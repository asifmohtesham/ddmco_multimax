import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_strip.dart';

void main() {
  group('actionableFiltersFor', () {
    test('PO/PR/DN filter on status Draft', () {
      for (final dt in const ['Purchase Order', 'Purchase Receipt', 'Delivery Note']) {
        expect(actionableFiltersFor(dt, ActionableScope.everyone, 'x@y.com'),
            {'status': 'Draft'});
      }
    });

    test('Stock Entry filters on docstatus 0 (no status field)', () {
      expect(actionableFiltersFor('Stock Entry', ActionableScope.everyone, 'x@y.com'),
          {'docstatus': 0});
    });

    test('mine scope adds owner', () {
      expect(actionableFiltersFor('Delivery Note', ActionableScope.mine, 'a@b.com'),
          {'status': 'Draft', 'owner': 'a@b.com'});
      expect(actionableFiltersFor('Stock Entry', ActionableScope.mine, 'a@b.com'),
          {'docstatus': 0, 'owner': 'a@b.com'});
    });

    test('mine scope with null/empty email omits owner', () {
      expect(actionableFiltersFor('Delivery Note', ActionableScope.mine, null),
          {'status': 'Draft'});
      expect(actionableFiltersFor('Delivery Note', ActionableScope.mine, ''),
          {'status': 'Draft'});
    });
  });

  group('actionableCacheKey', () {
    test('mine keys by email; everyone is user-independent', () {
      expect(actionableCacheKey(ActionableScope.mine, 'a@b.com'), 'mine::a@b.com');
      expect(actionableCacheKey(ActionableScope.everyone, 'a@b.com'), 'all');
      expect(actionableCacheKey(ActionableScope.everyone, null), 'all');
    });
  });

  group('scope <-> string', () {
    test('round trips and defaults to mine', () {
      expect(actionableScopeToString(ActionableScope.mine), 'mine');
      expect(actionableScopeToString(ActionableScope.everyone), 'everyone');
      expect(actionableScopeFromString('everyone'), ActionableScope.everyone);
      expect(actionableScopeFromString('mine'), ActionableScope.mine);
      expect(actionableScopeFromString('garbage'), ActionableScope.mine);
      expect(actionableScopeFromString(null), ActionableScope.mine);
    });
  });

  group('actionableFiltersFor — Packing Slip', () {
    test('Packing Slip filters on docstatus 0, never status (virtual field)', () {
      final f = actionableFiltersFor('Packing Slip', ActionableScope.everyone, 'x@y.com');
      expect(f, {'docstatus': 0});
      expect(f.containsKey('status'), isFalse);
    });

    test('Packing Slip under mine adds owner and still uses docstatus', () {
      expect(actionableFiltersFor('Packing Slip', ActionableScope.mine, 'a@b.com'),
          {'docstatus': 0, 'owner': 'a@b.com'});
    });
  });

  group('kActionableDocConfigs', () {
    test('covers the five document DocTypes in strip order', () {
      expect(kActionableDocConfigs.map((c) => c.doctype).toList(), [
        'Purchase Order',
        'Purchase Receipt',
        'Stock Entry',
        'Delivery Note',
        'Packing Slip',
      ]);
    });

    test('labels are the full DocType names', () {
      for (final c in kActionableDocConfigs) {
        expect(c.label, c.doctype);
      }
    });

    test('every config carries preview fields incl. name and owner', () {
      for (final c in kActionableDocConfigs) {
        expect(c.previewFields, contains('name'));
        expect(c.previewFields, contains('owner'));
      }
    });

    test('Packing Slip never requests the virtual status field', () {
      final ps = kActionableDocConfigs.firstWhere((c) => c.doctype == 'Packing Slip');
      expect(ps.previewFields, isNot(contains('status')));
      expect(ps.previewFields, contains('delivery_note'));
    });
  });

  group('defaultActionableSelection', () {
    test('defaults to Tasks when there are open todos', () {
      expect(defaultActionableSelection({'Purchase Order': 5}, 2), 'ToDo');
    });

    test('falls through to the first doctype with work when Tasks is empty', () {
      expect(
        defaultActionableSelection(
            {'Purchase Order': 0, 'Purchase Receipt': 0, 'Stock Entry': 4}, 0),
        'Stock Entry',
      );
    });

    test('respects config order when several have work', () {
      expect(
        defaultActionableSelection({'Delivery Note': 9, 'Purchase Order': 3}, 0),
        'Purchase Order',
      );
    });

    test('returns null when nothing is actionable', () {
      expect(defaultActionableSelection({'Purchase Order': 0}, 0), isNull);
      expect(defaultActionableSelection({}, 0), isNull);
    });
  });
}
