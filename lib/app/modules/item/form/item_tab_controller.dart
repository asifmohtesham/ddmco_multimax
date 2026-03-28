import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';

/// Owns the [TabController] for [ItemFormScreen].
///
/// Separated from [ItemFormController] so the ticker lifecycle
/// ([GetSingleTickerProviderStateMixin]) is fully isolated from the
/// data layer. This prevents the `_dependents.isEmpty` assertion that
/// fires when [GetTickerProviderStateMixin] is disposed after a
/// bottom-sheet overlay has already been deactivated from the widget tree.
///
/// Usage:
///   - Register with [Get.put] **before** opening the bottom sheet.
///   - Delete with [Get.delete] inside the `.then()` callback of
///     [Get.bottomSheet], **before** deleting [ItemFormController].
class ItemTabController extends GetxController
    with GetSingleTickerProviderStateMixin {
  late final TabController tabController;

  @override
  void onInit() {
    super.onInit();
    tabController = TabController(length: 4, vsync: this);
    tabController.addListener(() {
      // indexIsChanging is true during the animation; we only want the
      // settled index after the user has fully committed to a tab.
      if (!tabController.indexIsChanging) {
        Get.find<ItemFormController>().onTabChanged(tabController.index);
      }
    });
  }

  @override
  void onClose() {
    // dispose() removes all listeners internally before releasing the ticker.
    tabController.dispose();
    super.onClose();
  }
}
