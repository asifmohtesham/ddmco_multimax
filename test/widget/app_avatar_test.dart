import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/app_avatar.dart';

Widget _host(Widget child, {Brightness b = Brightness.light}) =>
    MaterialApp(theme: ThemeData(brightness: b), home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('shows initials in primary over a primary-tinted bg', (tester) async {
    await tester.pumpWidget(_host(const AppAvatar(initials: 'AM')));
    expect(find.text('AM'), findsOneWidget);
    final txt = tester.widget<Text>(find.text('AM'));
    expect(txt.style?.color, AppScheme.light.primary);
    final box = tester.widget<Container>(
      find.ancestor(of: find.text('AM'), matching: find.byType(Container)).first);
    final deco = box.decoration as BoxDecoration;
    expect(deco.color,
        Color.alphaBlend(AppScheme.light.primary.withValues(alpha: 0.16), AppScheme.light.fg));
    expect(deco.shape, BoxShape.circle);
  });

  testWidgets('square uses rounded rect not circle', (tester) async {
    await tester.pumpWidget(_host(const AppAvatar(initials: 'X', square: true)));
    final box = tester.widget<Container>(
      find.ancestor(of: find.text('X'), matching: find.byType(Container)).first);
    final deco = box.decoration as BoxDecoration;
    expect(deco.shape, BoxShape.rectangle);
    expect(deco.borderRadius, BorderRadius.circular(AppRadius.md));
  });

  testWidgets('AvatarGroup renders all children', (tester) async {
    await tester.pumpWidget(_host(const AvatarGroup(children: [
      AppAvatar(initials: 'A'), AppAvatar(initials: 'B'), AppAvatar(initials: 'C'),
    ])));
    expect(find.byType(AppAvatar), findsNWidgets(3));
  });
}
