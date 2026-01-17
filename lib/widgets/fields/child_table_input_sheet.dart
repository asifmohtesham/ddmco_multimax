import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/child_form_controller.dart';
import '../../widgets/generic_frappe_form.dart';
import '../../widgets/frappe_button.dart';
import '../../theme/frappe_theme.dart';

class ChildTableInputSheet extends StatelessWidget {
  final String childDoctype;
  final Map<String, dynamic>? initialData;
  final Function(Map<String, dynamic>) onSave;
  final VoidCallback? onDelete;

  const ChildTableInputSheet({
    super.key,
    required this.childDoctype,
    required this.onSave,
    this.initialData,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Unique tag to prevent controller conflict if multiple tables exist
    final controllerTag =
        "child_${childDoctype}_${DateTime.now().millisecondsSinceEpoch}";

    final controller = Get.put(
      ChildFormController(
        childDoctype: childDoctype,
        onSaveCallback: onSave,
        onDeleteCallback: onDelete,
        initialData: initialData,
      ),
      tag: controllerTag,
    );

    return Container(
      color: Colors.white,
      height: Get.height * 0.9, // Almost full screen
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: FrappeTheme.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  initialData == null
                      ? "Add $childDoctype"
                      : "Edit $childDoctype",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Get.back(),
                ),
              ],
            ),
          ),

          // Form Body
          Expanded(
            child: FrappeFormLayout(
              // Reusing layout for formKey support
              title: "", // Handled by custom header above
              formKey: controller.formKey,
              body: GenericFrappeForm(controller: controller),
            ),
          ),

          // Footer Actions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              children: [
                if (onDelete != null) ...[
                  Expanded(
                    child: FrappeButton(
                      label: "Delete",
                      icon: Icons.delete_outline,
                      style: FrappeButtonStyle.danger,
                      onPressed: controller.delete,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: FrappeButton(
                    label: "Done",
                    icon: Icons.check,
                    style: FrappeButtonStyle.primary,
                    onPressed: controller.save,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Minimal wrapper for GenericForm to work inside sheet without Scaffold
class FrappeFormLayout extends StatelessWidget {
  final Widget body;
  final String title;
  final GlobalKey<FormState>? formKey;

  const FrappeFormLayout({
    super.key,
    required this.body,
    required this.title,
    this.formKey,
  });

  @override
  Widget build(BuildContext context) {
    if (formKey != null) {
      return Form(key: formKey, child: body);
    }
    return body;
  }
}
