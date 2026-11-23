import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';

void main() {
  test(
    'serializes drafts as a check value and keeps link filters separate',
    () {
      const defaults = SuppliersByItemFilters();
      expect(defaults.includeDrafts, isTrue);
      expect(defaults.linkFilters, isEmpty);
      expect(defaults.toJson(), {'include_drafts': 1});

      const filters = SuppliersByItemFilters(
        items: [' ITEM-1 ', 'ITEM-1', '', 'ITEM-2'],
        variantOf: [' SHIRT '],
        suppliers: ['  '],
        warehouses: ['WAREHOUSE-1'],
        includeDrafts: false,
      );
      expect(filters.linkFilters, {
        'items': ['ITEM-1', 'ITEM-2'],
        'variant_of': ['SHIRT'],
        'warehouses': ['WAREHOUSE-1'],
      });
      expect(filters.toJson(), {...filters.linkFilters, 'include_drafts': 0});
    },
  );

  test('keeps supplierless variants and skips Desk placeholder rows', () {
    final tree = SuppliersByItemNode.parseRows([
      {
        'node_id': 'template:ACP-25',
        'indent': 0,
        'template': 'ACP-25',
        'tree_label': 'ACP-25',
        'supplier_count': 1,
      },
      {
        'node_id': 'item:2002492',
        'parent_id': 'template:ACP-25',
        'indent': 1,
        'item_code': '2002492',
        'tree_label': '2002492',
        'supplier_count': 0,
        'total_qty_received': 0,
        'stock_uom': 'Nos',
      },
      {
        'node_id': 'none:7:2002492',
        'parent_id': 'item:2002492',
        'row_type': 'placeholder',
        'indent': 2,
        'tree_label': 'No supplier recorded',
        'item_code': '2002492',
        'is_placeholder': 1,
      },
      {
        'node_id': 'item:2002506',
        'parent_id': 'template:ACP-25',
        'indent': 1,
        'item_code': '2002506',
        'tree_label': '2002506',
        'supplier_count': 1,
      },
      {
        'node_id': 'supplier:7:2002506:KANG KAI',
        'parent_id': 'item:2002506',
        'row_type': 'supplier',
        'indent': 2,
        'tree_label': 'KANG KAI',
        'item_code': '2002506',
        'supplier': 'KANG KAI',
        'is_placeholder': 0,
        'total_qty_received': 0,
        'last_rate': 14,
        'currency': 'AED',
        'rate_source': 'Purchase Order',
        'rate_date': '2026-11-05',
        'rate_document': 'PUR-ORD-2026-00001',
      },
    ]);

    final template = tree.single;
    expect(template.row.template, 'ACP-25');
    expect(template.hasSuppliers, isTrue);
    expect(template.row.supplierCount, 1);
    final [withoutSupplier, withSupplier] = template.children;
    expect(withoutSupplier.row.itemCode, '2002492');
    expect(withoutSupplier.row.supplierCount, 0);
    expect(withoutSupplier.hasSuppliers, isFalse);
    expect(withoutSupplier.children, isEmpty);
    expect(withSupplier.row.itemCode, '2002506');
    expect(withSupplier.hasSuppliers, isTrue);
    final supplier = withSupplier.children.single.row;
    expect(supplier.supplier, 'KANG KAI');
    expect(supplier.totalQtyReceived, 0);
    expect(supplier.lastRate, 14);
    expect(supplier.currency, 'AED');
    expect(supplier.rateSource, 'Purchase Order');
    expect(supplier.rateDate, '2026-11-05');
    expect(supplier.rateDocument, 'PUR-ORD-2026-00001');
  });

  test('builds template and standalone item branches in server order', () {
    final tree = SuppliersByItemNode.parseRows([
      {
        'node_id': 'template:SHIRT',
        'parent_id': null,
        'indent': 0,
        'template': 'SHIRT',
        'tree_label': 'SHIRT',
        'item_name': 'Shirt',
        'total_qty_received': '26.5',
        'supplier_count': 1,
      },
      {
        'node_id': 'item:SHIRT-BLUE',
        'parent_id': 'template:SHIRT',
        'indent': 1,
        'item_code': 'SHIRT-BLUE',
        'item_name': 'Blue shirt',
        'total_qty_received': 26.5,
        'supplier_count': '1',
      },
      {
        'node_id': 'supplier:SHIRT-BLUE:SUP-1',
        'parent_id': 'item:SHIRT-BLUE',
        'indent': 2,
        'item_code': 'SHIRT-BLUE',
        'supplier': 'SUP-1',
        'supplier_name': 'Tailor One',
        'supplier_part_number': '1234-B',
        'sources': 'Purchase Receipt, Batch',
        'last_purchase_date': '2026-11-07',
        'last_purchase_receipt': 'PR-0001',
        'last_rate': '0',
        'rate_source': 'Purchase Receipt',
        'rate_date': '2026-11-07',
        'rate_document': 'PR-0001',
        'currency': 'AED',
        'rate_uom': 'Box',
        'total_qty_received': 26.5,
        'stock_uom': 'Nos',
        'last_po_date': '2026-11-05',
      },
      {'node_id': 'item:GLOVES', 'indent': 0},
      {
        'node_id': 'supplier:GLOVES:SUP-2',
        'parent_id': 'item:GLOVES',
        'indent': 1,
      },
    ]);

    expect(tree.map((node) => node.row.nodeId), [
      'template:SHIRT',
      'item:GLOVES',
    ]);
    final template = tree.first.row;
    expect(template.kind, SuppliersByItemRowKind.template);
    expect(template.template, 'SHIRT');
    expect(template.treeLabel, 'SHIRT');
    expect(template.itemName, 'Shirt');
    expect(template.totalQtyReceived, 26.5);
    expect(template.supplierCount, 1);

    final variant = tree.first.children.single;
    expect(variant.row.itemCode, 'SHIRT-BLUE');
    expect(variant.row.template, 'SHIRT');
    expect(variant.row.supplierCount, 1);
    final supplier = variant.children.single.row;
    expect(supplier.kind, SuppliersByItemRowKind.supplier);
    expect(supplier.indent, 2);
    expect(supplier.parentId, 'item:SHIRT-BLUE');
    expect(supplier.itemCode, 'SHIRT-BLUE');
    expect(supplier.supplier, 'SUP-1');
    expect(supplier.supplierName, 'Tailor One');
    expect(supplier.supplierPartNumber, '1234-B');
    expect(supplier.sources, 'Purchase Receipt, Batch');
    expect(supplier.lastPurchaseDate, '2026-11-07');
    expect(supplier.lastPurchaseReceipt, 'PR-0001');
    expect(supplier.lastRate, 0);
    expect(supplier.rateSource, 'Purchase Receipt');
    expect(supplier.rateDate, '2026-11-07');
    expect(supplier.rateDocument, 'PR-0001');
    expect(supplier.currency, 'AED');
    expect(supplier.rateUom, 'Box');
    expect(supplier.totalQtyReceived, 26.5);
    expect(supplier.stockUom, 'Nos');
    expect(supplier.lastPoDate, '2026-11-05');
    expect(tree.last.children.single.row.indent, 1);
  });

  test('falls back to node IDs and preserves null and absent columns', () {
    final tree = SuppliersByItemNode.parseRows([
      {
        'node_id': 'supplier:ITEM:BLUE:SUP-1',
        'parent_id': 'item:ITEM:BLUE',
        'indent': 2,
        'supplier': null,
        'item_code': null,
        'supplier_part_number': null,
        'last_purchase_date': null,
        'last_rate': null,
        'total_qty_received': null,
        'stock_uom': null,
        'last_po_date': null,
      },
      {
        'node_id': 'supplier:ITEM:BLUE:EMPTY',
        'parent_id': 'item:ITEM:BLUE',
        'is_placeholder': '1',
      },
      {'node_id': 'template:LEGACY', 'template': null, 'indent': 0},
      {
        'node_id': 'item:ITEM:BLUE',
        'parent_id': 'template:LEGACY',
        'item_name': null,
        'supplier_count': null,
        'indent': 1,
      },
      null,
      {'tree_label': 'Total'},
      ['Total', null],
    ]);

    final template = tree.single;
    expect(template.row.template, 'LEGACY');
    expect(template.row.treeLabel, 'LEGACY');
    expect(template.row.balanceQty, isNull);
    expect(template.row.matchedSupplier, isFalse);
    final item = template.children.single;
    expect(item.row.itemCode, 'ITEM:BLUE');
    expect(item.row.treeLabel, 'ITEM:BLUE');
    expect(item.row.itemName, isNull);
    expect(item.row.supplierCount, isNull);
    expect(item.row.balanceQty, isNull);
    expect(item.row.matchedSupplier, isFalse);
    final supplier = item.children.single.row;
    expect(supplier.itemCode, 'ITEM:BLUE');
    expect(supplier.supplier, 'SUP-1');
    expect(supplier.treeLabel, 'SUP-1');
    expect(supplier.supplierName, isNull);
    expect(supplier.supplierPartNumber, isNull);
    expect(supplier.lastPurchaseDate, isNull);
    expect(supplier.lastRate, isNull);
    expect(supplier.rateSource, isNull);
    expect(supplier.rateDate, isNull);
    expect(supplier.rateDocument, isNull);
    expect(supplier.currency, isNull);
    expect(supplier.rateUom, isNull);
    expect(supplier.totalQtyReceived, isNull);
    expect(supplier.stockUom, isNull);
    expect(supplier.lastPoDate, isNull);
    expect(supplier.balanceQty, isNull);
    expect(supplier.matchedSupplier, isFalse);
  });

  test('reads balances and supplier matches on their respective rows', () {
    final tree = SuppliersByItemNode.parseRows([
      {
        'node_id': 'template:SHIRT',
        'balance_qty': '12.5',
        'stock_uom': 'Nos',
        'matched_supplier': 1,
      },
      {
        'node_id': 'item:SHIRT-BLUE',
        'parent_id': 'template:SHIRT',
        'balance_qty': 12.5,
        'stock_uom': 'Nos',
        'matched_supplier': 1,
      },
      {
        'node_id': 'supplier:SHIRT-BLUE:SUP-1',
        'parent_id': 'item:SHIRT-BLUE',
        'balance_qty': 50,
        'matched_supplier': '1',
      },
      {
        'node_id': 'supplier:SHIRT-BLUE:SUP-2',
        'parent_id': 'item:SHIRT-BLUE',
        'matched_supplier': 0,
      },
      {
        'node_id': 'supplier:SHIRT-BLUE:SUP-3',
        'parent_id': 'item:SHIRT-BLUE',
        'matched_supplier': true,
      },
      {
        'node_id': 'supplier:SHIRT-BLUE:PLACEHOLDER',
        'parent_id': 'item:SHIRT-BLUE',
        'is_placeholder': true,
        'matched_supplier': 1,
      },
    ]);

    final template = tree.single;
    expect(template.row.balanceQty, 12.5);
    expect(template.row.matchedSupplier, isFalse);
    final variant = template.children.single;
    expect(variant.row.balanceQty, 12.5);
    expect(variant.row.matchedSupplier, isFalse);
    expect(variant.children.map((node) => node.row.supplier), [
      'SUP-1',
      'SUP-2',
      'SUP-3',
    ]);
    expect(variant.children.map((node) => node.row.matchedSupplier), [
      true,
      false,
      true,
    ]);
    expect(
      variant.children.map((node) => node.row.balanceQty),
      everyElement(isNull),
    );
  });

  test('parses the v6 supplier, item and template fields', () {
    final template = SuppliersByItemNode.parseRows([
      {
        'node_id': 'template:SHIRT',
        'projected_qty': '3.25',
        'reorder_level': 5,
        'reorder_qty': 10,
      },
      {
        'node_id': 'item:SHIRT-BLUE',
        'parent_id': 'template:SHIRT',
        'projected_qty': 3.25,
        'reorder_level': '5',
        'reorder_qty': '10',
        'open_order_qty': '12.5',
        'draft_order_qty': 6,
      },
      {
        'node_id': 'supplier:SHIRT-BLUE:SUP-1',
        'parent_id': 'item:SHIRT-BLUE',
        'supplier_status': ' On Hold (All) until 2026-12-01 ',
        'open_order_qty': 12.5,
        'draft_order_qty': '6',
        'lead_time_days': '10.4',
        'lead_time_receipts': '5',
        'po_count': 2,
        'receipt_count': '3',
        'sources':
            'Purchase Order (Draft), Batch (draft PO), '
            'Batch (cancelled PO), Batch (no PO)',
      },
    ]).single;

    final variant = template.children.single;
    for (final row in [template.row, variant.row]) {
      expect(row.projectedQty, 3.25);
      expect(row.reorderLevel, 5);
      expect(row.reorderQty, 10);
    }
    expect(variant.row.openOrderQty, 12.5);
    expect(variant.row.draftOrderQty, 6);

    final supplier = variant.children.single.row;
    expect(supplier.supplierStatus, 'On Hold (All) until 2026-12-01');
    expect(supplier.openOrderQty, 12.5);
    expect(supplier.draftOrderQty, 6);
    expect(supplier.leadTimeDays, 10.4);
    expect(supplier.leadTimeReceipts, 5);
    expect(supplier.poCount, 2);
    expect(supplier.receiptCount, 3);
    expect(
      supplier.sources,
      'Purchase Order (Draft), Batch (draft PO), '
      'Batch (cancelled PO), Batch (no PO)',
    );
  });

  test('preserves null and missing v6 fields on older report rows', () {
    const missing = <String, Object?>{};
    const blank = {
      'supplier_status': null,
      'open_order_qty': null,
      'draft_order_qty': null,
      'lead_time_days': null,
      'lead_time_receipts': null,
      'po_count': null,
      'receipt_count': null,
      'projected_qty': null,
      'reorder_level': null,
      'reorder_qty': null,
    };
    for (final fields in [missing, blank]) {
      final template = SuppliersByItemNode.parseRows([
        {'node_id': 'template:SHIRT', ...fields},
        {'node_id': 'item:BLUE', 'parent_id': 'template:SHIRT', ...fields},
        {'node_id': 'supplier:BLUE:SUP-1', 'parent_id': 'item:BLUE', ...fields},
      ]).single;
      final item = template.children.single;
      final supplier = item.children.single.row;

      for (final row in [template.row, item.row, supplier]) {
        expect(row.projectedQty, isNull);
        expect(row.reorderLevel, isNull);
        expect(row.reorderQty, isNull);
        expect(row.openOrderQty, isNull);
        expect(row.draftOrderQty, isNull);
      }
      expect(supplier.supplierStatus, isNull);
      expect(supplier.leadTimeDays, isNull);
      expect(supplier.leadTimeReceipts, isNull);
      expect(supplier.poCount, isNull);
      expect(supplier.receiptCount, isNull);
    }
  });

  test('flags only a known projection below a positive reorder level', () {
    final tree = SuppliersByItemNode.parseRows([
      {'node_id': 'template:LOW', 'projected_qty': -2, 'reorder_level': 1},
      {'node_id': 'item:LOW', 'projected_qty': 0, 'reorder_level': 1},
      {'node_id': 'item:EQUAL', 'projected_qty': 5, 'reorder_level': 5},
      {'node_id': 'item:ABOVE', 'projected_qty': 6, 'reorder_level': 5},
      {'node_id': 'item:ZERO-LEVEL', 'projected_qty': -2, 'reorder_level': 0},
      {
        'node_id': 'item:NEGATIVE-LEVEL',
        'projected_qty': -2,
        'reorder_level': -1,
      },
      {'node_id': 'item:NO-LEVEL', 'projected_qty': -2},
      {'node_id': 'item:NO-PROJECTION', 'reorder_level': 5},
      {
        'node_id': 'supplier:LOW:SUP-1',
        'parent_id': 'item:LOW',
        'projected_qty': 0,
        'reorder_level': 1,
      },
    ]);
    expect(
      tree
          .where((node) => node.row.isBelowReorderLevel)
          .map((node) => node.row.nodeId),
      ['template:LOW', 'item:LOW'],
    );
    expect(tree[1].children.single.row.isBelowReorderLevel, isFalse);
  });

  test('sums item quantities once per stock UOM', () {
    final tree = SuppliersByItemNode.parseRows([
      {
        'node_id': 'template:SHIRT',
        'balance_qty': 12.5,
        'projected_qty': 18,
        'open_order_qty': 2,
        'stock_uom': 'Nos',
      },
      {
        'node_id': 'item:SHIRT-BLUE',
        'parent_id': 'template:SHIRT',
        'balance_qty': 12.5,
        'projected_qty': 18,
        'open_order_qty': 2,
        'stock_uom': 'Nos',
      },
      {
        'node_id': 'supplier:SHIRT-BLUE:SUP-1',
        'parent_id': 'item:SHIRT-BLUE',
        'balance_qty': 10,
        'projected_qty': 18,
        'open_order_qty': 2,
        'stock_uom': 'Nos',
      },
      {'node_id': 'template:MIXED', 'balance_qty': null},
      {
        'node_id': 'item:MIXED-PIECES',
        'parent_id': 'template:MIXED',
        'balance_qty': -2,
        'projected_qty': -1,
        'stock_uom': 'Nos',
      },
      {
        'node_id': 'item:MIXED-BOX',
        'parent_id': 'template:MIXED',
        'balance_qty': '4',
        'open_order_qty': 0,
        'stock_uom': 'Box',
      },
      {
        'node_id': 'item:GLOVES',
        'balance_qty': '3',
        'projected_qty': 4,
        'open_order_qty': '3',
        'stock_uom': 'Nos',
      },
      {'node_id': 'item:FABRIC', 'balance_qty': 0, 'stock_uom': 'Meter'},
      {'node_id': 'item:LEGACY', 'stock_uom': 'Set'},
      {
        'node_id': 'item:INVALID',
        'balance_qty': 'NaN',
        'projected_qty': 'Infinity',
        'open_order_qty': 'invalid',
        'stock_uom': 'Pair',
      },
      {
        'node_id': 'item:NO-UOM',
        'balance_qty': 100,
        'projected_qty': 100,
        'open_order_qty': 100,
        'stock_uom': '',
      },
      {'node_id': 'item:LEATHER', 'projected_qty': -4, 'stock_uom': 'Kg'},
    ]);

    expect(tree[1].row.balanceQty, isNull);
    expect(tree[3].row.balanceQty, 0);
    expect(tree[5].row.balanceQty, isNull);
    final totals = SuppliersByItemNode.quantityTotalsByUom(tree);
    expect(totals.keys, ['Nos', 'Box', 'Meter', 'Kg']);
    expect(totals['Nos']!.balanceQty, 13.5);
    expect(totals['Nos']!.projectedQty, 21);
    expect(totals['Nos']!.openOrderQty, 5);
    expect(totals['Box']!.balanceQty, 4);
    expect(totals['Box']!.projectedQty, isNull);
    expect(totals['Box']!.openOrderQty, 0);
    expect(totals['Meter']!.balanceQty, 0);
    expect(totals['Meter']!.projectedQty, isNull);
    expect(totals['Kg']!.balanceQty, isNull);
    expect(totals['Kg']!.projectedQty, -4);
    expect(totals['Kg']!.openOrderQty, isNull);
  });
}
