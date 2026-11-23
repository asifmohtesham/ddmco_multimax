import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_binding.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_screen.dart';

import '../support/delivery_note_fixture.dart';

void main() {
  tearDown(Get.reset);

  testWidgets(
    'read-only delivery note shows the loaded and refreshed posting date',
    (tester) async {
      final api = registerDeliveryNoteTestServices();
      final note = <String, dynamic>{
        'name': 'DN-001',
        'posting_date': '2026-11-23',
        'docstatus': 1,
        'status': 'To Bill',
      };
      api.existingNote = note;

      await tester.pumpWidget(
        GetMaterialApp(
          home: const SizedBox.shrink(),
          getPages: [
            GetPage(
              name: '/note',
              binding: DeliveryNoteFormBinding(),
              page: () => const DeliveryNoteFormScreen(),
            ),
          ],
        ),
      );
      Get.toNamed('/note', arguments: {'name': 'DN-001', 'mode': 'view'});
      await tester.pumpAndSettle();

      final postingDate = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Posting Date',
      );
      TextField field() => tester.widget<TextField>(postingDate);

      expect(field().readOnly, isTrue);
      expect(field().controller?.text, '2026-11-23');

      note['posting_date'] = '2026-11-24';
      await Get.find<DeliveryNoteFormController>().fetchDocument();
      await tester.pumpAndSettle();
      expect(field().controller?.text, '2026-11-24');
    },
  );
}
