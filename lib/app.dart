import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'services/ble_service.dart';
import 'services/storage_service.dart';
import 'screens/home_screen.dart';

class BellApp extends StatelessWidget {
  final BleService ble;
  final StorageService storage;

  const BellApp({super.key, required this.ble, required this.storage});

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: 'Bell',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE53935),
            brightness: Brightness.dark,
          ),
        ),
        home: HomeScreen(ble: ble, storage: storage),
      ),
    );
  }
}
