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

  group('kActionableDocConfigs', () {
    test('covers the four transactional DocTypes in strip order', () {
      expect(kActionableDocConfigs.map((c) => c.doctype).toList(),
          ['Purchase Order', 'Purchase Receipt', 'Stock Entry', 'Delivery Note']);
    });
  });
}
