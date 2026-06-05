import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/doctype_image_upload.dart';

void main() {
  Widget buildHarness({String? imageUrl}) => MaterialApp(
        home: Scaffold(
          body: DocTypeImageUpload(
            doctype: 'Item',
            docname: 'ITEM-001',
            fieldname: 'image',
            baseUrl: 'https://erp.example.com',
            imageUrl: imageUrl,
            onUploaded: () {},
          ),
        ),
      );

  group('DocTypeImageUpload', () {
    testWidgets('T-1: Edit badge visible when imageUrl is null', (tester) async {
      await tester.pumpWidget(buildHarness(imageUrl: null));
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('T-2: Edit badge visible when imageUrl is set', (tester) async {
      await tester.pumpWidget(buildHarness(imageUrl: '/files/item.jpg'));
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('T-3: tapping Edit badge opens source picker sheet with both sources', (tester) async {
      await tester.pumpWidget(buildHarness(imageUrl: null));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Choose from Gallery'), findsOneWidget);
    });

    testWidgets('T-4: Remove Image row absent from sheet when imageUrl is null', (tester) async {
      await tester.pumpWidget(buildHarness(imageUrl: null));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Image'), findsNothing);
    });

    testWidgets('T-5: Remove Image row present in sheet when imageUrl is set', (tester) async {
      await tester.pumpWidget(buildHarness(imageUrl: '/files/item.jpg'));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Image'), findsOneWidget);
    });
  });
}
