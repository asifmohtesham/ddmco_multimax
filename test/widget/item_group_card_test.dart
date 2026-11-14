import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/shared/pos_upload/item_group_card.dart';

/// Pumps an [ItemGroupCard] inside a minimal MaterialApp scaffold so the
/// chip Wrap is laid out and queryable.
Future<void> _pumpCard(
  WidgetTester tester, {
  double totalQty = 360,
  double scannedQty = 0,
  double? posUploadQty,
  String totalQtyLabel = 'Required',
  String scannedQtyLabel = 'Scanned',
  String posUploadQtyLabel = 'POS Upload Qty',
  String unit = 'pcs',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ItemGroupCard(
            isExpanded: false,
            serialNo: 4,
            itemName: 'BELTS CASUAL 40MM',
            rate: 0.0,
            totalQty: totalQty,
            scannedQty: scannedQty,
            posUploadQty: posUploadQty,
            posUploadQtyLabel: posUploadQtyLabel,
            totalQtyLabel: totalQtyLabel,
            scannedQtyLabel: scannedQtyLabel,
            unit: unit,
            onToggle: () {},
            children: const [],
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ItemGroupCard POS Upload Qty chip', () {
    testWidgets('renders the POS Upload Qty chip with value when provided',
        (tester) async {
      await _pumpCard(tester, posUploadQty: 480);

      expect(find.text('POS Upload Qty'), findsOneWidget);
      expect(find.text('480 pcs'), findsOneWidget);
    });

    testWidgets('hides the POS Upload Qty chip when null', (tester) async {
      await _pumpCard(tester, posUploadQty: null);

      expect(find.text('POS Upload Qty'), findsNothing);
    });

    testWidgets('shows the three abbreviated funnel chips with caller labels',
        (tester) async {
      await _pumpCard(
        tester,
        posUploadQty: 480,
        totalQty: 360,
        scannedQty: 12,
        posUploadQtyLabel: 'POS Qty',
        totalQtyLabel: 'DN Qty',
        scannedQtyLabel: 'PS Qty',
      );

      expect(find.text('POS Qty'), findsOneWidget);
      expect(find.text('DN Qty'), findsOneWidget);
      expect(find.text('PS Qty'), findsOneWidget);
    });

    testWidgets('uses the document unit on qty chips', (tester) async {
      await _pumpCard(
        tester,
        posUploadQty: 480,
        totalQty: 360,
        scannedQty: 0,
        unit: 'Nos',
      );

      expect(find.text('480 Nos'), findsOneWidget);
      expect(find.text('360 Nos'), findsOneWidget);
      expect(find.text('0 Nos'), findsOneWidget);
    });
  });
}
