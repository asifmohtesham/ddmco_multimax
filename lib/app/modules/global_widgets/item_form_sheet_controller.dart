import 'package:get/get.dart';

/// Lightweight GetxController scoped to a single [GlobalItemFormSheet] instance.
///
/// Registered with [Get.put] using a unique [tag] when the sheet opens and
/// deleted automatically via [onClose] when the sheet is removed from the tree,
/// so there is zero state leakage between sequential sheet opens.
class ItemFormSheetController extends GetxController {
  /// True while the manual submit button tap is in-progress.
  /// Drives the save-button spinner independently of the parent
  /// DocType controller's [isSaving] / [isLoading] flags.
  final isSubmitting = false.obs;
}
