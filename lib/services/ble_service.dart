import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/di2_device.dart';
import 'di2_parser.dart';
import 'hold_detector.dart';
import 'log_service.dart';
import 'storage_service.dart';

enum BleStatus { off, idle, scanning, connecting, connected, disconnected }

/// Battery-efficient BLE manager for the Shimano EW-WU111.
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

  bool _disposed = false;
  int _reconnectDelayMs = 2000;
  static const int _maxReconnectDelayMs = 60000;

  // Known Shimano D-Fly BLE service / characteristic (community reverse-engineered).
  // The app also subscribes to ALL notify characteristics as a fallback for
  // different EW-WU111 firmware versions.
  static final Guid _dFlyServiceUuid =
      Guid('a026ee01-0a7d-4ab3-97fa-f1500f9feb8b');
  static final Guid _dFlyButtonCharUuid =
      Guid('a026e002-0a7d-4ab3-97fa-f1500f9feb8b');

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> start() async {
    _rebuildHoldDetector();
    final paired = _storage.pairedDevice;
    Log.i('BLE', 'start() — paired device: ${paired?.name ?? "none"}  climbA=${_storage.climbAEnabled}  climbB=${_storage.climbBEnabled}  holdMs=${_storage.holdDurationMs}');
    if (paired != null) await _connectById(paired.remoteId);
  }

  /// Returns a stream of scan results for the pairing screen.
  /// Uses low-power scan mode to minimise battery draw.
  Stream<ScanResult> scan({int timeoutSec = 12}) {
    _setStatus(BleStatus.scanning);
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
    await device.requestConnectionPriority(
      connectionPriorityRequest: ConnectionPriority.balanced,
    );

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
      final isKnownSvc = svc.serviceUuid == _dFlyServiceUuid;
      Log.i('BLE', '  service ${svc.serviceUuid}${isKnownSvc ? " ← D-Fly ✓" : ""}');
      for (final char in svc.characteristics) {
        if (!char.properties.notify) continue;
        final isKnownChar = isKnownSvc &&
            char.characteristicUuid == _dFlyButtonCharUuid;
        Log.i('BLE', '    char ${char.characteristicUuid}  notify=true${isKnownChar ? " ← button char ✓" : ""}');
        await char.setNotifyValue(true);

        final sub = char.lastValueStream.listen((data) {
          if (data.isEmpty) return;
          // Log every raw packet so we can reverse-engineer new firmware
          Log.raw('BLE', 'notify ${char.characteristicUuid}', data);
          final active = Di2Parser.isEnabledActive(
            data,
            climbA: _storage.climbAEnabled,
            climbB: _storage.climbBEnabled,
          );
          Log.i('BLE',
            'packet → comp=0x${data.length > 3 ? data[3].toRadixString(16).padLeft(2,"0") : "?"}  '
            'byte4=0x${data.length > 4 ? data[4].toRadixString(16).padLeft(2,"0") : "?"}  '
            'isButtonDown=${Di2Parser.isButtonDown(data)}  '
            'enabledActive=$active  '
            'climbAen=${_storage.climbAEnabled}  climbBen=${_storage.climbBEnabled}');
          if (active) {
            Log.i('BLE', 'Enabled button active → feeding HoldDetector');
            _holdDetector?.onPacket();
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
    for (final s in _notifySubs) { s.cancel(); }
    super.dispose();
  }
}
