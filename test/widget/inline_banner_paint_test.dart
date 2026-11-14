import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/inline_banner.dart';

/// Regression guard for the zero-height banner.
///
/// `InlineBanner` mounted a message that was present in the widget tree but
/// laid out at height 0, so nothing ever reached the user. Every assertion
/// here measures the RENDER tree — a `find.text` / `findsWidgets` assertion
/// passes happily against a collapsed banner (and also matches the GetX
/// snackbar), which is exactly how this went unnoticed.
void main() {
  const kMessage = 'Save failed — check the warehouse';

  // A Column gives its non-flex children unbounded height, so the banner
  // sizes to its own content. That mirrors the real call sites, where the
  // banner sits above the form body.
  Widget host(Widget banner) => MaterialApp(
        home: Scaffold(
          body: Column(children: [banner, const Expanded(child: SizedBox())]),
        ),
      );

  double bannerHeight(WidgetTester tester) =>
      tester.getSize(find.byType(InlineBanner)).height;

  testWidgets('paints at a non-zero height when mounted already visible',
      (tester) async {
    await tester.pumpWidget(host(const InlineBanner(
      visible: true,
      message: kMessage,
      type: BannerType.error,
    )));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(InlineBanner),
        matching: find.text(kMessage),
      ),
      findsOneWidget,
    );
    expect(bannerHeight(tester), greaterThan(0));
  });

  testWidgets('paints at a non-zero height when visible flips false -> true',
      (tester) async {
    final visible = ValueNotifier<bool>(false);
    addTearDown(visible.dispose);

    await tester.pumpWidget(host(ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (_, v, __) => InlineBanner(
        visible: v,
        message: kMessage,
        type: BannerType.error,
      ),
    )));
    await tester.pumpAndSettle();
    expect(bannerHeight(tester), 0, reason: 'hidden banner must not take space');

    visible.value = true;
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(InlineBanner),
        matching: find.text(kMessage),
      ),
      findsOneWidget,
    );
    expect(bannerHeight(tester), greaterThan(0));
  });

  testWidgets('collapses back to zero height when visible flips true -> false',
      (tester) async {
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);

    await tester.pumpWidget(host(ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (_, v, __) => InlineBanner(
        visible: v,
        message: kMessage,
        type: BannerType.error,
      ),
    )));
    await tester.pumpAndSettle();
    expect(bannerHeight(tester), greaterThan(0));

    visible.value = false;
    await tester.pumpAndSettle();
    expect(bannerHeight(tester), 0);
  });

  testWidgets('stays painted while the message is swapped in place',
      (tester) async {
    final message = ValueNotifier<String>(kMessage);
    addTearDown(message.dispose);

    await tester.pumpWidget(host(ValueListenableBuilder<String>(
      valueListenable: message,
      builder: (_, m, __) => InlineBanner(
        visible: true,
        message: m,
        type: BannerType.error,
      ),
    )));
    await tester.pumpAndSettle();
    final first = bannerHeight(tester);
    expect(first, greaterThan(0));

    message.value = 'Saved';
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(InlineBanner),
        matching: find.text('Saved'),
      ),
      findsOneWidget,
    );
    expect(bannerHeight(tester), greaterThan(0));
  });
}
