import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';

Widget _host({required Brightness brightness, required Widget child}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('renders label, icon and a close affordance', (tester) async {
    await tester.pumpWidget(_host(
      brightness: Brightness.light,
      child: FilterChipWidget(
          icon: Icons.label, label: 'Status: Draft', onDeleted: () {}),
    ));
    expect(find.text('Status: Draft'), findsOneWidget);
    expect(find.byIcon(Icons.label), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('tapping the close icon calls onDeleted', (tester) async {
    var deleted = false;
    await tester.pumpWidget(_host(
      brightness: Brightness.light,
      child: FilterChipWidget(
          icon: Icons.label, label: 'x', onDeleted: () => deleted = true),
    ));
    await tester.tap(find.byIcon(Icons.close));
    expect(deleted, isTrue);
  });

  testWidgets('active style: maroon-tinted fill + primary text in light', (tester) async {
    await tester.pumpWidget(_host(
      brightness: Brightness.light,
      child: FilterChipWidget(icon: Icons.label, label: 'x', onDeleted: () {}),
    ));
    final scheme = AppScheme.light;
    // Label text uses primary.
    final text = tester.widget<Text>(find.text('x'));
    expect(text.style?.color, scheme.primary);
    // Container fill = primary @12% over fg; border present.
    final box = tester.widget<Container>(
      find.ancestor(of: find.text('x'), matching: find.byType(Container)).first,
    );
    final deco = box.decoration as BoxDecoration;
    expect(deco.color, Color.alphaBlend(scheme.primary.withValues(alpha: 0.12), scheme.fg));
    expect(deco.borderRadius, BorderRadius.circular(AppRadius.full));
    expect(deco.border, isNotNull);
  });

  testWidgets('resolves against dark scheme when brightness is dark', (tester) async {
    await tester.pumpWidget(_host(
      brightness: Brightness.dark,
      child: FilterChipWidget(icon: Icons.label, label: 'x', onDeleted: () {}),
    ));
    final text = tester.widget<Text>(find.text('x'));
    expect(text.style?.color, AppScheme.dark.primary);
    expect(text.style?.color, isNot(AppScheme.light.primary));
  });
}
