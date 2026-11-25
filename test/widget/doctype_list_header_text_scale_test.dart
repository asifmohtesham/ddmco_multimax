// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';
import 'package:multimax/main.dart' show buildAppTheme;

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();

  @override
  double scale(double fontSize) => fontSize * (fontSize >= 20 ? 1.75 : 2);

  @override
  double get textScaleFactor => 2;
}

void main() {
  testWidgets(
    'header follows system scaling and each app preset exactly once',
    (tester) async {
      final controller = Get.put(
        ThemeController(persist: (_, _) async {}, restore: (_) async => null),
      );
      addTearDown(Get.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final filters = {'status': 'Draft'}.obs;
      const title = 'Item';
      const caption = 'Status: Draft';
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppScheme.light, Brightness.light),
          builder: (context, child) => Obx(
            () => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(controller.textSize.value.factor),
              ),
              child: child!,
            ),
          ),
          home: Scaffold(
            body: CustomScrollView(
              controller: scroll,
              slivers: [
                DocTypeListHeader(
                  title: title,
                  extraActions: [
                    SizedBox(
                      width: 48,
                      child: TextButton(
                        onPressed: () {},
                        child: const Text('A'),
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(onPressed: () {}, icon: const Icon(Icons.image)),
                  ],
                  activeFilters: filters,
                  onFilterTap: () {},
                  filterChipsBuilder: (_) => [
                    FilterChipWidget(
                      icon: Icons.flag,
                      label: caption,
                      onTap: () {},
                      onDeleted: () {},
                    ),
                  ],
                ),
                const SliverToBoxAdapter(child: Text('Body text')),
                const SliverToBoxAdapter(child: SizedBox(height: 1200)),
              ],
            ),
          ),
        ),
      );

      double sizeOf(String text, double fontSize) => tester
          .renderObject<RenderParagraph>(find.text(text))
          .textScaler
          .scale(fontSize);

      for (final system in [1.0, 1.3, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = system;
        for (final preset in AppTextSize.values) {
          await controller.setTextSize(preset);
          await tester.pump();
          for (final size in [10.0, 12.0, 14.0, 22.0, 28.0]) {
            expect(
              sizeOf(title, size),
              closeTo(size * system * preset.factor, .01),
            );
          }
          expect(sizeOf('1', 10), closeTo(10 * system * preset.factor, .01));
          expect(
            sizeOf(caption, 14),
            closeTo(14 * system * preset.factor, .01),
          );
          expect(sizeOf('Body text', 14), closeTo(14 * preset.factor, .01));
          expect(tester.takeException(), isNull);
        }
      }
      scroll.jumpTo(120);
      await tester.pump();
      expect(sizeOf(title, 22), closeTo(22 * 2.24, .01));
      expect(
        const HeaderTextScaler(_NonlinearScaler(), 1.12).scale(22),
        closeTo(22 * 1.75 * 1.12, .01),
      );
      expect(
        const HeaderTextScaler(_NonlinearScaler(), 1.12).scale(14),
        closeTo(14 * 2.24, .01),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 800);
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      expect(sizeOf('A', 14), closeTo(14 * 2.24, .01));
      await controller.setTextSize(AppTextSize.comfortable);
      await tester.pumpAndSettle();
      expect(sizeOf('A', 14), closeTo(28, .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'header uses the pane width and preserves an inherited nonlinear scaler',
    (tester) async {
      final accent = ValueNotifier(AppAccent.brand);
      addTearDown(accent.dispose);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      const title = 'Monthly Attendance Sheet';
      const headerKey = ValueKey('pane-header');
      final filter = {'status': 'Draft'}.obs;
      await tester.pumpWidget(
        ValueListenableBuilder<AppAccent>(
          valueListenable: accent,
          builder: (context, palette, _) => MaterialApp(
            theme: buildAppTheme(
              AppScheme.light,
              Brightness.light,
              accent: palette,
            ),
            darkTheme: buildAppTheme(
              AppScheme.dark,
              Brightness.dark,
              accent: palette,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const _NonlinearScaler()),
              child: child!,
            ),
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                child: AppShellScaffold(
                  body: CustomScrollView(
                    controller: controller,
                    slivers: [
                      DocTypeListHeader(
                        key: headerKey,
                        title: title,
                        activeFilters: filter,
                        onFilterTap: () {},
                        searchQuery: ''.obs,
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 1600)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      controller.jumpTo(300);
      await tester.pump();
      final heading = find.text(title);
      expect(tester.getRect(heading).right, lessThanOrEqualTo(304));
      final paragraph = tester.renderObject<RenderParagraph>(heading);
      expect(paragraph.textScaler.scale(22), 22 * 1.75);
      expect(paragraph.textScaler.scale(14), 28);
      for (final brightness in Brightness.values) {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        for (final next in AppAccent.all) {
          accent.value = next;
          await tester.pumpAndSettle();
          final badge = tester.widget<Text>(find.text('1'));
          expect(
            badge.style!.color,
            brightness == Brightness.dark ? AppScheme.dark.bg : Colors.white,
          );
          final paragraph = tester.renderObject<RenderParagraph>(heading);
          expect(paragraph.textScaler.scale(22), 22 * 1.75);
          expect(
            (paragraph.text as TextSpan).style!.color,
            AppScheme.of(brightness).text,
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
