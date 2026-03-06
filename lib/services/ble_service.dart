import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/di2_device.dart';
import 'di2_parser.dart';
import 'hold_detector.dart';
import 'log_service.dart';
import 'storage_service.dart';

enum BleStatus { off, idle, scanning, connecting, connected, disconnected }

/// Battery-efficient BLE manager for Shimano Di2 (RD-R8150 / EW-WU111).
///
/// Design principles
/// ─────────────────
/// • Scan ONCE to pair, then reconnect by saved device ID — no continuous scan.
/// • All button data arrives via BLE NOTIFY — zero CPU polling cost at rest.
/// • Automatic exponential back-off reconnect (2 s → 60 s max).
/// • "Balanced" connection priority: lower duty cycle = less heat + drain.
class BleService extends ChangeNotifier {
  final StorageService _storage;
  final void Function() onHoldDetected;

  BleService({required StorageService storage, required this.onHoldDetected})
      : _storage = storage;

  // ── Public state ───────────────────────────────────────────────────────────
  BleStatus status = BleStatus.idle;
  BluetoothDevice? connectedDevice;

  // ── Internals ──────────────────────────────────────────────────────────────
  HoldDetector? _holdDetector;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  final List<StreamSubscription<List<int>>> _notifySubs = [];
  StreamSubscription<dynamic>? _wahooEventSub;

  static const _wahooEventChannel = EventChannel('com.bell/wahoo_events');

  bool _disposed = false;
  int _reconnectDelayMs = 2000;
  static const int _maxReconnectDelayMs = 60000;

  // ── Shimano BLE service / characteristic UUIDs ────────────────────────────
  // Legacy D-Fly (EW-WU111, SM-EWW01, older junction boxes)
  static final Guid _dFlyServiceUuid =
      Guid('a026ee01-0a7d-4ab3-97fa-f1500f9feb8b');
  static final Guid _dFlyButtonCharUuid =
      Guid('a026e002-0a7d-4ab3-97fa-f1500f9feb8b');

  // Shimano proprietary (RD-R8150, RD-R9250 and 12-speed Di2 in general)
  static final Guid _shimanoServiceUuid =
      Guid('ad0a1000-6101-414a-a001-0010c2e6f477');
  /// Gear/CSC data — subscribed for keep-alive; not parsed for button events.
  static final Guid _shimanoDataCharUuid =
      Guid('ad0a1001-6101-414a-a001-0010c2e6f477');
  /// Switch events: [switchId, actionCode] — the button characteristic we act on.
  static final Guid _shimanoSwitchCharUuid =
      Guid('ad0a1002-6101-414a-a001-0010c2e6f477');

  // Both service UUIDs kept here for reference / future re-enabling of scan filter.
  // ignore: unused_element
  List<Guid> get _scanServiceUuids => [_dFlyServiceUuid, _shimanoServiceUuid];

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> start() async {
    _rebuildHoldDetector();
    final paired = _storage.pairedDevice;
    Log.i('BLE', 'start() — paired device: ${paired?.name ?? "none"}  climbA=${_storage.climbAEnabled}  climbB=${_storage.climbBEnabled}  holdMs=${_storage.holdDurationMs}');
    if (paired != null) await _connectById(paired.remoteId);
    _listenWahooEvents();
  }

  /// On Android: subscribe to Wahoo BT connect/disconnect events from
  /// MainActivity so we can auto-start the Di2 connection when the rider
  /// mounts their bike and the Wahoo head-unit pairs.
  void _listenWahooEvents() {
    if (!Platform.isAndroid) return;
    _wahooEventSub?.cancel();
    _wahooEventSub = _wahooEventChannel.receiveBroadcastStream().listen(
      (event) {
        Log.i('BLE', 'Wahoo event: $event');
        if (event == 'wahoo_connected') {
          final paired = _storage.pairedDevice;
          if (paired != null && status != BleStatus.connected && status != BleStatus.connecting) {
            Log.i('BLE', 'Wahoo connected → auto-connecting Di2');
            _connectById(paired.remoteId);
          }
        }
      },
      onError: (e) => Log.w('BLE', 'Wahoo event channel error: $e'),
    );
  }

  /// Returns a stream of scan results for the pairing screen.
  /// Filters by Shimano service UUIDs — catches both legacy D-Fly (EW-WU111)
  /// and 12-speed proprietary (RD-R8150 / RD-R9250).
  Stream<ScanResult> scan({int timeoutSec = 15}) {
    _setStatus(BleStatus.scanning);
    Log.i('BLE', 'Starting scan — no filter, showing all BLE devices');
    FlutterBluePlus.startScan(
      timeout: Duration(seconds: timeoutSec),
      androidScanMode: AndroidScanMode.lowPower,
    );
    return FlutterBluePlus.scanResults.expand((list) => list);
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    if (status == BleStatus.scanning) _setStatus(BleStatus.idle);
  }

  /// Persist [device] as the paired DI2 unit and connect to it.
  Future<void> pairAndConnect(BluetoothDevice device) async {
    await _storage.savePairedDevice(
      Di2Device(remoteId: device.remoteId.str, name: device.platformName),
    );
    await _connectById(device.remoteId.str);
  }

  /// Disconnect and forget the paired device.
  Future<void> unpair() async {
    _disposed = true;
    await _disconnect();
    await _storage.clearPairedDevice();
    _disposed = false;
    _setStatus(BleStatus.idle);
  }

  /// Call after the user changes the hold duration setting.
  void refreshHoldThreshold() => _rebuildHoldDetector();

  // ── Connection internals ───────────────────────────────────────────────────

  Future<void> _connectById(String remoteId) async {
    if (_disposed) return;
    Log.i('BLE', 'Connecting to $remoteId …');
    _setStatus(BleStatus.connecting);
    try {
      final device = BluetoothDevice.fromId(remoteId);
      await _attach(device);
    } catch (e) {
      Log.e('BLE', 'connect error: $e');
      _scheduleReconnect(remoteId);
    }
  }

  Future<void> _attach(BluetoothDevice device) async {
    await device.connect(autoConnect: false, mtu: null);

    connectedDevice = device;
    _reconnectDelayMs = 2000; // reset back-off on success
    Log.i('BLE', 'Connected to ${device.platformName} (${device.remoteId})');
    _setStatus(BleStatus.connected);

    // Balanced priority: ~100 ms BLE connection interval saves battery vs
    // "high" (7.5 ms) while still being fast enough for button detection.
    // Android only — iOS does not expose this API.
    if (Platform.isAndroid) {
      await device.requestConnectionPriority(
        connectionPriorityRequest: ConnectionPriority.balanced,
      );
    }

    _connStateSub?.cancel();
    _connStateSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _handleDisconnect(device.remoteId.str);
      }
    });

    await _subscribeAll(device);
  }

  Future<void> _subscribeAll(BluetoothDevice device) async {
    for (final s in _notifySubs) { s.cancel(); }
    _notifySubs.clear();

    final services = await device.discoverServices();
    Log.i('BLE', 'Discovered ${services.length} services');
    for (final svc in services) {
      final isKnownSvc = svc.serviceUuid == _dFlyServiceUuid ||
          svc.serviceUuid == _shimanoServiceUuid;
      Log.i('BLE', '  service ${svc.serviceUuid}${isKnownSvc ? " ← Shimano ✓" : ""}');
      for (final char in svc.characteristics) {
        if (!char.properties.notify) continue;

        final isSwitchChar = char.characteristicUuid == _shimanoSwitchCharUuid;
        final isLegacyChar = isKnownSvc &&
            char.characteristicUuid == _dFlyButtonCharUuid;
        final isGearChar = isKnownSvc &&
            char.characteristicUuid == _shimanoDataCharUuid;
        final label = isSwitchChar
            ? ' ← switch char ✓'
            : isLegacyChar
                ? ' ← legacy D-Fly char ✓'
                : isGearChar
                    ? ' ← gear/CSC data char'
                    : '';
        Log.i('BLE', '    char ${char.characteristicUuid}  notify=true$label');
        await char.setNotifyValue(true);

        final sub = char.lastValueStream.listen((data) {
          if (data.isEmpty) return;
          // Log every raw packet — invaluable for firmware reverse-engineering
          Log.raw('BLE', 'notify ${char.characteristicUuid}', data);

          if (isSwitchChar) {
            // ── New 1002 path: hardware-classified switch events ──────────
            final event = Di2Parser.parseSwitchEvent(data);
            Log.i('BLE',
              'switch event → ${event ?? "too short (len=${data.length})"}'  
              '  climbAen=${_storage.climbAEnabled}  climbBen=${_storage.climbBEnabled}');
            if (event != null && event.action == Di2Action.longPress) {
              final enabled =
                  (event.button == Di2Button.climbA && _storage.climbAEnabled) ||
                  (event.button == Di2Button.climbB && _storage.climbBEnabled);
              if (enabled) {
                Log.i('BLE', 'Long press on enabled button → triggering hold callback');
                onHoldDetected();
              }
            }
          } else {
            // ── Legacy D-Fly path: software HoldDetector ─────────────────
            final active = Di2Parser.isEnabledActive(
              data,
              climbA: _storage.climbAEnabled,
              climbB: _storage.climbBEnabled,
            );
            Log.i('BLE',
              'legacy packet → '
              'comp=0x${data.length > 3 ? data[3].toRadixString(16).padLeft(2, "0") : "?"}  '
              'byte4=0x${data.length > 4 ? data[4].toRadixString(16).padLeft(2, "0") : "?"}  '
              'isButtonDown=${Di2Parser.isButtonDown(data)}  '
              'enabledActive=$active');
            if (active) {
              Log.i('BLE', 'Enabled button active → feeding HoldDetector');
              _holdDetector?.onPacket();
            }
          }
        });
        _notifySubs.add(sub);
      }
    }
    Log.i('BLE', 'Listening on ${_notifySubs.length} notify characteristics');
  }

  void _handleDisconnect(String remoteId) {
    Log.w('BLE', 'Disconnected from $remoteId');
    connectedDevice = null;
    _setStatus(BleStatus.disconnected);
    for (final s in _notifySubs) { s.cancel(); }
    _notifySubs.clear();
    if (_storage.autoReconnect && !_disposed) _scheduleReconnect(remoteId);
  }

  void _scheduleReconnect(String remoteId) {
    if (_disposed) return;
    Log.i('BLE', 'Retry in ${_reconnectDelayMs}ms …');
    Future.delayed(Duration(milliseconds: _reconnectDelayMs), () {
      if (!_disposed) _connectById(remoteId);
    });
    _reconnectDelayMs =
        (_reconnectDelayMs * 2).clamp(2000, _maxReconnectDelayMs);
  }

  Future<void> _disconnect() async {
    _connStateSub?.cancel();
    for (final s in _notifySubs) { s.cancel(); }
    _notifySubs.clear();
    try {
      await connectedDevice?.disconnect();
    } catch (_) {}
    connectedDevice = null;
  }

  void _rebuildHoldDetector() {
    _holdDetector?.dispose();
    _holdDetector = HoldDetector(
      onHold: onHoldDetected,
      holdThresholdMs: _storage.holdDurationMs,
    );
  }

  void _setStatus(BleStatus s) {
    status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _holdDetector?.dispose();
    _connStateSub?.cancel();
    _wahooEventSub?.cancel();
    for (final s in _notifySubs) { s.cancel(); }
    super.dispose();
  }
}
