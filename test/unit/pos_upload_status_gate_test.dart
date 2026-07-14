import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_controller.dart';

void main() {
  group('PosUploadFormController.computeCanEditStatus', () {
    test('editable when write perm confirmed, not saving, not stale', () {
      expect(
        PosUploadFormController.computeCanEditStatus(
          canWritePerm: true,
          isSaving: false,
          isStale: false,
        ),
        isTrue,
      );
    });

    test('blocked without write permission (fail-closed default)', () {
      expect(
        PosUploadFormController.computeCanEditStatus(
          canWritePerm: false,
          isSaving: false,
          isStale: false,
        ),
        isFalse,
      );
    });

    test('blocked while a save is in flight', () {
      expect(
        PosUploadFormController.computeCanEditStatus(
          canWritePerm: true,
          isSaving: true,
          isStale: false,
        ),
        isFalse,
      );
    });

    test('blocked when the local copy is stale', () {
      expect(
        PosUploadFormController.computeCanEditStatus(
          canWritePerm: true,
          isSaving: false,
          isStale: true,
        ),
        isFalse,
      );
    });
  });
}
