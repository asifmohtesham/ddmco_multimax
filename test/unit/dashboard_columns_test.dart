import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/home/home_screen.dart';

/// In-memory stand-in for the GetStorage box used by StorageService.
class _FakeBox {
  final Map<String, dynamic> _m = {};
  T? read<T>(String key) => _m[key] as T?;
  Future<void> write(String key, dynamic value) async => _m[key] = value;
  bool hasData(String key) => _m.containsKey(key);
  Future<void> remove(String key) async => _m.remove(key);
}

void main() {
  group('StorageService dashboard columns', () {
    test('defaults to 1 column when unset', () {
      final s = StorageService.withStorage(_FakeBox());
      expect(s.getDashboardColumns(), 1);
    });

    test('round-trips 1 and 2', () async {
      final s = StorageService.withStorage(_FakeBox());
      await s.saveDashboardColumns(2);
      expect(s.getDashboardColumns(), 2);
      await s.saveDashboardColumns(1);
      expect(s.getDashboardColumns(), 1);
    });

    test('clamps stale or corrupt values to the 1-column default', () async {
      final s = StorageService.withStorage(_FakeBox());
      await s.saveDashboardColumns(3); // legacy 3-column layout is gone
      expect(s.getDashboardColumns(), 1);
      await s.saveDashboardColumns(0);
      expect(s.getDashboardColumns(), 1);
    });
  });

  group('DashboardColumnsToggle', () {
    Future<void> pump(WidgetTester tester,
        {required int columns,
        required ValueChanged<int> onChanged,
        Brightness brightness = Brightness.light}) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: Center(
            child: DashboardColumnsToggle(
              columns: columns,
              onChanged: onChanged,
            ),
          ),
        ),
      ));
    }

    testWidgets('renders both options', (tester) async {
      await pump(tester, columns: 2, onChanged: (_) {});
      expect(find.byIcon(Icons.view_agenda_outlined), findsOneWidget);
      expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    });

    testWidgets('tapping the 1-column option reports 1', (tester) async {
      int? reported;
      await pump(tester, columns: 2, onChanged: (v) => reported = v);
      await tester.tap(find.byIcon(Icons.view_agenda_outlined));
      expect(reported, 1);
    });

    testWidgets('tapping the 2-column option reports 2', (tester) async {
      int? reported;
      await pump(tester, columns: 1, onChanged: (v) => reported = v);
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      expect(reported, 2);
    });

    testWidgets('renders in dark mode', (tester) async {
      await pump(tester,
          columns: 1, onChanged: (_) {}, brightness: Brightness.dark);
      expect(find.byIcon(Icons.view_agenda_outlined), findsOneWidget);
    });
  });
}
