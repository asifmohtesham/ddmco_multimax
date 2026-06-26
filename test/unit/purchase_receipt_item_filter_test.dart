import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_item_filter.dart';

PurchaseReceiptItem _item({
  required double qty,
  double? purchaseOrderQty,
  double? poQty,
  String? purchaseOrderItem,
  String name = 'row',
}) =>
    PurchaseReceiptItem(
      name: name,
      owner: 'a',
      creation: 'c',
      itemCode: 'ITEM',
      qty: qty,
      warehouse: 'W',
      purchaseOrderQty: purchaseOrderQty,
      poQty: poQty,
      purchaseOrderItem: purchaseOrderItem,
    );

void main() {
  group('resolvedTargetQty', () {
    test('purchase_order_qty wins when present and > 0', () {
      expect(_item(qty: 1, purchaseOrderQty: 10, poQty: 7).resolvedTargetQty,
          10);
    });

    test('falls back to po_qty for locally-added rows', () {
      expect(_item(qty: 1, poQty: 7).resolvedTargetQty, 7);
    });

    test('null when both are absent or non-positive', () {
      expect(_item(qty: 1).resolvedTargetQty, isNull);
      expect(_item(qty: 1, purchaseOrderQty: 0, poQty: 0).resolvedTargetQty,
          isNull);
    });
  });

  group('isFullyReceived', () {
    test('true when accepted qty meets the target', () {
      expect(_item(qty: 10, purchaseOrderQty: 10).isFullyReceived, isTrue);
    });

    test('true when over-received', () {
      expect(_item(qty: 12, purchaseOrderQty: 10).isFullyReceived, isTrue);
    });

    test('false when partially received', () {
      expect(_item(qty: 4, purchaseOrderQty: 10).isFullyReceived, isFalse);
    });

    test('rows with no PO target are never fully received', () {
      expect(_item(qty: 99).isFullyReceived, isFalse);
    });
  });

  group('isPoLinkBroken', () {
    test('true when a PO reference no longer resolves a target', () {
      // Has purchase_order_item but the qty could not be hydrated → orphaned.
      expect(_item(qty: 5, purchaseOrderItem: 'dead-row').isPoLinkBroken,
          isTrue);
    });

    test('false when the reference still resolves a target', () {
      expect(
          _item(qty: 5, purchaseOrderItem: 'live-row', purchaseOrderQty: 10)
              .isPoLinkBroken,
          isFalse);
    });

    test('false when the row carries no PO reference at all', () {
      expect(_item(qty: 5).isPoLinkBroken, isFalse);
    });
  });

  group('filterReceiptItems', () {
    final full = _item(qty: 10, purchaseOrderQty: 10, name: 'full');
    final partial = _item(qty: 3, purchaseOrderQty: 10, name: 'partial');
    final noTarget = _item(qty: 5, name: 'noTarget');
    final orphan =
        _item(qty: 5, purchaseOrderItem: 'dead-row', name: 'orphan');
    final items = [full, partial, noTarget, orphan];

    test('all returns every row (as a copy)', () {
      final result = filterReceiptItems(items, ReceiptItemFilter.all);
      expect(result, hasLength(4));
      expect(identical(result, items), isFalse);
    });

    test('completed returns only fully-received rows', () {
      final result = filterReceiptItems(items, ReceiptItemFilter.completed);
      expect(result.map((i) => i.name), ['full']);
    });

    test('pending excludes orphaned rows (the regression fix)', () {
      final result = filterReceiptItems(items, ReceiptItemFilter.pending);
      expect(result.map((i) => i.name), ['partial', 'noTarget']);
      expect(result.map((i) => i.name), isNot(contains('orphan')));
    });

    test('linkBroken returns only orphaned rows', () {
      final result = filterReceiptItems(items, ReceiptItemFilter.linkBroken);
      expect(result.map((i) => i.name), ['orphan']);
    });

    test('order is preserved', () {
      final ordered = [partial, full, noTarget];
      final result = filterReceiptItems(ordered, ReceiptItemFilter.pending);
      expect(result.map((i) => i.name), ['partial', 'noTarget']);
    });
  });

  group('countReceiptItems', () {
    final items = [
      _item(qty: 10, purchaseOrderQty: 10),
      _item(qty: 3, purchaseOrderQty: 10),
      _item(qty: 5),
      _item(qty: 5, purchaseOrderItem: 'dead-row'),
    ];

    test('counts per filter', () {
      expect(countReceiptItems(items, ReceiptItemFilter.all), 4);
      expect(countReceiptItems(items, ReceiptItemFilter.completed), 1);
      expect(countReceiptItems(items, ReceiptItemFilter.pending), 2);
      expect(countReceiptItems(items, ReceiptItemFilter.linkBroken), 1);
    });
  });

  test('filter labels', () {
    expect(ReceiptItemFilter.all.label, 'All');
    expect(ReceiptItemFilter.pending.label, 'Pending');
    expect(ReceiptItemFilter.completed.label, 'Completed');
    expect(ReceiptItemFilter.linkBroken.label, 'Link broken');
  });
}
