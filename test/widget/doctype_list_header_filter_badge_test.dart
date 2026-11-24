// Keep the app's shared Material APIs until its Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/count_badge.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(800, 360),
    const Size(800, 1280),
    const Size(1280, 800),
  ]) {
    testWidgets(
      'filter badge stays inside toolbar at ${size.width} × ${size.height}',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const title = 'Item Variant Details';
        final filters = <String, dynamic>{'item_group': 'Belts'}.obs;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  DocTypeListHeader(
                    title: title,
                    automaticallyImplyLeading: false,
                    activeFilters: filters,
                    onFilterTap: () {},
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 2000)),
                ],
              ),
            ),
          ),
        );

        void expectBadgeInsideToolbar() {
          final toolbar = tester.getRect(find.byType(NavigationToolbar));
          final badge = tester.getRect(find.byType(CountBadge));
          expect(badge.left, greaterThanOrEqualTo(toolbar.left));
          expect(badge.right, lessThanOrEqualTo(toolbar.right));
          expect(badge.right, lessThanOrEqualTo(size.width));
          expect(badge.top, greaterThanOrEqualTo(toolbar.top));
          expect(badge.bottom, lessThanOrEqualTo(toolbar.bottom));
        }

        expect(
          find.descendant(
            of: find.byType(NavigationToolbar),
            matching: find.text(title),
          ),
          findsNothing,
        );
        expectBadgeInsideToolbar();

        await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(NavigationToolbar),
            matching: find.text(title),
          ),
          findsOneWidget,
        );
        expectBadgeInsideToolbar();
      },
    );
  }
}
