import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/home/home_screen.dart';
import 'package:multimax/main.dart' show buildAppTheme;

// Exercises the Dashboard-revamp presentational widgets (extracted from
// HomeScreen) across both themes on a narrow phone-width viewport, guarding the
// dense layouts against overflow and confirming each surfaces its key figures.
//
// HomeScreen itself is a GetView<HomeController> wired to ~10 global services, so
// the full screen is impractical to pump in a unit test. These widgets carry the
// new layout/hierarchy, so testing them directly covers the revamp's risk:
//   • loading state  → PulseSkeleton
//   • loaded state   → ScanHeroCard, PulseStat, AttentionRow, ResumeJobCard,
//                      BomCountCard
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Widget child,
    required Brightness brightness,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppScheme.of(brightness), brightness),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
    // Bounded pump, not pumpAndSettle: PulseSkeleton's shimmer repeats
    // forever (..repeat(reverse: true)) and would never settle. 600ms
    // covers both the skeleton's first frame and PulseStat/BomCountCard's
    // 500ms count-up animation.
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  }

  for (final brightness in Brightness.values) {
    final mode = brightness.name;

    testWidgets('loaded composition renders without overflow ($mode)',
        (tester) async {
      await pump(
        tester,
        brightness: brightness,
        child: Column(
          children: [
            ScanHeroCard(onTap: () {}),
            const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: PulseStat(
                      title: 'Work Orders',
                      icon: Icons.precision_manufacturing_outlined,
                      actual: 8,
                      target: 12,
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PulseStat(
                      title: 'Job Cards',
                      icon: Icons.assignment_ind_outlined,
                      actual: 5,
                      target: 40,
                      onTap: () {},
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ResumeJobCard(jcName: 'JC-0042', operation: 'Cutting'),
            const SizedBox(height: 9),
            AttentionRow(
              icon: Icons.precision_manufacturing_outlined,
              color: Colors.indigo,
              title: 'Work Orders in process',
              subtitle: 'Active manufacturing orders',
              count: 8,
              onTap: () {},
            ),
            const SizedBox(height: 16),
            BomCountCard(count: 123, onTap: () {}),
          ],
        ),
      );

      // Hero scan entry point.
      expect(find.text('Scan to start'), findsOneWidget);
      // Pulse stats: actual numbers + target labels.
      expect(find.text('8'), findsWidgets);
      expect(find.text('/ 12 target'), findsOneWidget);
      expect(find.text('/ 40 target'), findsOneWidget);
      // Pulse percentages (8/12 = 67%, 5/40 = 13%).
      expect(find.text('67%'), findsOneWidget);
      expect(find.text('13%'), findsOneWidget);
      // Footer shows honest distance-to-target (no due-today source).
      expect(find.text('4 to target'), findsOneWidget);
      expect(find.text('35 to target'), findsOneWidget);
      // Attention items.
      expect(find.text('RESUME JOB CARD'), findsOneWidget);
      expect(find.text('JC-0042 · Cutting'), findsOneWidget);
      expect(find.text('Work Orders in process'), findsOneWidget);
      // BOM count.
      expect(find.text('Active BOMs'), findsOneWidget);
      expect(find.text('123'), findsOneWidget);
    });

    testWidgets('loading skeleton renders without overflow ($mode)',
        (tester) async {
      await pump(
        tester,
        brightness: brightness,
        child: const PulseSkeleton(),
      );
      expect(find.byType(PulseSkeleton), findsOneWidget);
    });

    testWidgets('PulseStat with zero target shows 0% and no overflow ($mode)',
        (tester) async {
      await pump(
        tester,
        brightness: brightness,
        child: PulseStat(
          title: 'Work Orders',
          icon: Icons.precision_manufacturing_outlined,
          actual: 0,
          target: 0,
          onTap: () {},
        ),
      );
      expect(find.text('0%'), findsOneWidget);
      // actual (0) >= target (0) → target met, no negative "to target".
      expect(find.text('Target met'), findsOneWidget);
    });
  }
}
