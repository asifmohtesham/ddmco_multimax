import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/item_image.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('shows initials fallback when imageUrl is null/empty', (tester) async {
    await tester.pumpWidget(_wrap(const ItemThumbnail(
      imageUrl: null, itemCode: '2001272', itemName: 'STRAPS T/X PRINT',
    )));
    // 'STRAPS T/X PRINT' -> words [STRAPS, T, X, PRINT] -> first two initials 'ST'
    expect(find.text('ST'), findsOneWidget);
  });

  testWidgets('falls back to item code for initials when name is blank',
      (tester) async {
    await tester.pumpWidget(_wrap(const ItemThumbnail(
      imageUrl: '', itemCode: 'AB1234', itemName: '',
    )));
    // 'AB1234' has no whitespace so it is a single "word"; the verbatim
    // initials algorithm (unchanged from Stock Balance's original
    // _ItemThumb) takes the first letter of up to the first two words,
    // so a single-word source yields one letter: 'A'.
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('no zoom gesture when there is no image', (tester) async {
    await tester.pumpWidget(_wrap(const ItemThumbnail(
      imageUrl: null, itemCode: 'X', itemName: 'X',
    )));
    // With no image the thumb is not wrapped in a GestureDetector-with-onTap.
    final gestures = tester.widgetList<GestureDetector>(find.byType(GestureDetector));
    expect(gestures.where((g) => g.onTap != null), isEmpty);
  });

  testWidgets('showItemImagePreview opens a dialog with an InteractiveViewer',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_wrap(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    showItemImagePreview(ctx, 'https://example.com/x.jpg', '2001272', 'STRAPS');
    // Avoid pumpAndSettle: the placeholder is an indeterminate
    // CircularProgressIndicator that schedules frames forever in a test
    // environment where the network image never resolves, so settle()
    // would time out. The dialog chrome (InteractiveViewer + caption) is
    // static and present as soon as the dialog itself has built.
    await tester.pump();
    await tester.pump();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('2001272 · STRAPS'), findsOneWidget);
  });
}
