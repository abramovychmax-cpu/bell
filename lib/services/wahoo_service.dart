import 'dart:io';
import 'package:flutter/services.dart';

/// Checks whether the Wahoo companion app can receive call notifications.
///
/// Android: verifies that at least one notification listener is active
///          (not Wahoo-specific, since package names vary by region/build).
///          Also checks if the companion app is installed.
/// iOS:     nothing to check — CallKit events are delivered by the OS.
class WahooService {
  static const _ch = MethodChannel('com.bell/wahoo');

  // Package names of known Wahoo companion apps (checked via native channel).
  // Listed here for reference — the actual check is done in MainActivity.kt.
  static const List<String> knownWahooPackages = [
    'com.wahooligan.android.elmnt',   // ELEMNT
    'com.wahooligan.android.bolt',    // BOLT
    'com.wahooligan.android.roam',    // ROAM
  ];

  /// Returns true when the phone is properly set up to mirror call
  /// notifications to a Wahoo head-unit.
  Future<WahooStatus> check() async {
    if (Platform.isIOS) {
      // On iOS CallKit fires system-wide — no extra setup needed.
      return WahooStatus(notificationListenerEnabled: true, appInstalled: true);
    }

    bool listenerEnabled = false;
    bool appInstalled = false;

    try {
      listenerEnabled =
          await _ch.invokeMethod<bool>('isNotificationListenerEnabled') ?? false;
      appInstalled =
          await _ch.invokeMethod<bool>('isWahooInstalled') ?? false;
    } on PlatformException {
      // Can't determine — flag as unknown (false).
    } on MissingPluginException {
      // Channel not yet registered (first run / test).
    }

    return WahooStatus(
      notificationListenerEnabled: listenerEnabled,
      appInstalled: appInstalled,
    );
  }

  /// Opens Android's Notification Access settings screen.
  Future<void> openNotificationSettings() async {
    try {
      await _ch.invokeMethod<void>('openNotificationSettings');
    } catch (_) {}
  }
}

class WahooStatus {
  final bool notificationListenerEnabled;
  final bool appInstalled;

  const WahooStatus({
    required this.notificationListenerEnabled,
    required this.appInstalled,
  });

  bool get allGood => notificationListenerEnabled && appInstalled;
}
