import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';

void main() {
  test('serializes check values and keeps link filters separate', () {
    const defaults = SuppliersByItemFilters();
    expect(defaults.includeDrafts, isTrue);
    expect(defaults.expandBom, isFalse);
    expect(defaults.linkFilters, isEmpty);
    expect(defaults.toJson(), {'include_drafts': 1, 'expand_bom': 0});

    const filters = SuppliersByItemFilters(
      items: [' ITEM-1 ', 'ITEM-1', '', 'ITEM-2'],
      variantOf: [' SHIRT '],
      suppliers: ['  '],
      warehouses: ['WAREHOUSE-1'],
      includeDrafts: false,
      expandBom: true,
    );
    expect(filters.linkFilters, {
      'items': ['ITEM-1', 'ITEM-2'],
      'variant_of': ['SHIRT'],
      'warehouses': ['WAREHOUSE-1'],
    });
    expect(filters.toJson(), {
      ...filters.linkFilters,
      'include_drafts': 0,
      'expand_bom': 1,
    });
  });

  test('prefilters a scanned variant by its template', () {
    final filters = SuppliersByItemFilters.forScannedItem(
      itemCode: 'SHIRT-BLUE',
      variantOf: ' SHIRT ',
    );

    expect(filters.linkFilters, {
      'variant_of': ['SHIRT'],
    });
  });

  test('prefilters a scanned item without a template by its own code', () {
    for (final variantOf in [null, '', ' ']) {
      final filters = SuppliersByItemFilters.forScannedItem(
        itemCode: 'BLUE',
        variantOf: variantOf,
      );

      expect(filters.linkFilters, {
        'items': ['BLUE'],
      });
    }
  });

  test(
    'keeps supplierless variants and typed placeholders without counting them',
    () {
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
      final placeholder = withoutSupplier.children.single.row;
      expect(placeholder.kind, SuppliersByItemRowKind.placeholder);
      expect(placeholder.treeLabel, 'No supplier recorded');
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
    },
  );

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

  test('parses the production v7 BOM trees for 3000338 and 3000339', () {
    final rows = <Map<String, Object?>>[];
    void add(
      String type,
      String id,
      String? parent,
      int indent,
      Map<String, Object?> fields,
    ) {
      rows.add({
        'row_type': type,
        'node_id': id,
        'parent_id': parent,
        'indent': indent,
        'is_component': switch (type) {
          'bom' || 'component' => 1,
          _ => parent?.startsWith('component:') == true ? 1 : 0,
        },
        ...fields,
      });
    }

    String path(String type, String parent, String key) =>
        '$type:${parent.length}:$parent|$key';

    String bom(
      String parent,
      String item,
      int count,
      int indent, {
      bool draft = false,
      required int suppliers,
    }) {
      final code = 'BOM-$item-001';
      final id = path('bom', parent, code);
      add('bom', id, parent, indent, {
        'bom_no': code,
        'bom_is_default': 1,
        'bom_status': draft ? 'Draft' : 'Submitted',
        'component_count': count,
        'component_supplier_count': suppliers,
        'tree_label': draft
            ? '$code · $count components · draft'
            : '$code · default · $count components',
      });
      return id;
    }

    String component(
      String parent,
      String bomItem,
      String item,
      int index,
      int indent,
      num quantity, {
      String? supplier,
      bool matched = false,
    }) {
      final id = path(
        'component',
        parent,
        '$index|${item.length}:$item|line-$index',
      );
      add('component', id, parent, indent, {
        'item_code': item,
        'item_name': 'Component $item',
        'bom_no': 'BOM-$bomItem-001',
        'bom_qty_per_unit': quantity,
        'stock_uom': 'Nos',
        'include_in_manufacturing': supplier == 'JOAP' ? 0 : 1,
        'used_in_bom_count': 2,
        'balance_qty': 50,
        'projected_qty': '60.5',
        'last_purchase_date': supplier == null ? null : '2026-11-01',
        'supplier_count': supplier == null ? 0 : 1,
      });
      if (supplier == null) {
        add('placeholder', 'none:$id', id, indent + 1, {
          'item_code': item,
          'is_placeholder': 1,
        });
      } else {
        add('supplier', path('supplier', id, supplier), id, indent + 1, {
          'item_code': item,
          'supplier': supplier,
          'matched_supplier': matched ? 1 : 0,
        });
      }
      return id;
    }

    // Production topology and quantities with representative stock values.
    const template = 'template:GQP-BELTS';
    add('item', 'item:3000338', null, 0, {
      'item_code': '3000338',
      'stock_uom': 'Nos',
      'balance_qty': 4,
      'projected_qty': 5,
      'supplier_count': 0,
    });
    add('placeholder', 'none:7:3000338', 'item:3000338', 1, {
      'item_code': '3000338',
      'is_placeholder': 1,
    });
    final bom338 = bom('item:3000338', '3000338', 4, 1, suppliers: 3);
    component(bom338, '3000338', '3000329', 1, 2, 12);
    final assembly = component(bom338, '3000338', '3000281', 2, 2, 12);
    final draft281 = bom(assembly, '3000281', 2, 3, draft: true, suppliers: 2);
    component(draft281, '3000281', '1004879', 1, 4, 1, supplier: 'EDGE');
    component(draft281, '3000281', '1004722', 2, 4, 1, supplier: 'BOVIS');
    component(bom338, '3000338', '1004774', 3, 2, 12, supplier: 'KOL-FACTORY');
    component(bom338, '3000338', '1003590', 4, 2, 12);

    add('template', template, null, 0, {'template': 'GQP-BELTS'});
    add('item', 'item:3000339', template, 1, {
      'item_code': '3000339',
      'stock_uom': 'Nos',
      'balance_qty': 6,
      'projected_qty': 7,
      'open_order_qty': 2,
      'supplier_count': 0,
    });
    add('placeholder', 'none:7:3000339', 'item:3000339', 2, {
      'item_code': '3000339',
      'is_placeholder': 1,
    });
    final bom339 = bom('item:3000339', '3000339', 2, 2, suppliers: 2);
    component(
      bom339,
      '3000339',
      '2002999',
      1,
      3,
      360,
      supplier: 'JOAP',
      matched: true,
    );
    component(bom339, '3000339', '2002906', 2, 3, 360, supplier: 'PING HAI');

    final tree = SuppliersByItemNode.parseRows(rows);
    final [item338, belts] = tree;
    final item339 = belts.children.single;
    for (final item in [item338, item339]) {
      expect(item.row.supplierCount, 0);
      expect(item.hasSuppliers, isFalse);
      expect(item.children.map((child) => child.row.kind), [
        SuppliersByItemRowKind.placeholder,
        SuppliersByItemRowKind.bom,
      ]);
      expect(item.children.first.row.treeLabel, 'No supplier recorded');
      expect(item.children.first.row.isComponent, isFalse);
    }
    expect(belts.hasSuppliers, isFalse);
    final mainBom = item338.children.last;
    expect(mainBom.row.bomNo, 'BOM-3000338-001');
    expect(mainBom.row.bomIsDefault, isTrue);
    expect(mainBom.row.bomStatus, 'Submitted');
    expect(mainBom.row.componentCount, 4);
    expect(mainBom.row.componentSupplierCount, 3);
    expect(mainBom.children.map((child) => child.row.itemCode), [
      '3000329',
      '3000281',
      '1004774',
      '1003590',
    ]);
    final subassembly = mainBom.children[1];
    expect(subassembly.row.bomQtyPerUnit, 12);
    expect(
      subassembly.children.first.row.kind,
      SuppliersByItemRowKind.placeholder,
    );
    expect(subassembly.children.first.row.isComponent, isTrue);
    final draftBom = subassembly.children.last;
    expect(draftBom.row.bomNo, 'BOM-3000281-001');
    expect(draftBom.row.bomIsDefault, isTrue);
    expect(draftBom.row.bomStatus, 'Draft');
    expect(draftBom.children.map((child) => child.row.itemCode), [
      '1004879',
      '1004722',
    ]);
    expect(
      draftBom.children.map((child) => child.children.single.row.supplier),
      ['EDGE', 'BOVIS'],
    );

    final beltBom = item339.children.last;
    expect(beltBom.row.treeLabel, 'BOM-3000339-001 · default · 2 components');
    final [firstBeltPart, secondBeltPart] = beltBom.children;
    expect(firstBeltPart.row.itemCode, '2002999');
    expect(firstBeltPart.row.itemName, 'Component 2002999');
    expect(firstBeltPart.row.bomNo, 'BOM-3000339-001');
    expect(firstBeltPart.row.bomQtyPerUnit, 360);
    expect(firstBeltPart.row.stockUom, 'Nos');
    expect(firstBeltPart.row.balanceQty, 50);
    expect(firstBeltPart.row.projectedQty, 60.5);
    expect(firstBeltPart.row.usedInBomCount, 2);
    expect(firstBeltPart.row.lastPurchaseDate, '2026-11-01');
    expect(firstBeltPart.row.includeInManufacturing, isFalse);
    expect(firstBeltPart.row.supplierCount, 1);
    final joap = firstBeltPart.children.single.row;
    expect(joap.itemCode, '2002999');
    expect(joap.supplier, 'JOAP');
    expect(joap.matchedSupplier, isTrue);
    expect(joap.isComponent, isTrue);
    expect(secondBeltPart.row.itemCode, '2002906');
    expect(secondBeltPart.children.single.row.supplier, 'PING HAI');
  });

  test('uses explicit row kinds and never infers component identities', () {
    final item = SuppliersByItemNode.parseRows([
      {'node_id': 'item:ROOT'},
      {
        'row_type': 'bom',
        'node_id': 'other:ROOT|BOM-ID',
        'parent_id': 'item:ROOT',
        'is_component': 1,
      },
      {
        'row_type': 'component',
        'node_id': 'item:ROOT|1|COMPONENT-ID',
        'parent_id': 'other:ROOT|BOM-ID',
        'is_component': 1,
        'bom_cycle': 1,
        'bom_depth_limit': '1',
      },
      {
        'row_type': 'supplier',
        'node_id': 'supplier:item:ROOT|1|COMPONENT-ID|SUPPLIER-ID',
        'parent_id': 'item:ROOT|1|COMPONENT-ID',
        'is_component': 1,
      },
    ]).single;
    final bom = item.children.single;
    expect(bom.row.kind, SuppliersByItemRowKind.bom);
    expect(bom.row.bomNo, isNull);
    final component = bom.children.single;
    expect(component.row.kind, SuppliersByItemRowKind.component);
    expect(component.row.itemCode, isNull);
    expect(component.row.bomCycle, isTrue);
    expect(component.row.bomDepthLimit, isTrue);
    expect(component.children.single.row.itemCode, isNull);
    expect(component.children.single.row.supplier, isNull);
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

  test('lists top-level items once, including opaque identities', () {
    final tree = SuppliersByItemNode.parseRows([
      {'node_id': 'row:opaque|a', 'row_type': 'item', 'item_code': ' A '},
      {'node_id': 'supplier:opaque|first', 'parent_id': 'row:opaque|a'},
      {'node_id': 'row:duplicate|a', 'row_type': 'item', 'item_code': 'A'},
      {'node_id': 'bom:b', 'parent_id': 'item:B'},
      {
        'node_id': 'component:b|part',
        'parent_id': 'bom:b',
        'item_code': 'PART',
      },
      {'node_id': 'item:B'},
      {'node_id': 'opaque|identity', 'row_type': 'item'},
      {'node_id': 'item:opaque|identity'},
    ]);
    expect(
      SuppliersByItemNode.topLevelItems(tree).map((node) => node.row.nodeId),
      ['row:opaque|a', 'item:B', 'opaque|identity', 'item:opaque|identity'],
    );
  });
}
