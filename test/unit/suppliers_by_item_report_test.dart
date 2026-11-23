import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';

void main() {
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
        'sources': 'Purchase Receipt',
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
    expect(supplier.sources, 'Purchase Receipt');
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
    final item = template.children.single;
    expect(item.row.itemCode, 'ITEM:BLUE');
    expect(item.row.treeLabel, 'ITEM:BLUE');
    expect(item.row.itemName, isNull);
    expect(item.row.supplierCount, isNull);
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
  });
}
