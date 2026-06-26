import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/skeleton_box.dart';

Widget _host({required bool reduceMotion, Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: const Scaffold(
        body: Center(child: SizedBox(width: 200, child: SkeletonBox(height: 12))),
      ),
    ),
  );
}

void main() {
  testWidgets('animated: renders a gradient (no static solid fill)', (tester) async {
    await tester.pumpWidget(_host(reduceMotion: false));
    await tester.pump(const Duration(milliseconds: 100));
    final boxes = tester.widgetList<Container>(find.byType(Container));
    final hasGradient = boxes.any((c) =>
        c.decoration is BoxDecoration && (c.decoration as BoxDecoration).gradient != null);
    expect(hasGradient, isTrue);
    await tester.pump(const Duration(milliseconds: 700)); // ensure it animates without throwing
  });

  testWidgets('reduced motion: static subtle fill, no gradient', (tester) async {
    await tester.pumpWidget(_host(reduceMotion: true));
    await tester.pump();
    final container = tester.widgetList<Container>(find.byType(Container)).firstWhere(
        (c) => c.decoration is BoxDecoration &&
               (c.decoration as BoxDecoration).color == AppScheme.light.subtle);
    final deco = container.decoration as BoxDecoration;
    expect(deco.gradient, isNull);
    expect(deco.color, AppScheme.light.subtle);
  });

  testWidgets('resolves dark subtle under dark brightness (reduced motion)', (tester) async {
    await tester.pumpWidget(_host(reduceMotion: true, brightness: Brightness.dark));
    await tester.pump();
    final match = tester.widgetList<Container>(find.byType(Container)).any((c) =>
        c.decoration is BoxDecoration &&
        (c.decoration as BoxDecoration).color == AppScheme.dark.subtle);
    expect(match, isTrue);
  });
}
