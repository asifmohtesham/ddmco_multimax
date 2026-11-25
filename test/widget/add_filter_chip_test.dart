import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/add_filter_chip.dart';
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';
import 'package:multimax/main.dart';

Widget _host({required Brightness brightness, required Widget child}) {
  return MaterialApp(
    theme: buildAppTheme(AppScheme.of(brightness), brightness),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('renders "+ Filter" label with an add icon', (tester) async {
    await tester.pumpWidget(
      _host(
        brightness: Brightness.light,
        child: AddFilterChip(onTap: () {}),
      ),
    );
    expect(find.text('Filter'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('tapping the chip fires onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _host(
        brightness: Brightness.light,
        child: AddFilterChip(onTap: () => tapped = true),
      ),
    );
    await tester.tap(find.byType(AddFilterChip));
    expect(tapped, isTrue);
  });

  testWidgets('Add filter names one padded native button', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        brightness: Brightness.dark,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: AddFilterChip(onTap: () => taps++),
        ),
      ),
    );
    final action = find.byType(TextButton);
    final node = tester.getSemantics(action).getSemanticsData();
    final rect = tester.getRect(action);
    expect(node.label, 'Add filter');
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.hasAction(SemanticsAction.tap), isTrue);
    expect(find.byTooltip('Add filter'), findsOneWidget);
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));
    expect(tester.getSize(find.byType(HeaderPill)).height, 34);
    expect(
      tester.getCenter(find.byIcon(Icons.add)).dx,
      greaterThan(tester.getCenter(find.text('Filter')).dx),
    );
    await tester.tapAt(rect.topLeft + const Offset(1, 1));
    await tester.tapAt(rect.bottomRight + const Offset(-1, -1));
    expect(taps, 2);
  });
}
