import 'dart:async';
import 'log_service.dart';

/// Distinguishes a short click from a deliberate hold on the DI2 button.
///
/// Each time a BLE notification packet arrives (indicating the button is
/// active), call [onPacket]. That resets an internal liveness timer.
/// When the button is first pressed the hold timer starts; if no new packet
/// arrives within [packetTimeoutMs] the button is considered released.
/// If the button was held for at least [holdThresholdMs] before release, the
/// [onHold] callback fires.
///
/// Battery note: this is purely timer-based – no polling, zero idle CPU cost.
class HoldDetector {
  final int holdThresholdMs;   // default 800 ms
  final int packetTimeoutMs;   // silence window that means "button up"
  final void Function() onHold;

  HoldDetector({
    required this.onHold,
    this.holdThresholdMs = 800,
    this.packetTimeoutMs = 200,
  });

  Timer? _releaseTimer;
  DateTime? _pressStart;
  bool _triggered = false;

  /// Call this every time a button-down BLE notification arrives.
  void onPacket() {
    final isFirstPacket = _pressStart == null;
    _pressStart ??= DateTime.now();
    _triggered = false;
    if (isFirstPacket) Log.i('Hold', 'Button press started — hold threshold=${holdThresholdMs}ms');

    // Reset the "silence → button released" timer.
    _releaseTimer?.cancel();
    _releaseTimer = Timer(Duration(milliseconds: packetTimeoutMs), _onRelease);
  }

  void _onRelease() {
    final start = _pressStart;
    if (start == null) return;

    final held = DateTime.now().difference(start).inMilliseconds;
    _pressStart = null;

    Log.i('Hold', 'Button released — held=${held}ms  threshold=${holdThresholdMs}ms  '
        'willFire=${!_triggered && held >= holdThresholdMs}');

    if (!_triggered && held >= holdThresholdMs) {
      _triggered = true;
      Log.i('Hold', '🔔 Hold threshold met — firing callback');
      onHold();
    }
  }

  void dispose() {
    _releaseTimer?.cancel();
  }
}
