import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:multimax/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Smoke test Landed Cost Voucher', (WidgetTester tester) async {
    // Start the app
    await app.main();
    await tester.pumpAndSettle();

    // The user might be logged out if data is cleared.
    // If we are on login screen, we pause and prompt the user to login manually.
    final loginTitle = find.text('Login');
    if (loginTitle.evaluate().isNotEmpty) {
      print('Please manually log into the app on your device to continue the smoke test...');
      while (find.text('Login').evaluate().isNotEmpty) {
        await tester.pump(const Duration(seconds: 1));
      }
      print('Login detected! Continuing with smoke test...');
      await tester.pumpAndSettle();
    }

    // Open the drawer
    final ScaffoldState state = tester.firstState(find.byType(Scaffold));
    state.openDrawer();
    await tester.pumpAndSettle();

    // Find the Stock section in the drawer
    final stockFinder = find.text('Stock');
    expect(stockFinder, findsOneWidget, reason: 'Stock section not found in drawer');
    
    // Tap to expand the Stock section
    await tester.tap(stockFinder);
    await tester.pumpAndSettle();

    // Find Landed Cost Voucher and tap it
    final lcvFinder = find.text('Landed Cost Voucher');
    // Scroll until it's visible if necessary
    await tester.scrollUntilVisible(lcvFinder, 100.0, scrollable: find.byType(Scrollable).last);
    
    expect(lcvFinder, findsOneWidget, reason: 'Landed Cost Voucher not found in drawer');
    await tester.tap(lcvFinder);
    await tester.pumpAndSettle();

    // Verify we are on the Landed Cost Vouchers screen
    expect(find.text('Landed Cost Vouchers'), findsWidgets, reason: 'Did not navigate to Landed Cost Vouchers screen');
    
    // Also verify the floating action button exists to create a new one
    expect(find.byType(FloatingActionButton), findsOneWidget, reason: 'Missing FAB to create new voucher');
  });
}
