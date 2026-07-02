import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

GlobalSearchTarget _byDoctype(String d) =>
    kGlobalSearchTargets.firstWhere((t) => t.doctype == d);

void main() {
  group('kGlobalSearchTargets', () {
    test('has no duplicate doctypes', () {
      final seen = kGlobalSearchTargets.map((t) => t.doctype).toSet();
      expect(seen.length, kGlobalSearchTargets.length);
    });

    test('every target has a non-empty route and label', () {
      for (final t in kGlobalSearchTargets) {
        expect(t.route, isNotEmpty, reason: '${t.doctype} route');
        expect(t.label, isNotEmpty, reason: '${t.doctype} label');
      }
    });

    test('Item argsFor uses itemCode key', () {
      expect(_byDoctype('Item').argsFor('FG-1'), {'itemCode': 'FG-1'});
      expect(_byDoctype('Item').route, AppRoutes.ITEM_FORM);
    });

    test('view-mode doctypes pass name + mode:view', () {
      for (final d in const [
        'Delivery Note', 'Purchase Receipt', 'Stock Entry', 'Purchase Order',
        'Packing Slip', 'Material Request', 'POS Upload', 'Work Order',
      ]) {
        expect(_byDoctype(d).argsFor('X'), {'name': 'X', 'mode': 'view'},
            reason: d);
      }
    });

    test('Batch opens in edit mode', () {
      expect(_byDoctype('Batch').argsFor('B-1'), {'name': 'B-1', 'mode': 'edit'});
      expect(_byDoctype('Batch').route, AppRoutes.BATCH_FORM);
    });

    test('Job Card and BOM pass name only', () {
      expect(_byDoctype('Job Card').argsFor('JC-1'), {'name': 'JC-1'});
      expect(_byDoctype('BOM').argsFor('BOM-1'), {'name': 'BOM-1'});
    });
  });
}
