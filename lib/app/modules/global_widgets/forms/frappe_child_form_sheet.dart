import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/fields/frappe_field_widget.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';

class FrappeChildFormSheet extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> fieldsMeta;
  final Map<String, dynamic> initialData;
  final Function(Map<String, dynamic>) onSave;
  final VoidCallback? onDelete;
  final bool isNew;

  const FrappeChildFormSheet({
    super.key,
    required this.title,
    required this.fieldsMeta,
    required this.initialData,
    required this.onSave,
    this.onDelete,
    this.isNew = false,
  });

  @override
  State<FrappeChildFormSheet> createState() => _FrappeChildFormSheetState();
}

class _FrappeChildFormSheetState extends State<FrappeChildFormSheet> {
  late Map<String, dynamic> _formData;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Create a mutable copy of the data
    _formData = Map<String, dynamic>.from(widget.initialData);
  }

  void _handleFieldChange(String fieldname, dynamic value) {
    setState(() {
      _formData[fieldname] = value;
    });
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? true) {
      widget.onSave(_formData);
      Get.back();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter visible fields (exclude hidden or structural fields not needed in form)
    // Note: FrappeFieldWidget handles 'hidden: 1', but we filter structural items here if needed.
    final visibleFields = widget.fieldsMeta.where((f) {
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
          // Handle keyboard overlap
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- Header ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.title,
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
            const Divider(),

            // --- Form Fields ---
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: visibleFields.map((field) {
                      return FrappeFieldWidget(
                        fieldMeta: field,
                        doc: _formData,
                        // Pass current row state as doc for visibility logic
                        value: _formData[field['fieldname']],
                        onChanged: (val) =>
                            _handleFieldChange(field['fieldname'], val),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // --- Action Buttons ---
            Row(
              children: [
                if (!widget.isNew && widget.onDelete != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // Confirm Delete
                        Get.defaultDialog(
                          title: "Remove Item",
                          middleText: "Are you sure you want to remove this row?",
                          textConfirm: "Remove",
                          confirmTextColor: Colors.white,
                          buttonColor: Colors.red,
                          onConfirm: () {
                            widget.onDelete!();
                            Get.back(); // Close Dialog
                            Get.back(); // Close Sheet
                          },
                        );
                      },
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text(
                        "Remove",
                        style: TextStyle(color: Colors.red),
                      ),
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
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(widget.isNew ? "Add Row" : "Update Row"),
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
