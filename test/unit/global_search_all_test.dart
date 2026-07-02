import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

GlobalSearchTarget _t(String d) => GlobalSearchTarget(
      doctype: d,
      label: d,
      icon: Icons.circle,
      color: Colors.grey,
      route: '/x',
      argsFor: (id) => {'name': id},
    );

GlobalSearchItem _item(String id) =>
    GlobalSearchItem(id: id, title: id, rawData: const {});

void main() {
  final targets = [_t('Item'), _t('Batch'), _t('BOM')];

  group('filterPermittedTargets', () {
    test('drops targets the user cannot read (false)', () {
      final out = GlobalSearchService.filterPermittedTargets(
        targets,
        (d) => d == 'Batch' ? false : true,
      );
      expect(out.map((t) => t.doctype), ['Item', 'BOM']);
    });

    test('keeps targets whose permission is unknown (null)', () {
      final out = GlobalSearchService.filterPermittedTargets(
        targets,
        (d) => d == 'BOM' ? null : true,
      );
      expect(out.map((t) => t.doctype), ['Item', 'Batch', 'BOM']);
    });
  });

  group('buildGroups', () {
    test('preserves order and drops empty groups', () {
      final groups = GlobalSearchService.buildGroups([
        MapEntry(_t('Item'), [_item('A')]),
        MapEntry(_t('Batch'), <GlobalSearchItem>[]),
        MapEntry(_t('BOM'), [_item('B'), _item('C')]),
      ]);
      expect(groups.map((g) => g.target.doctype), ['Item', 'BOM']);
      expect(groups.first.items.single.id, 'A');
      expect(groups.last.items.length, 2);
    });
  });

  group('runSearchAll', () {
    test('fans out only over permitted targets, caps, groups in order',
        () async {
      final calls = <String>[];
      final groups = await GlobalSearchService.runSearchAll(
        targets: targets,
        canRead: (d) => d != 'Batch',
        cap: 2,
        searcher: (doctype) async {
          calls.add(doctype);
          if (doctype == 'Item') {
            return [_item('I1'), _item('I2'), _item('I3')]; // > cap
          }
          if (doctype == 'BOM') return [_item('B1')];
          return [];
        },
      );

      expect(calls.toSet(), {'Item', 'BOM'}); // Batch never searched
      expect(groups.map((g) => g.target.doctype), ['Item', 'BOM']);
      expect(groups.first.items.length, 2); // capped
      expect(groups.last.items.single.id, 'B1');
    });
  });
}
