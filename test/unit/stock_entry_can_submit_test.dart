import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

void main() {
  group('StockEntryFormController.computeCanSubmit', () {
    // A clean, saved draft with submit permission and nothing in flight.
    bool call({
      String mode = 'edit',
      int? docStatus = 0,
      bool isDirty = false,
      bool isSaving = false,
      bool isSubmitting = false,
      bool canSubmitPerm = true,
    }) =>
        StockEntryFormController.computeCanSubmit(
          mode: mode,
          docStatus: docStatus,
          isDirty: isDirty,
          isSaving: isSaving,
          isSubmitting: isSubmitting,
          canSubmitPerm: canSubmitPerm,
        );

    test('T-1: clean saved draft with permission → true', () {
      expect(call(), isTrue);
    });

    test('T-2: new document → false', () {
      expect(call(mode: 'new'), isFalse);
    });

    test('T-3: dirty draft → false', () {
      expect(call(isDirty: true), isFalse);
    });

    test('T-4: already submitted (docstatus 1) → false', () {
      expect(call(docStatus: 1), isFalse);
    });

    test('T-5: null docstatus → false', () {
      expect(call(docStatus: null), isFalse);
    });

    test('T-6: no submit permission → false', () {
      expect(call(canSubmitPerm: false), isFalse);
    });

    test('T-7: save in flight → false', () {
      expect(call(isSaving: true), isFalse);
    });

    test('T-8: submit in flight → false', () {
      expect(call(isSubmitting: true), isFalse);
    });
  });
}
