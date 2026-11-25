import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_layout.dart';

SuppliersByItemRowKey _key(String nodeId) => (nodeId: nodeId);

List<String> _ids(Iterable<SuppliersByItemLayoutRow> rows) =>
    rows.map((row) => row.sourceKey.nodeId).toList();

List<Map<String, Object?>> _als() => [
  {'node_id': 'template:ALS', 'item_name': 'Automatic'},
  {
    'node_id': 'item:2002906',
    'parent_id': 'template:ALS',
    'balance_qty': 2186,
    'stock_uom': 'Nos',
  },
  {
    'node_id': 'supplier:2002906:PING',
    'parent_id': 'item:2002906',
    'supplier_name': 'PING HAI',
  },
  {
    'node_id': 'item:2002907',
    'parent_id': 'template:ALS',
    'balance_qty': 256,
    'stock_uom': 'Nos',
  },
  {
    'node_id': 'supplier:2002907:PING',
    'parent_id': 'item:2002907',
    'supplier_name': 'PING HAI',
  },
];

void main() {
  test(
    'projects standalone, promoted MIX, grouped ALS and empty templates',
    () {
      final source = SuppliersByItemNode.parseRows([
        {'node_id': 'item:STANDALONE'},
        {'node_id': 'template:MIX'},
        {'node_id': 'item:MIX-1', 'parent_id': 'template:MIX'},
        {
          'node_id': 'none:mix',
          'row_type': 'placeholder',
          'parent_id': 'item:MIX-1',
        },
        {
          'node_id': 'bom:raw|1',
          'parent_id': 'item:MIX-1',
          'tree_label': 'MIX-BOM · default · 2 components · draft',
        },
        {
          'node_id': 'component:line|1',
          'parent_id': 'bom:raw|1',
          'item_code': 'MIX-SHELL',
        },
        {
          'node_id': 'supplier:component|1',
          'parent_id': 'component:line|1',
          'supplier': 'SHELL SUPPLIER',
        },
        {
          'node_id': 'component:line|2',
          'parent_id': 'bom:raw|1',
          'item_code': 'MIX-INLAY',
        },
        {
          'node_id': 'supplier:component|2',
          'parent_id': 'component:line|2',
          'supplier': 'INLAY SUPPLIER',
        },
        {'node_id': 'bom:raw|2', 'parent_id': 'item:MIX-1', 'bom_no': 'BOM-2'},
        ..._als(),
        {'node_id': 'template:EMPTY'},
        {
          'node_id': 'supplier:detached',
          'parent_id': 'item:NONE',
          'supplier_name': 'Orphan supplier',
        },
      ]);
      final index = indexReport(source);
      final view = buildTemplateView(index);
      expect(_ids(view), [
        'item:STANDALONE',
        'item:MIX-1',
        'template:ALS',
        'template:EMPTY',
        'supplier:detached',
      ]);
      final promoted = view[1];
      expect(promoted.depth, 0);
      expect(promoted.parentKey, isNull);
      expect(promoted.templateContext, 'MIX');
      expect(promoted.templateNode, same(source[1]));
      expect(promoted.node, same(source[1].children.single));
      expect(_ids(promoted.children), ['none:mix', 'bom:raw|1', 'bom:raw|2']);
      expect(_ids(promoted.children[1].children), [
        'component:line|1',
        'component:line|2',
      ]);
      expect(promoted.children[1].bomLabel, 'MIX-BOM');
      expect(promoted.children[1].children.first.depth, 2);
      expect(
        promoted.children[1].children.first.parentKey,
        promoted.children[1].key,
      );
      final withoutPlaceholders = buildTemplateView(
        index,
        showPlaceholders: false,
      );
      expect(_ids(withoutPlaceholders[1].children), ['bom:raw|1', 'bom:raw|2']);
      expect(source[1].children.single.children.first.row.nodeId, 'none:mix');
      expect(
        source[1].children.single.children[1].row.treeLabel,
        contains('draft'),
      );
      expect(summarize(index).noDirectCount, 2);
      expect(summarize(index).supplierCount, 1);

      final als = view[2];
      expect(als.variantCount, 2);
      expect(als.children.map((row) => row.parentKey), [als.key, als.key]);
      expect(als.children.map((row) => row.depth), [1, 1]);
      expect(view[3].children, isEmpty);
      final browse = defaultExpansion(index, view);
      expect(browse, {als.key});
      final oneAls = searchIndex(index, '2002906');
      expect(_ids(flattenTemplateView(view, {}, search: oneAls).rows), [
        'template:ALS',
        'item:2002906',
      ]);
      expect(oneAls.matchingItemIds, {_key('item:2002906')});
      expect(oneAls.forcedOpen, {als.key});
      final openMix = flattenTemplateView(view, {
        promoted.key,
        _key('bom:raw|1'),
        _key('component:line|1'),
      });
      expect(_ids(openMix.rows.skip(1).take(7)), [
        'item:MIX-1',
        'none:mix',
        'bom:raw|1',
        'component:line|1',
        'supplier:component|1',
        'component:line|2',
        'bom:raw|2',
      ]);
    },
  );

  test(
    'summarizes unique suppliers listed under the item and the same stock as the footer',
    () {
      final als = summarize(indexReport(SuppliersByItemNode.parseRows(_als())));
      expect(als.itemCount, 2);
      expect(als.supplierCount, 1);
      expect(als.noDirectCount, 0);
      expect(als.totalsByUom['Nos']!.balanceQty, 2442);

      final source = SuppliersByItemNode.parseRows([
        ..._als(),
        {
          'node_id': 'supplier:2002906:ANOTHER',
          'parent_id': 'item:2002906',
          'supplier_name': 'PING HAI',
        },
        {'node_id': 'item:WITHOUT', 'balance_qty': null, 'stock_uom': 'Set'},
        {'node_id': 'item:ZERO', 'balance_qty': 0, 'stock_uom': 'Box'},
        {'node_id': 'item:NEGATIVE', 'balance_qty': -1, 'stock_uom': 'Kg'},
        {'node_id': 'item:UNKNOWN', 'balance_qty': 10},
        {
          'node_id': 'opaque-unresolved-supplier',
          'row_type': 'supplier',
          'parent_id': 'item:UNKNOWN',
          'supplier_name': 'UNIDENTIFIED',
        },
      ]);
      final index = indexReport(source);
      final summary = summarize(index);
      expect(summary.itemCount, 6);
      expect(summary.supplierCount, 2);
      expect(summary.noDirectCount, 3);
      expect(summary.hasUnknownStockUom, isTrue);
      Map<String, num?> balances(
        Map<String, SuppliersByItemQuantityTotals> totals,
      ) => totals.map((key, value) => MapEntry(key, value.balanceQty));
      final totals = balances(summary.totalsByUom);
      expect(totals, {'Nos': 2442, 'Box': 0, 'Kg': -1});
      expect(totals, balances(SuppliersByItemNode.quantityTotalsByUom(source)));
      final projection = buildTemplateView(index);
      expect(projection.first.directSupplierCount, 2);
      expect(
        projection.first.children.first.children.map(
          (row) => row.supplierLabel,
        ),
        ['PING HAI (PING)', 'PING HAI (ANOTHER)'],
      );
      expect(projection.last.directSupplierCount, isNull);
      expect(projection.last.hasDirectSupplier, isTrue);
      expect(searchIndex(index, 'NEGATIVE').matchingItemIds, {
        _key('item:NEGATIVE'),
      });
      expect(summarize(index), same(summary));
      expect(balances(summary.totalsByUom), totals);
    },
  );

  test(
    'searches folded identity tokens on one source trail and keeps other suppliers',
    () {
      final index = indexReport(
        SuppliersByItemNode.parseRows([
          ..._als(),
          {'node_id': 'template:MIX', 'item_name': 'Caf\u00e9 family'},
          {
            'node_id': 'item:MIX|:A',
            'parent_id': 'template:MIX',
            'item_name': 'Tasse',
          },
          {
            'node_id': 'supplier:MIX|:A:ONE',
            'parent_id': 'item:MIX|:A',
            'supplier_name': 'L\u00f3pez',
          },
          {
            'node_id': 'supplier:MIX|:A:TWO',
            'parent_id': 'item:MIX|:A',
            'supplier_name': 'Other source',
          },
          {
            'node_id': 'bom:opaque|mix',
            'parent_id': 'item:MIX|:A',
            'tree_label': 'Shells · 2 components · draft',
          },
          {
            'node_id': 'component:line|a',
            'parent_id': 'bom:opaque|mix',
            'item_code': 'SHELL-A',
            'item_name': 'Brass',
          },
          {
            'node_id': 'bom:deep|opaque',
            'parent_id': 'component:line|a',
            'bom_no': 'BOM:NESTED',
          },
          {
            'node_id': 'component:repeat|a',
            'parent_id': 'bom:deep|opaque',
            'item_code': 'INNER|PART',
            'item_name': 'Cafe\u0301 lug',
          },
          {
            'node_id': 'supplier:repeat|a',
            'parent_id': 'component:repeat|a',
            'supplier': 'FIRST:VENDOR',
          },
          {
            'node_id': 'component:line|b',
            'parent_id': 'bom:opaque|mix',
            'item_code': 'INNER|PART',
            'item_name': 'Cafe\u0301 lug',
          },
          {
            'node_id': 'supplier:repeat|b',
            'parent_id': 'component:line|b',
            'supplier': 'SECOND:VENDOR',
          },
          {'node_id': 'item:DECOMPOSED', 'item_name': 'Re\u0301sume\u0301'},
          {
            'node_id': 'supplier:orphan',
            'parent_id': 'item:MISSING',
            'supplier_name': 'Loose evidence',
          },
        ]),
      );
      final projection = buildTemplateView(index);
      final browse = {_key('template:ALS'), _key('item:2002907')};
      final before = flattenTemplateView(projection, browse).rows;

      final family = searchIndex(index, '  CAFE\u0301   FAMILY ');
      expect(family.matchingItemIds, {_key('item:MIX|:A')});
      expect(family.forcedOpen, isEmpty);
      expect(_ids(flattenTemplateView(projection, {}, search: family).rows), [
        'item:MIX|:A',
      ]);

      final supplier = searchIndex(index, ' mix|:a   LOPEZ  ');
      expect(supplier.matchingItemIds, {_key('item:MIX|:A')});
      expect(supplier.forcedOpen, {_key('item:MIX|:A')});
      expect(_ids(flattenTemplateView(projection, {}, search: supplier).rows), [
        'item:MIX|:A',
        'supplier:MIX|:A:ONE',
        'supplier:MIX|:A:TWO',
        'bom:opaque|mix',
      ]);

      final nested = searchIndex(
        index,
        'TASSE BOM:NESTED INNER|PART FIRST:VENDOR',
      );
      expect(nested.matchingItemIds, {_key('item:MIX|:A')});
      expect(nested.forcedOpen, {
        _key('item:MIX|:A'),
        _key('bom:opaque|mix'),
        _key('component:line|a'),
        _key('bom:deep|opaque'),
        _key('component:repeat|a'),
      });
      final manual = {_key('component:line|b')};
      final results = flattenTemplateView(projection, manual, search: nested);
      expect(
        results.indexByKey.keys,
        containsAll([_key('supplier:repeat|a'), _key('supplier:repeat|b')]),
      );
      final repeatedPart = searchIndex(index, 'inner|part');
      expect(repeatedPart.matchingItemIds, {_key('item:MIX|:A')});
      expect(repeatedPart.forcedOpen, {
        _key('item:MIX|:A'),
        _key('bom:opaque|mix'),
        _key('component:line|a'),
        _key('bom:deep|opaque'),
      });
      expect(
        _ids(flattenTemplateView(projection, {}, search: repeatedPart).rows),
        [
          'item:MIX|:A',
          'supplier:MIX|:A:ONE',
          'supplier:MIX|:A:TWO',
          'bom:opaque|mix',
          'component:line|a',
          'bom:deep|opaque',
          'component:repeat|a',
          'component:line|b',
        ],
      );
      expect(
        searchIndex(index, 'BOM:NESTED SECOND:VENDOR').matchingItemIds,
        isEmpty,
      );
      expect(searchIndex(index, 'lopez other').matchingItemIds, isEmpty);
      expect(searchIndex(index, 'shells draft').matchingItemIds, isEmpty);
      expect(searchIndex(index, 'r\u00e9sum\u00e9').matchingItemIds, {
        _key('item:DECOMPOSED'),
      });
      expect(searchIndex(index, 'loose evidence').matchingOtherIds, {
        _key('supplier:orphan'),
      });
      expect(searchIndex(index, 'loose evidence').matchingItemIds, isEmpty);
      expect(
        flattenTemplateView(
          projection,
          browse,
          search: searchIndex(index, '   '),
        ).rows,
        before,
      );
      expect(browse, {_key('template:ALS'), _key('item:2002907')});
    },
  );

  test('folds Arabic harakat, tatweel and Unicode marks on both sides', () {
    final index = indexReport(
      SuppliersByItemNode.parseRows([
        {'node_id': 'item:A'},
        {
          'node_id': 'supplier:A:ONE',
          'parent_id': 'item:A',
          'supplier_name': 'الشَّرِكة',
        },
        {'node_id': 'item:B'},
        {
          'node_id': 'supplier:B:TWO',
          'parent_id': 'item:B',
          'supplier_name': 'الشركة',
        },
      ]),
    );
    const queries = ['الشركة', 'الشَّرِكة', 'الشـَّرِكة\u0670\u06d6\u1ab0'];
    for (final query in queries) {
      final result = searchIndex(index, query);
      expect(result.matchingItemIds, {_key('item:A'), _key('item:B')});
      expect(result.forcedOpen, result.matchingItemIds);
      expect(
        _ids(
          flattenTemplateView(
            buildTemplateView(index),
            {},
            search: result,
          ).rows,
        ),
        ['item:A', 'supplier:A:ONE', 'item:B', 'supplier:B:TWO'],
      );
    }
  });

  test(
    'stops BOM descent at the branch limit and repeated codes, retaining pair rows',
    () {
      final input = <Map<String, Object?>>[
        {'node_id': 'item:A'},
        {'node_id': 'bom:cycle', 'parent_id': 'item:A'},
        {
          'node_id': 'component:repeat|a',
          'parent_id': 'bom:cycle',
          'item_code': 'A',
        },
        {
          'node_id': 'supplier:cycle|a',
          'parent_id': 'component:repeat|a',
          'supplier': 'DIRECT',
        },
        {'node_id': 'bom:block-repeat', 'parent_id': 'component:repeat|a'},
        {
          'node_id': 'component:flag',
          'parent_id': 'bom:cycle',
          'item_code': 'FLAG',
          'bom_depth_limit': 1,
        },
        {'node_id': 'bom:block-flag', 'parent_id': 'component:flag'},
        {
          'node_id': 'component:sibling',
          'parent_id': 'bom:cycle',
          'item_code': 'B',
        },
        {'node_id': 'bom:kept', 'parent_id': 'component:sibling'},
      ];
      for (var level = 1; level <= 11; level++) {
        input.addAll([
          {
            'node_id': 'bom:depth|$level',
            'parent_id': level == 1 ? 'item:A' : 'component:depth|${level - 1}',
          },
          {
            'node_id': 'component:depth|$level',
            'parent_id': 'bom:depth|$level',
            'item_code': 'PART-$level',
          },
        ]);
      }
      input.add({
        'node_id': 'supplier:depth|10',
        'parent_id': 'component:depth|10',
        'supplier': 'TERMINAL',
      });
      final index = indexReport(SuppliersByItemNode.parseRows(input));
      final projection = buildTemplateView(index);
      final all = flattenTemplateView(projection, structuralKeys(projection));
      expect(
        all.indexByKey.keys,
        containsAll([
          _key('supplier:cycle|a'),
          _key('supplier:depth|10'),
          _key('bom:kept'),
        ]),
      );
      expect(all.indexByKey, isNot(contains(_key('bom:depth|11'))));
      expect(all.indexByKey, isNot(contains(_key('bom:block-repeat'))));
      expect(all.indexByKey, isNot(contains(_key('bom:block-flag'))));
      expect(index.nodesById, contains('bom:block-flag'));
      expect(searchIndex(index, 'terminal').matchingItemIds, {_key('item:A')});

      final supplier = buildSupplierView(index);
      expect(supplier.map((row) => row.group!.label), [
        'DIRECT',
        'TERMINAL',
        'No supplier recorded',
      ]);
      expect(supplier[0].children.single.componentPath, 'A › BOM 1 › A');
      final last = supplier[1].children.single;
      expect(last.componentTrail.length, 20);
      expect(last.componentTrail.last.row.itemCode, 'PART-10');
      final supplierAll = flattenTemplateView(
        supplier,
        structuralKeys(supplier),
      );
      expect(_ids(supplierAll.rows), isNot(contains('bom:depth|11')));
      expect(_ids(supplierAll.rows), isNot(contains('bom:block-repeat')));
      expect(_ids(supplierAll.rows), isNot(contains('bom:block-flag')));
    },
  );

  test(
    'supplier memberships keep complete opaque occurrences and one total',
    () {
      final index = _membershipIndex();
      final projection = buildSupplierView(index);
      final edgeKey = (SuppliersByItemOccurrence.supplierGroup, 'EDGE');
      final lockalKey = (SuppliersByItemOccurrence.supplierGroup, 'LOCKAL');
      final noDirectKey = (SuppliersByItemOccurrence.noDirectGroup,);
      final groupByKey = {for (final row in projection) row.key: row};
      final edge = groupByKey[edgeKey]!;
      final lockal = groupByKey[lockalKey]!;
      final noDirect = groupByKey[noDirectKey]!;
      expect(projection.map((row) => row.group!.label), [
        'Parts only',
        'Same vendor (EDGE)',
        'Same vendor (LOCKAL)',
        'Unidentified vendor',
        'No supplier recorded',
        'Other report rows',
      ]);
      expect(edge.group!.directItemCount, 1);
      expect(edge.group!.componentMatchCount, 2);
      expect(lockal.group!.directItemCount, 1);
      expect(lockal.group!.componentMatchCount, 1);
      expect(lockal.group!.matchedSupplier, isTrue);
      expect(projection.first.group!.directItemCount, 0);
      expect(projection.first.group!.componentMatchCount, 1);
      expect(noDirect.group!.directItemCount, 2);
      expect(noDirect.group!.componentMatchCount, 0);

      final direct = edge.children.first;
      final directKey = (edgeKey, SuppliersByItemOccurrence.direct, 'item:A');
      expect(direct.key, directKey);
      expect(direct.ownerKey, _key('item:A'));
      expect(direct.pairNode!.row.lastPurchaseDate, '2023-01-01');
      expect(
        lockal.children.first.pairNode!.row.lastPurchaseDate,
        '2026-11-10',
      );
      expect(direct.children.single.key, (directKey, 'bom:|A'));
      expect(direct.children.single.node, same(index.nodesById['bom:|A']));
      expect(edge.children.skip(1).map((row) => row.componentPath), [
        'A › BOM-A › COG (line 1)',
        'A › BOM-A › COG (line 2)',
      ]);
      expect(edge.children[2].key, (
        edgeKey,
        SuppliersByItemOccurrence.componentMatch,
        'item:A',
        'component:|A:2',
        'pair:|A:2',
      ));
      final nested = lockal.children.last;
      expect(
        nested.componentPath,
        'A › BOM-A › COG (line 1) › BOM-NEST › DEEP',
      );
      expect(nested.componentTrail.map((node) => node.row.nodeId), [
        'bom:|A',
        'component:|A:1',
        'bom:|nest',
        'component:|deep',
      ]);
      expect(nested.pairNode!.row.supplierStatus, 'On Hold');
      expect(nested.pairNode!.row.lastPurchaseDate, '2025-10-01');
      expect(nested.parentOutputUom, 'Nos');
      final noDirectB = noDirect.children.firstWhere(
        (row) => row.sourceKey.nodeId == 'item:B',
      );
      expect(noDirectB.key, (
        noDirectKey,
        SuppliersByItemOccurrence.direct,
        'item:B',
      ));
      expect(_ids(noDirectB.children), ['none:B', 'bom:|B']);
      expect(noDirectB.hasDirectSupplier, isFalse);
      expect(
        defaultExpansion(
          index,
          projection,
          group: SuppliersByItemGroup.supplier,
        ),
        {projection.first.key},
      );
      final visible = flattenTemplateView(
        projection,
        structuralKeys(projection),
      );
      expect(visible.indexByKey.length, visible.rows.length);
      expect(
        visible.rows.map((row) => row.key).toSet(),
        hasLength(visible.rows.length),
      );

      final summary = summarize(index);
      expect(summary.itemCount, 4);
      expect(summary.supplierCount, 2);
      expect(summary.noDirectCount, 2);
      expect(summary.totalsByUom['Nos']!.balanceQty, 3);
      expect(summary.totalsByUom['Kg']!.balanceQty, 1);
      expect(summary.totalsByUom['Nos']!.openOrderQty, 0);
      expect(summary.totalsByUom['Nos']!.projectedQty, -3);
    },
  );

  test(
    'supplier search remaps only actual hits and keeps complete memberships',
    () {
      final index = _membershipIndex();
      final view = buildSupplierView(index);
      final edge = view[1];
      final lockal = view[2];
      final noDirect = view[4];
      SuppliersByItemSearch search(String query) =>
          searchIndex(index, query, group: SuppliersByItemGroup.supplier);

      final query = 'owner-a BOM-NEST DEEP LOCKAL';
      final nested = search(query);
      expect(nested.matchingItemIds, searchIndex(index, query).matchingItemIds);
      expect(nested.matchingItemIds, {_key('item:A')});
      expect(nested.forcedOpen, {lockal.key});
      final nestedVisible = flattenTemplateView(view, {}, search: nested);
      expect(nestedVisible.rows.map((row) => row.key), [
        edge.key,
        lockal.key,
        for (final row in lockal.children) row.key,
      ]);
      expect(
        flattenTemplateView(view, {edge.key}, search: nested).rows,
        containsAll(edge.children),
      );
      expect(search('OWNER-A').forcedOpen, {edge.key, lockal.key});
      expect(search('OWNER-B').forcedOpen, {noDirect.key});
      expect(search('BOM-NEST EDGE').matchingItemIds, isEmpty);
      expect(search('EDGE').forcedOpen, {edge.key});
      expect(search('COG').forcedOpen, {edge.key});
      expect(
        _ids(flattenTemplateView(view, {}, search: search('BOM-NEST')).rows),
        contains('bom:|nest'),
      );

      final unsourced = search('MISSING-PART');
      final branch = noDirect.children.firstWhere(
        (row) => row.sourceKey.nodeId == 'item:B',
      );
      expect(unsourced.matchingItemIds, {_key('item:B')});
      expect(unsourced.forcedOpen, {
        noDirect.key,
        branch.key,
        branch.children.last.key,
      });
      expect(
        _ids(flattenTemplateView(view, {}, search: unsourced).rows),
        contains('component:|missing'),
      );
      final orphans = search('Unattached supplier');
      expect(orphans.matchingItemIds, isEmpty);
      expect(orphans.matchingOtherIds, {_key('supplier:loose')});
      expect(orphans.forcedOpen, {view.last.key});
      expect(
        _ids(flattenTemplateView(view, {}, search: orphans).rows).last,
        'supplier:loose',
      );
      expect(summarize(index).totalsByUom['Nos']!.balanceQty, 3);
    },
  );

  test('counts retained direct owners in collapsed supplier groups', () {
    final index = _membershipIndex();
    final projection = buildSupplierView(index);
    final noDirect = projection.firstWhere((row) => row.group!.isNoDirect);
    final ownerB = noDirect.children.firstWhere(
      (row) => row.ownerKey == _key('item:B'),
    );
    final ownerC = noDirect.children.firstWhere(
      (row) => row.ownerKey == _key('item:C'),
    );
    final search = searchIndex(
      index,
      'Parts only',
      group: SuppliersByItemGroup.supplier,
    );

    expect(noDirect.group!.retainedDirectItemCount, isNull);
    final collapsed = flattenTemplateView(projection, {}, search: search);
    final heading = collapsed.rows[collapsed.indexByKey[noDirect.key]!];
    expect(heading.group!.retainedDirectItemCount, 1);
    expect(heading.group!.directItemCount, 2);
    expect(collapsed.indexByKey.containsKey(ownerB.key), isFalse);

    final expanded = flattenTemplateView(projection, {
      noDirect.key,
    }, search: search);
    expect(
      expanded
          .rows[expanded.indexByKey[noDirect.key]!]
          .group!
          .retainedDirectItemCount,
      1,
    );
    expect(expanded.indexByKey.containsKey(ownerB.key), isTrue);
    expect(expanded.indexByKey.containsKey(ownerC.key), isFalse);
  });

  test(
    'counts zero retained component matches when only a direct item matches',
    () {
      final index = indexReport(
        SuppliersByItemNode.parseRows([
          {'node_id': 'item:AX'},
          _pair('pair:AX:vendor', 'item:AX', 'VENDOR'),
          {'node_id': 'item:BY'},
          {'node_id': 'bom:BY', 'parent_id': 'item:BY'},
          {
            'node_id': 'component:COG',
            'parent_id': 'bom:BY',
            'item_code': 'COG',
          },
          _pair('pair:COG:vendor', 'component:COG', 'VENDOR'),
        ]),
      );
      final projection = buildSupplierView(index);
      final vendor = projection.first;

      SuppliersByItemVisibleRows matching(String query) => flattenTemplateView(
        projection,
        {},
        search: searchIndex(index, query, group: SuppliersByItemGroup.supplier),
      );

      final direct = matching('AX');
      expect(direct.rows.first.group!.retainedDirectItemCount, 1);
      expect(direct.rows.first.group!.retainedComponentMatchCount, 0);
      expect(direct.rows.first.group!.componentMatchCount, 1);
      expect(direct.indexByKey.containsKey(vendor.children.last.key), isFalse);

      final component = matching('COG');
      expect(component.rows.first.group!.retainedDirectItemCount, 0);
      expect(component.rows.first.group!.retainedComponentMatchCount, 1);
      expect(
        component.indexByKey.containsKey(vendor.children.last.key),
        isTrue,
      );
    },
  );

  test('returned Supplier Count controls sorting and missing-child scope', () {
    final index = indexReport(
      SuppliersByItemNode.parseRows([
        {'node_id': 'item:A', 'supplier_count': 4},
        {'node_id': 'supplier:A:S', 'parent_id': 'item:A', 'supplier': 'S'},
        {'node_id': 'item:B'},
        {'node_id': 'supplier:B:S', 'parent_id': 'item:B', 'supplier': 'S'},
        {'node_id': 'item:C', 'supplier_count': 2},
        {'node_id': 'item:D', 'supplier_count': 0},
      ]),
    );
    const view = SuppliersByItemView(
      sortField: SuppliersByItemSortField.supplierCount,
      sortDirection: SuppliersByItemSortDirection.desc,
    );
    final items = buildTemplateView(index, view: view);
    expect(items.map((row) => row.node.row.itemCode), ['A', 'C', 'B', 'D']);
    expect(items.map((row) => row.directSupplierCount), [4, 2, 1, 0]);
    expect(items.map((row) => row.hasDirectSupplier), [
      true,
      true,
      true,
      false,
    ]);

    final groups = buildSupplierView(index, view: view);
    final supplier = groups.singleWhere((row) => row.group?.label == 'S');
    expect(supplier.children.map((row) => row.node.row.itemCode), ['A', 'B']);
    expect(supplier.children.map((row) => row.directSupplierCount), [4, 1]);
    final noSupplier = groups.singleWhere((row) => row.group!.isNoDirect);
    expect(noSupplier.children.single.node.row.itemCode, 'D');
    final other = groups.singleWhere((row) => row.group!.isOther);
    expect(other.children.single.node.row.itemCode, 'C');
    expect(summarize(index).noDirectCount, 1);
  });

  test('sorts template and supplier siblings for each field and direction', () {
    final index = _sortIndex();
    const stock = SuppliersByItemSortField.stock;
    const count = SuppliersByItemSortField.supplierCount;
    const date = SuppliersByItemSortField.lastPurchase;
    const asc = SuppliersByItemSortDirection.asc;
    const desc = SuppliersByItemSortDirection.desc;
    final cases =
        <
          (SuppliersByItemSortField, SuppliersByItemSortDirection),
          ({String roots, String variants, String direct, String matches})
        >{
          (stock, asc): (
            roots: 'E d B C a T F G H MIX',
            variants: 'V v',
            direct: 'E d V B C X a F H',
            matches: 'Q P p N U',
          ),
          (stock, desc): (
            roots: 'd E T a C B F G H MIX',
            variants: 'v V',
            direct: 'd E a X C B V F H',
            matches: 'Q N P p U',
          ),
          (count, asc): (
            roots: 'G B C E H d MIX T a F',
            variants: 'V v',
            direct: 'B C E H V X d a F',
            matches: 'N P Q U p',
          ),
          (count, desc): (
            roots: 'MIX T a B C E H d G F',
            variants: 'V v',
            direct: 'a B C E H V X d F',
            matches: 'p N P Q U',
          ),
          (date, asc): (
            roots: 'MIX d T F B C a E G H',
            variants: 'V v',
            direct: 'X d V a F B C E H',
            matches: 'P p N Q U',
          ),
          (date, desc): (
            roots: 'a B C F T d MIX E G H',
            variants: 'v V',
            direct: 'B C F a V d X E H',
            matches: 'N P p Q U',
          ),
        };
    Iterable<String?> codes(Iterable<SuppliersByItemLayoutRow> rows) =>
        rows.map((row) => row.node.row.template ?? row.node.row.itemCode);

    for (final MapEntry(key: (field, direction), value: expected)
        in cases.entries) {
      final settings = SuppliersByItemView(
        sortField: field,
        sortDirection: direction,
      );
      final reason = '${field.name} ${direction.name}';
      final template = buildTemplateView(index, view: settings);
      expect(
        codes(template.take(template.length - 1)),
        expected.roots.split(' '),
        reason: reason,
      );
      expect(template.last.sourceKey.nodeId, 'supplier:unplaced');
      final homogeneous = template.firstWhere(
        (row) => row.sourceKey.nodeId == 'template:T',
      );
      // A variant also carries the legacy template ID, so inspect its item ID.
      expect(
        homogeneous.children.map((row) => row.node.row.itemCode),
        expected.variants.split(' '),
        reason: reason,
      );
      final root = template.firstWhere(
        (row) => row.sourceKey.nodeId == 'item:a',
      );
      expect(_ids(root.children), ['pair:a:G', 'pair:a:O', 'bom:Z', 'bom:A']);
      expect(_ids(root.children[2].children), [
        'component:U',
        'component:p',
        'component:Q',
        'component:P',
        'component:N',
      ]);

      final supplier = buildSupplierView(index, view: settings);
      expect(supplier.map((row) => row.group!.label), [
        'G',
        'O',
        'Unknown count vendor',
        'No supplier recorded',
        'Other report rows',
      ]);
      final entries = supplier.first.children;
      Iterable<String?> itemCodes(Iterable<SuppliersByItemLayoutRow> rows) =>
          rows.map((row) => row.node.row.itemCode);
      expect(
        itemCodes(entries.take(9)),
        expected.direct.split(' '),
        reason: reason,
      );
      expect(
        itemCodes(entries.skip(9)),
        expected.matches.split(' '),
        reason: reason,
      );
      final direct = entries.firstWhere(
        (row) => row.sourceKey.nodeId == 'item:a',
      );
      expect(_ids(direct.children), ['bom:Z', 'bom:A']);
      expect(
        _ids(direct.children.first.children),
        _ids(root.children[2].children),
      );
    }
  });

  test('accepts only a valid calendar date for pair comparison', () {
    expect(strictReportDate('2024-02-29'), DateTime.utc(2024, 2, 29));
    for (final invalid in [
      null,
      '2025-02-29',
      '2025-1-01',
      '2025-04-31',
      '2025-01-01T00:00:00',
    ]) {
      expect(strictReportDate(invalid), isNull);
    }
  });
}

Map<String, Object?> _pair(
  String id,
  String parent,
  String? supplier, {
  String? name,
  String? date,
  bool matched = false,
  String? status,
}) => {
  'node_id': id,
  'row_type': 'supplier',
  'parent_id': parent,
  'supplier': supplier,
  'supplier_name': name,
  'last_purchase_date': date,
  'matched_supplier': matched,
  'supplier_status': status,
};

SuppliersByItemIndex _membershipIndex() => indexReport(
  SuppliersByItemNode.parseRows([
    {
      'node_id': 'item:A',
      'item_name': 'OWNER-A',
      'stock_uom': 'Nos',
      'balance_qty': -2,
      'open_order_qty': 0,
      'projected_qty': -3,
    },
    _pair(
      'pair:edge',
      'item:A',
      'EDGE',
      name: 'Same vendor',
      date: '2023-01-01',
    ),
    _pair(
      'pair:lockal',
      'item:A',
      'LOCKAL',
      name: 'Same vendor',
      date: '2026-11-10',
    ),
    {'node_id': 'bom:|A', 'parent_id': 'item:A', 'bom_no': 'BOM-A'},
    {
      'node_id': 'component:|A:1',
      'parent_id': 'bom:|A',
      'item_code': 'COG',
      'stock_uom': 'Nos',
      'balance_qty': 100,
    },
    _pair('pair:|A:1', 'component:|A:1', 'EDGE', date: '2024-01-01'),
    {
      'node_id': 'bom:|nest',
      'parent_id': 'component:|A:1',
      'bom_no': 'BOM-NEST',
    },
    {
      'node_id': 'component:|deep',
      'parent_id': 'bom:|nest',
      'item_code': 'DEEP',
    },
    _pair(
      'pair:|deep',
      'component:|deep',
      'LOCKAL',
      date: '2025-10-01',
      matched: true,
      status: 'On Hold',
    ),
    {'node_id': 'component:|A:2', 'parent_id': 'bom:|A', 'item_code': 'COG'},
    _pair('pair:|A:2', 'component:|A:2', 'EDGE'),
    {
      'node_id': 'item:duplicated',
      'item_code': 'A',
      'stock_uom': 'Nos',
      'balance_qty': 200000,
    },
    _pair(
      'pair:edge:duplicate',
      'item:duplicated',
      'EDGE',
      name: 'Later name',
      date: '2025-01-01',
    ),
    {
      'node_id': 'item:B',
      'item_name': 'OWNER-B',
      'stock_uom': 'Nos',
      'balance_qty': 5,
    },
    {'node_id': 'none:B', 'parent_id': 'item:B', 'row_type': 'placeholder'},
    {'node_id': 'bom:|B', 'parent_id': 'item:B', 'bom_no': 'BOM-B'},
    {'node_id': 'component:|B', 'parent_id': 'bom:|B', 'item_code': 'BOBBIN'},
    _pair('pair:|B', 'component:|B', 'PARTS', name: 'Parts only'),
    {
      'node_id': 'component:|missing',
      'parent_id': 'bom:|B',
      'item_code': 'MISSING-PART',
    },
    {'node_id': 'item:C', 'stock_uom': 'Kg', 'balance_qty': 1},
    {'node_id': 'item:D'},
    _pair('pair:unresolved', 'item:D', null, name: 'Unidentified vendor'),
    _pair(
      'supplier:loose',
      'item:missing',
      'NONE',
      name: 'Unattached supplier',
    ),
  ]),
);

SuppliersByItemIndex _sortIndex() {
  Map<String, Object?> item(
    String code,
    num? stock,
    String? uom, {
    String? parent,
  }) => {
    'node_id': 'item:$code',
    'parent_id': parent,
    'balance_qty': stock,
    'stock_uom': uom,
  };
  Map<String, Object?> component(String code, num stock, String? uom) => {
    'node_id': 'component:$code',
    'parent_id': 'bom:Z',
    'item_code': code,
    'balance_qty': stock,
    'stock_uom': uom,
  };
  return indexReport(
    SuppliersByItemNode.parseRows([
      item('B', -2, 'Nos'),
      _pair('pair:B:G', 'item:B', 'G', date: '2024-08-04'),
      item('a', 3, 'Nos'),
      _pair('pair:a:G', 'item:a', 'G', date: '2023-01-01'),
      _pair('pair:a:O', 'item:a', 'O', date: '2025-10-10'),
      {'node_id': 'bom:Z', 'parent_id': 'item:a'},
      component('U', 50, null),
      _pair('pair:U:G', 'component:U', 'G'),
      component('p', -1, 'Nos'),
      _pair('pair:p:G', 'component:p', 'G', date: '2024-01-01'),
      _pair('pair:p:O', 'component:p', 'O', date: '2026-01-01'),
      component('Q', 100, 'Kg'),
      _pair('pair:Q:G', 'component:Q', 'G', date: '2025-02-30'),
      component('P', -1, 'Nos'),
      _pair('pair:P:G', 'component:P', 'G', date: '2024-01-01'),
      component('N', 7, 'Nos'),
      _pair('pair:N:G', 'component:N', 'G', date: '2025-01-01'),
      {'node_id': 'bom:A', 'parent_id': 'item:a'},
      item('C', 0, 'Nos'),
      _pair('pair:C:G', 'item:C', 'G', date: '2024-08-04'),
      item('E', 1, 'Kg'),
      _pair('pair:E:G', 'item:E', 'G', date: '2025-02-30'),
      item('d', 100, 'Kg'),
      _pair('pair:d:G', 'item:d', 'G', date: '2022-06-04'),
      item('H', null, 'Nos'),
      _pair('pair:H:G', 'item:H', 'G'),
      item('F', null, 'Nos'),
      _pair('pair:F:G', 'item:F', 'G', date: '2023-12-02'),
      _pair('pair:F:unknown', 'item:F', null, name: 'Unknown count vendor'),
      item('G', 50, null),
      {'node_id': 'template:T', 'balance_qty': 9, 'stock_uom': 'Nos'},
      item('v', 4, 'Nos', parent: 'template:T'),
      _pair('pair:v:O', 'item:v', 'O', date: '2023-07-04'),
      item('V', -3, 'Nos', parent: 'template:T'),
      _pair('pair:V:G', 'item:V', 'G', date: '2022-11-04'),
      {'node_id': 'template:MIX', 'balance_qty': 10000, 'stock_uom': 'Nos'},
      item('X', 2, 'Nos', parent: 'template:MIX'),
      _pair('pair:X:G', 'item:X', 'G', date: '2021-11-04'),
      item('x', 8, 'Kg', parent: 'template:MIX'),
      _pair('pair:x:O', 'item:x', 'O'),
      _pair('supplier:unplaced', 'item:missing', 'ORPHAN'),
    ]),
  );
}
