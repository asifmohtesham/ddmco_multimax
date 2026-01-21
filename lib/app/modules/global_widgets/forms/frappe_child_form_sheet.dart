import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/fields/frappe_field_widget.dart';

/// Controller to manage the Child Form state
class FrappeChildFormController extends GetxController {
  final Map<String, dynamic> initialData;
  final Function(Map<String, dynamic>) onSave;

  // Renamed to avoid conflict with GetxController.onDelete lifecycle method
  final VoidCallback? onDeleteItemCallback;

  // Observable document state to trigger UI updates (e.g., visibility, filters)
  final RxMap<String, dynamic> doc = <String, dynamic>{}.obs;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  FrappeChildFormController({
    required this.initialData,
    required this.onSave,
    this.onDeleteItemCallback,
  });

  @override
  void onInit() {
    super.onInit();
    // Initialize doc with a copy of the data
    doc.assignAll(initialData);
  }

  void handleFieldChange(String fieldname, dynamic value) {
    doc[fieldname] = value;
    // doc is an RxMap, so UI listening to it (via Obx) will rebuild automatically
  }

  void submit() {
    if (formKey.currentState?.validate() ?? true) {
      onSave(Map<String, dynamic>.from(doc));
      Get.back(); // Close the sheet
    }
  }

  void deleteItem() {
    Get.defaultDialog(
      title: "Remove Item",
      middleText: "Are you sure you want to remove this row?",
      textConfirm: "Remove",
      confirmTextColor: Colors.white,
      buttonColor: Colors.red,
      onConfirm: () {
        if (onDeleteItemCallback != null) onDeleteItemCallback!();
        Get.back(); // Close Dialog
        Get.back(); // Close Sheet
      },
    );
  }
}

class FrappeChildFormSheet extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> fieldsMeta;
  final Map<String, dynamic> initialData;
  final Function(Map<String, dynamic>) onSave;
  final VoidCallback? onDelete;
  final bool isNew;
  final Map<String, dynamic> Function(String fieldname, Map<String, dynamic> doc)? onGetFilters;

  const FrappeChildFormSheet({
    super.key,
    required this.title,
    required this.fieldsMeta,
    required this.initialData,
    required this.onSave,
    this.onDelete,
    this.isNew = false,
    this.onGetFilters,
  });

  @override
  Widget build(BuildContext context) {
    // Create a unique tag to allow multiple forms using hashcode
    final String controllerTag = "child_form_${identityHashCode(this)}";

    // Initialize the controller
    final controller = Get.put(
      FrappeChildFormController(
        initialData: initialData,
        onSave: onSave,
        // Map the widget's onDelete to the controller's renamed callback
        onDeleteItemCallback: onDelete,
      ),
      tag: controllerTag,
    );

    // Filter structural fields
    final visibleFields = fieldsMeta.where((f) {
      final type = f['fieldtype'];
      return type != 'Column Break' && type != 'Section Break';
    }).toList();

    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: EdgeInsets.only(
          top: 16,
          left: 16,
          right: 16,
          // Handle keyboard overlap dynamic height
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        // Constrain height if needed, or let it grow within safe limits
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- Header ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Get.back(),
                ),
              ],
            ),
            const Divider(),

            // --- Form Fields ---
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: controller.formKey,
                  child: Obx(() {
                    // Wrap in Obx to rebuild fields when 'doc' changes
                    return Column(
                      children: visibleFields.map((field) {
                        return FrappeFieldWidget(
                          fieldMeta: field,
                          doc: controller.doc,
                          value: controller.doc[field['fieldname']],
                          onChanged: (val) => controller.handleFieldChange(field['fieldname'], val),
                          // Dynamically calculate filters based on current doc state
                          filters: onGetFilters != null
                              ? onGetFilters!(field['fieldname'], controller.doc)
                              : null,
                        );
                      }).toList(),
                    );
                  }),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // --- Action Buttons ---
            Row(
              children: [
                if (!isNew && onDelete != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: controller.deleteItem,
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text("Remove", style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: controller.submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(isNew ? "Add Row" : "Update Row"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}