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

  group('searchNavArgsFor', () {
    test('Delivery Note form route gets the canonical name+mode map', () {
      // Regression: DocTypeSearchDelegate used to pass a bare String id,
      // which DeliveryNoteFormController indexed with ['name'] → runtime
      // "type 'String' is not a subtype of type 'int' of 'index'".
      expect(
        searchNavArgsFor(AppRoutes.DELIVERY_NOTE_FORM, 'MAT-DN-00001'),
        {'name': 'MAT-DN-00001', 'mode': 'view'},
      );
    });

    test('Purchase Receipt and POS Upload form routes get name+mode maps', () {
      expect(
        searchNavArgsFor(AppRoutes.PURCHASE_RECEIPT_FORM, 'MAT-PRE-1'),
        {'name': 'MAT-PRE-1', 'mode': 'view'},
      );
      expect(
        searchNavArgsFor(AppRoutes.POS_UPLOAD_FORM, 'PU-1'),
        {'name': 'PU-1', 'mode': 'view'},
      );
    });

    test('Item form route keeps the itemCode key', () {
      expect(
        searchNavArgsFor(AppRoutes.ITEM_FORM, 'FG-1'),
        {'itemCode': 'FG-1'},
      );
    });

    test('Batch form route opens in edit mode', () {
      expect(
        searchNavArgsFor(AppRoutes.BATCH_FORM, 'B-1'),
        {'name': 'B-1', 'mode': 'edit'},
      );
    });

    test('ToDo form route gets the canonical name+mode map', () {
      expect(
        searchNavArgsFor(AppRoutes.TODO_FORM, 'TD-1'),
        {'name': 'TD-1', 'mode': 'view'},
      );
    });

    test('unregistered route falls back to the bare id', () {
      expect(searchNavArgsFor(AppRoutes.LOGIN, 'TD-1'), 'TD-1');
    });
  });

  group('searchTargetForDoctype', () {
    test('resolves a registered doctype to its target', () {
      final target = searchTargetForDoctype('Delivery Note');
      expect(target, isNotNull);
      expect(target!.route, AppRoutes.DELIVERY_NOTE_FORM);
    });

    test('returns null for an unregistered doctype', () {
      expect(searchTargetForDoctype('Sales Invoice'), isNull);
    });
  });
}
