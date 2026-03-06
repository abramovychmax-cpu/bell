import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'services/storage_service.dart';
import 'services/call_service.dart';
import 'services/ble_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = StorageService();
  await storage.init();

  final callService = CallService();
  await callService.init();

  final bleService = BleService(
    storage: storage,
    onHoldDetected: () => callService.triggerCall(
      callerName: storage.callMessage,
    ),
  );

  // Android: start foreground service so BLE connection survives screen-off.
  _initForegroundTask();

  runApp(BellApp(ble: bleService, storage: storage));

  // Start BLE after the widget tree is ready.
  await bleService.start();
}

void _initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'bell_fg',
      channelName: 'Bell — Ride Active',
      channelDescription: 'Keeps DI2 BLE connection alive during your ride.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      // Wake lock every 5 min just as heartbeat; BLE itself is interrupt-driven.
      eventAction: ForegroundTaskEventAction.repeat(300000),
      autoRunOnBoot: true,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );
}
