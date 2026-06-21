import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';

Widget _host({required Brightness brightness}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness, useMaterial3: true),
    home: Scaffold(
      body: CustomScrollView(
        slivers: const [
          DocTypeFormHeader(
            title: 'WO-2024-00123',
            docType: 'Work Order',
            statusLabel: 'Draft',
          ),
          SliverToBoxAdapter(child: SizedBox(height: 1200)),
        ],
      ),
    ),
  );
}

Material _headerSurface(WidgetTester tester, Color primary) {
  // The header's painted bar is the Material whose color == colorScheme.primary.
  final materials = tester.widgetList<Material>(find.byType(Material));
  return materials.firstWhere((m) => m.color == primary,
      orElse: () => throw TestFailure('No Material painted with primary color'));
}

void main() {
  testWidgets('form header bar is painted solid primary (light)', (tester) async {
    await tester.pumpWidget(_host(brightness: Brightness.light));
    await tester.pump();
    final primary = ThemeData(brightness: Brightness.light, useMaterial3: true)
        .colorScheme
        .primary;
    expect(() => _headerSurface(tester, primary), returnsNormally);
  });

  testWidgets('form header bar is painted solid primary (dark)', (tester) async {
    await tester.pumpWidget(_host(brightness: Brightness.dark));
    await tester.pump();
    final primary = ThemeData(brightness: Brightness.dark, useMaterial3: true)
        .colorScheme
        .primary;
    expect(() => _headerSurface(tester, primary), returnsNormally);
  });

  testWidgets('expanded doc-name title uses onPrimary', (tester) async {
    await tester.pumpWidget(_host(brightness: Brightness.light));
    await tester.pump();
    final cs = ThemeData(brightness: Brightness.light, useMaterial3: true).colorScheme;
    // The 24sp expanded title Text.
    final titleText = tester.widgetList<Text>(find.text('WO-2024-00123'))
        .firstWhere((t) => (t.style?.fontSize ?? 0) >= 20);
    expect(titleText.style?.color, cs.onPrimary);
  });
}
