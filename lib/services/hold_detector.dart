import 'dart:async';

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
    _pressStart ??= DateTime.now();
    _triggered = false;

    // Reset the "silence → button released" timer.
    _releaseTimer?.cancel();
    _releaseTimer = Timer(Duration(milliseconds: packetTimeoutMs), _onRelease);
  }

  void _onRelease() {
    final start = _pressStart;
    if (start == null) return;

    final held = DateTime.now().difference(start).inMilliseconds;
    _pressStart = null;

    if (!_triggered && held >= holdThresholdMs) {
      _triggered = true;
      onHold();
    }
  }

  void dispose() {
    _releaseTimer?.cancel();
  }
}
