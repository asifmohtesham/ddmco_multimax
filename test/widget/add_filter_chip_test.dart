import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/add_filter_chip.dart';
import 'package:multimax/main.dart';

Widget _host({required Brightness brightness, required Widget child}) {
  return MaterialApp(
    theme: buildAppTheme(AppScheme.of(brightness), brightness),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('renders "+ Filter" label with an add icon', (tester) async {
    await tester.pumpWidget(_host(
      brightness: Brightness.light,
      child: AddFilterChip(onTap: () {}),
    ));
    expect(find.text('Filter'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('tapping the chip fires onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host(
      brightness: Brightness.light,
      child: AddFilterChip(onTap: () => tapped = true),
    ));
    await tester.tap(find.byType(AddFilterChip));
    expect(tapped, isTrue);
  });
}
