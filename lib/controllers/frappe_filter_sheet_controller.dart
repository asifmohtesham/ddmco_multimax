import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/frappe_filter.dart';
import '../controllers/frappe_list_controller.dart';

class FrappeFilterSheetController extends GetxController {
  late FrappeListController listController;

  // Local "Draft" State
  final RxList<FrappeFilter> localFilters = <FrappeFilter>[].obs;
  final RxBool showImagesOnly = false.obs;

  final List<String> availableOperators = ['like', '=', '!=', '>', '<', '>=', '<='];

  void initialize(FrappeListController controller, {bool initialShowImages = false}) {
    listController = controller;
    showImagesOnly.value = initialShowImages;

    // Clone existing filters to local state so we can cancel changes
    if (listController.activeFilters.isEmpty && listController.filterableFields.isNotEmpty) {
      addFilterRow();
    } else {
      localFilters.assignAll(
          listController.activeFilters.map((e) => e.clone())
      );
    }
  }

  void addFilterRow() {
    if (listController.filterableFields.isEmpty) return;
    // Default to the first available field configuration
    // (Or specific index if you prefer, e.g. Item Name)
    final defaultField = listController.filterableFields.length > 1
        ? listController.filterableFields[1]
        : listController.filterableFields[0];

    localFilters.add(FrappeFilter(
      fieldname: defaultField.fieldname,
      label: defaultField.label,
      config: defaultField,
    ));
  }

  void removeFilterRow(int index) {
    localFilters.removeAt(index);
  }

  void updateFilterField(int index, String fieldLabel) {
    final config = listController.filterableFields.firstWhere((e) => e.label == fieldLabel);

    // Replace with new filter of the selected type
    localFilters[index] = FrappeFilter(
      fieldname: config.fieldname,
      label: config.label,
      config: config,
      operator: localFilters[index].operator,
      value: '',
      // Preserve extras if needed, or reset
    );
  }

  void updateOperator(int index, String op) {
    final old = localFilters[index];
    old.operator = op;
    localFilters[index] = old;
    localFilters.refresh();
  }

  void updateValue(int index, String val) {
    localFilters[index].value = val;
  }

  void updateExtra(int index, String key, dynamic value) {
    localFilters[index].extras[key] = value;
    localFilters.refresh(); // Important for nested Obx updates
  }

  void toggleImagesOnly(bool val) {
    showImagesOnly.value = val;
  }

  void apply() {
    final valid = localFilters.where((f) => f.value.isNotEmpty).toList();
    listController.applyFilters(valid);
    // If specific controller has 'setImagesOnly', we handle it:
    if (listController.runtimeType.toString() == 'ItemController') {
      // We can use a callback or dynamic dispatch, but keeping it simple:
      // This implies ItemController must handle image filter logic or we pass it differently.
      // Ideally FrappeListController has a generic 'extras' too, but for now:
      try {
        (listController as dynamic).setImagesOnly(showImagesOnly.value);
      } catch (e) { /* ignore */ }
    }
    Get.back();
  }

  void clear() {
    localFilters.clear();
    showImagesOnly.value = false;
    listController.clearFilters();
    Get.back();
  }

  Future<List<String>> searchLink(String doctype, String query) {
    return listController.searchLink(doctype, query);
  }
}