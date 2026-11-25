import 'dart:ui' show SemanticsAction;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';

void main() {
  for (final poppable in [false, true]) {
    for (final drawer in [false, true]) {
      for (final preferBack in [false, true]) {
        testWidgets('leading announces the action available on this route '
            '(canPop=$poppable, drawer=$drawer, preferBack=$preferBack)', (
          tester,
        ) async {
          final navigator = GlobalKey<NavigatorState>();
          final scaffold = GlobalKey<ScaffoldState>();
          var hasDrawer = drawer;
          late StateSetter updateDrawer;
          Widget screen = StatefulBuilder(
            builder: (context, setState) {
              updateDrawer = setState;
              return Scaffold(
                key: scaffold,
                drawer: hasDrawer
                    ? const Drawer(child: Text('Drawer contents'))
                    : null,
                body: CustomScrollView(
                  slivers: [
                    DocTypeListHeader(
                      title: 'Item',
                      automaticallyImplyLeading: preferBack,
                    ),
                  ],
                ),
              );
            },
          );

          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              home: poppable ? const Scaffold(body: Text('Root page')) : screen,
            ),
          );
          if (poppable) {
            navigator.currentState!.push<void>(
              MaterialPageRoute(builder: (_) => screen),
            );
          }
          await tester.pumpAndSettle();

          final usesDrawer = drawer && (!poppable || !preferBack);
          final context = tester.element(find.byType(DocTypeListHeader));
          final strings = MaterialLocalizations.of(context);
          final menu = find.byTooltip(strings.openAppDrawerTooltip);
          final back = find.byTooltip(strings.backButtonTooltip);
          expect(menu, usesDrawer ? findsOneWidget : findsNothing);
          expect(back, !usesDrawer && poppable ? findsOneWidget : findsNothing);

          if (!usesDrawer && !poppable) {
            updateDrawer(() => hasDrawer = true);
            await tester.pumpAndSettle();
            await tester.tap(menu);
            await tester.pumpAndSettle();
            expect(scaffold.currentState!.isDrawerOpen, isTrue);
            return;
          }

          final button = usesDrawer ? menu : back;
          final icon = usesDrawer ? Icons.menu : Icons.arrow_back;
          expect(
            find.descendant(of: button, matching: find.byIcon(icon)),
            findsOneWidget,
          );
          final node = tester.getSemantics(button);
          expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );

          // Exercise all activation sources across the route matrix.
          if (poppable && drawer) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          } else if (preferBack) {
            node.owner!.performAction(node.id, SemanticsAction.tap);
          } else {
            await tester.tap(button);
          }
          await tester.pumpAndSettle();

          if (usesDrawer) {
            expect(scaffold.currentState!.isDrawerOpen, isTrue);
            expect(navigator.currentState!.canPop(), isTrue);
            scaffold.currentState!.closeDrawer();
            await tester.pumpAndSettle();
            updateDrawer(() => hasDrawer = false);
            await tester.pumpAndSettle();
            expect(menu, findsNothing);
            expect(back, poppable ? findsOneWidget : findsNothing);
          } else {
            expect(find.text('Root page'), findsOneWidget);
            expect(navigator.currentState!.canPop(), isFalse);
          }
        });
      }
    }
  }
}
