// Regression test for the Dashboard app-bar colour bug: the SliverPersistentHeader
// caches its child based on _DocTypeListHeaderDelegate.shouldRebuild(). When only
// the app's resolved Theme (Brightness) changes — no title/filter/search/action
// diff — shouldRebuild must still return true, or the header keeps painting the
// old theme's colorScheme.surface while the rest of the screen (built fresh every
// time) already reflects the new theme. Confirmed on-device: header pixel #1F262C
// (AppScheme.dark.fg) while the Scaffold body was #FFF0EF (AppScheme.light's
// surfaceContainerLow) — i.e. the header was frozen on a stale dark snapshot after
// the persisted theme_mode changed to light.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/main.dart';

Widget _host(Brightness brightness) {
  final theme = brightness == Brightness.dark
      ? buildAppTheme(AppScheme.dark, Brightness.dark)
      : buildAppTheme(AppScheme.light, Brightness.light);
  return MaterialApp(
    theme: theme,
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          const DocTypeListHeader(
            title: 'Dashboard',
            automaticallyImplyLeading: false,
          ),
        ],
      ),
    ),
  );
}

SliverPersistentHeaderDelegate _delegateOf(WidgetTester tester) {
  final widget =
      tester.widget<SliverPersistentHeader>(find.byType(SliverPersistentHeader));
  return widget.delegate;
}

void main() {
  testWidgets(
      'DocTypeListHeader delegate requests a rebuild when brightness changes '
      'even though title/filters/search/actions are unchanged', (tester) async {
    await tester.pumpWidget(_host(Brightness.dark));
    await tester.pumpAndSettle();
    final darkDelegate = _delegateOf(tester);

    await tester.pumpWidget(_host(Brightness.light));
    await tester.pumpAndSettle();
    final lightDelegate = _delegateOf(tester);

    expect(
      lightDelegate.shouldRebuild(darkDelegate),
      isTrue,
      reason: 'a pure brightness change must invalidate the cached header — '
          'otherwise SliverPersistentHeader keeps painting the old theme colour',
    );
  });
}
