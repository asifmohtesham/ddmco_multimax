import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';

/// Mixin to handle Frappe TimestampMismatchError (Optimistic Locking)
mixin OptimisticLockingMixin on GetxController {

  /// Flag to indicate the local document is out of sync with the server
  var isStale = false.obs;

  /// MUST be implemented by the Controller.
  /// Should refetch the document from the API and update the local state.
  Future<void> reloadDocument();

  /// Call this at the start of any scanning or editing method.
  /// Returns [true] if the action should be BLOCKED.
  bool checkStaleAndBlock() {
    if (isStale.value) {
      _showConflictDialog();
      return true;
    }
    return false;
  }

  /// Checks if the error is a Version Conflict.
  /// If YES, it sets [isStale] to true and shows the dialog.
  /// Returns [true] if the error was handled as a conflict.
  bool handleVersionConflict(dynamic error) {
    if (error is DioException) {
      bool isConflict = false;

      // Check Status Code (409 Conflict)
      if (error.response?.statusCode == 409) {
        isConflict = true;
      }
      // Check Exception Message from Frappe
      else if (error.response?.data is Map) {
        final exception = error.response!.data['exception']?.toString() ?? '';
        if (exception.contains('TimestampMismatchError')) {
          isConflict = true;
        }
      }

      if (isConflict) {
        isStale.value = true;
        _showConflictDialog();
        return true;
      }
    }
    return false;
  }

  void _showConflictDialog() {
    GlobalDialog.showVersionConflict(onReload: () async {
      await reloadDocument();
      isStale.value = false;
    });
  }
}