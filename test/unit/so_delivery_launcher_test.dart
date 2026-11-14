import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/delivery_note/so_delivery_launcher.dart';

void main() {
  group('SoDeliveryLauncher.routeArgs', () {
    test('resumes an existing draft in edit mode', () {
      expect(SoDeliveryLauncher.routeArgs('SAL-ORD-1', 'MAT-DN-9'),
          {'name': 'MAT-DN-9', 'mode': 'edit'});
    });

    test('starts a new scan-to-pick DN bound to the order', () {
      for (final none in [null, '']) {
        expect(SoDeliveryLauncher.routeArgs('SAL-ORD-1', none),
            {'name': '', 'mode': 'new', 'salesOrderName': 'SAL-ORD-1'});
      }
    });
  });

  // Pick List policy: a Delivery Note is never pre-filled from its Sales
  // Order — floor staff scan every batched item. ERPNext's mapper may only
  // be used for the DN *header* (items dropped) in the DN form controller.
  test('policy guard: no code path saves make_delivery_note items', () {
    const allowed = 'lib/app/modules/delivery_note/form/delivery_note_form_controller.dart';
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      if (!code.contains("make_delivery_note'")) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (path != allowed || code.contains('frappe.client.insert')) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'Delivery Notes must be built by scanning (Pick List policy); '
            'see docs/sales_order_delivery_flow.md');
  });

  test('the DN form controller drops the mapped items', () {
    final src = File(
            'lib/app/modules/delivery_note/form/delivery_note_form_controller.dart')
        .readAsStringSync();
    expect(src, contains('SoPick.headerFromMappedDn'));
  });
}
