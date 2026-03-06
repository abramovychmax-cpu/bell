// Smoke test — verifies the app renders without crashing.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bell/app.dart';
import 'package:bell/services/storage_service.dart';
import 'package:bell/services/ble_service.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();

    final ble = BleService(
      storage: storage,
      onHoldDetected: () {},
    );

    await tester.pumpWidget(BellApp(ble: ble, storage: storage));
    await tester.pump();

    expect(find.text('Bell'), findsOneWidget);
  });
}
