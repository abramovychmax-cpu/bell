import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'log_service.dart';

/// Fires a notification that the Wahoo ELEMNT mirrors via ANCS.
///
/// The Wahoo companion app forwards all phone notifications over Bluetooth.
/// Each call to [triggerCall] shows a time-sensitive banner on iOS (mirrors
/// to Wahoo as a notification tile) and a CallStyle notification on Android.
///
/// Android 12+ : native CallStyle notification via MethodChannel.
/// Android <12 : full-screen high-priority notification fallback.
/// iOS          : time-sensitive local notification (flutter_local_notifications).
class CallService {
  static const _channel = MethodChannel('com.bell/call');

  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _notifCounter = 0; // incremented each trigger for unique ANCS delivery
  int _lastNotifId = -1;

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestSoundPermission: true,
      requestBadgePermission: false,
    );
    await _notif.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
  }

  /// Show a fake call notification.  [callerName] is displayed on the Wahoo
  /// screen as the incoming-call name.  Auto-cancelled after [durationSec].
  Future<void> triggerCall({
    required String callerName,
    int durationSec = 2,
  }) async {
    if (!_initialized) await init();

    Log.i('Call', 'triggerCall "$callerName"  platform=${Platform.isIOS ? "iOS" : "Android"}');
    if (Platform.isIOS) {
      await _showIosNotif(callerName);
    } else {
      await _showAndroidCall(callerName);
    }

    // Auto-dismiss after durationSec.
    Future.delayed(Duration(seconds: durationSec), _dismiss);
  }

  // ── iOS: time-sensitive local notification (mirrors to Wahoo via ANCS) ──────
  // Each call uses a NEW notification ID so iOS sends a fresh ANCS event to
  // the Wahoo. Updating the same ID in-place does NOT generate a new ANCS push.
  Future<void> _showIosNotif(String callerName) async {
    // Cancel the previous notification so it doesn't pile up on the iPhone.
    if (_lastNotifId >= 0) await _notif.cancel(_lastNotifId);
    final id = ++_notifCounter % 1000; // keep IDs in a small rolling window
    _lastNotifId = id;
    Log.i('Call', 'iOS local notif id=$id → "$callerName"');
    const details = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
      presentBanner: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    await _notif.show(
      id,
      'Bell',
      callerName,
      const NotificationDetails(iOS: details),
    );
  }

  // ── Android: MethodChannel → CallStyle notification ────────────────────────
  Future<void> _showAndroidCall(String callerName) async {
    bool nativeOk = false;
    try {
      await _channel.invokeMethod<void>('showCall', {'callerName': callerName});
      nativeOk = true;
      Log.i('Call', 'Android MethodChannel showCall OK');
    } on PlatformException catch (e) {
      nativeOk = false;
      Log.e('Call', 'MethodChannel PlatformException: $e');
    } on MissingPluginException catch (e) {
      nativeOk = false;
      Log.e('Call', 'MissingPluginException: $e');
    }

    if (!nativeOk) {
      Log.w('Call', 'Falling back to local notification');
      await _showFallbackNotification(callerName);
    }
  }

  Future<void> _dismiss() async {
    if (Platform.isIOS) {
      if (_lastNotifId >= 0) await _notif.cancel(_lastNotifId);
    } else {
      await _notif.cancel(_kNotifId);
      try {
        await _channel.invokeMethod<void>('dismissCall');
      } catch (_) {}
    }
  }

  Future<void> _showFallbackNotification(String callerName) async {
    const androidDetails = AndroidNotificationDetails(
      'bell_call_ch',
      'Rider Alert',
      channelDescription: 'DI2 hold-button call alerts',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
      autoCancel: true,
      playSound: true,
    );
    await _notif.show(
      _kNotifId,
      callerName,
      'DI2 Rider Alert',
      const NotificationDetails(android: androidDetails),
    );
  }

  static const int _kNotifId = 42;
}
