import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:uuid/uuid.dart';
import 'log_service.dart';

/// Fires a fake incoming-call notification that the Wahoo ELEMNT mirrors.
///
/// The Wahoo companion app forwards all phone notifications over Bluetooth.
/// A CallStyle / CallKit notification appears on the Wahoo head-unit as an
/// incoming call; the configured rider message becomes the "caller name".
///
/// Android 12+ : native CallStyle notification via MethodChannel.
/// Android <12 : full-screen high-priority notification fallback.
/// iOS          : CallKit via flutter_callkit_incoming package.
class CallService {
  static const _channel = MethodChannel('com.bell/call');
  static final _uuid = Uuid();

  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _activeCallId;

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
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
    int durationSec = 6,
  }) async {
    if (!_initialized) await init();

    Log.i('Call', 'triggerCall "$callerName"  platform=${Platform.isIOS ? "iOS" : "Android"}');
    if (Platform.isIOS) {
      await _showIosCall(callerName);
    } else {
      await _showAndroidCall(callerName);
    }

    // Auto-dismiss after durationSec.
    Future.delayed(Duration(seconds: durationSec), _dismiss);
  }

  // ── iOS: flutter_callkit_incoming ──────────────────────────────────────────
  Future<void> _showIosCall(String callerName) async {
    _activeCallId = _uuid.v4();
    Log.i('Call', 'iOS CallKit → showCallkitIncoming id=$_activeCallId name="$callerName"');
    final params = CallKitParams(
      id: _activeCallId,
      nameCaller: callerName,
      appName: 'Bell',
      type: 1,
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      ios: const IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        supportsHolding: false,
        supportsDTMF: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        configureAudioSession: false,
        ringtonePath: 'system_ringtone_default',
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
      ),
    );
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  Future<void> _endIosCall() async {
    if (_activeCallId == null) return;
    await FlutterCallkitIncoming.endCall(_activeCallId!);
    _activeCallId = null;
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
      await _endIosCall();
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
