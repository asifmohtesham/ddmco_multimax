import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'frappe_form_controller.dart';
import '../theme/frappe_theme.dart';
import '../models/frappe_form_layout_model.dart';

class ChildFormController extends FrappeFormController {
  final Function(Map<String, dynamic>) onSaveCallback;
  final VoidCallback? onDeleteCallback;

  ChildFormController({
    required String childDoctype,
    required this.onSaveCallback,
    this.onDeleteCallback,
    Map<String, dynamic>? initialData,
  }) : super(doctype: childDoctype) {
    if (initialData != null) {
      data.assignAll(initialData);
    } else {
      data['doctype'] = childDoctype;
      data['__islocal'] = 1;
    }
  }

  @override
  Future<void> save() async {
    // 1. UI Form Validation
    if (formKey.currentState != null && !formKey.currentState!.validate()) {
      Get.snackbar(
        "Validation Error",
        "Please check the form for errors.",
        backgroundColor: FrappeTheme.danger.withValues(alpha: 0.1),
        colorText: FrappeTheme.danger,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    // 2. Metadata Validation (using layoutTabs -> sections -> fields)
    // We access the parsed layout to find required fields
    for (var tab in layoutTabs) {
      for (var section in tab.sections) {
        for (var field in section.fields) {
          if (field.reqd && !field.readOnly) {
            final val = data[field.fieldname];
            if (val == null || (val is String && val.trim().isEmpty) || (val is List && val.isEmpty)) {
              Get.snackbar(
                "Missing Field",
                "${field.label} is required.",
                backgroundColor: FrappeTheme.warning.withValues(alpha: 0.1),
                colorText: FrappeTheme.warning,
                snackPosition: SnackPosition.BOTTOM,
              );
              return;
            }
          }
        }
      }
    }

    // 3. Success -> Callback -> Close
    onSaveCallback(Map<String, dynamic>.from(data));
    Get.back();
  }

  void delete() {
    if (onDeleteCallback != null) {
      onDeleteCallback!();
      Get.back();
    }
  }
}