import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/quantity_input_widget.dart';

class GlobalItemFormSheet extends StatelessWidget {
  final ScrollController? scrollController;
  final String title;
  final String itemCode;
  final String itemName;
  final String? itemSubtext; // e.g., variant info
  final List<Widget> customFields; // Specific fields like Batch, Rack, Rate

  // Quantity Props
  final TextEditingController qtyController;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final String? qtyInfoText;
  final bool isQtyReadOnly;

  // Actions
  final VoidCallback onSubmit;
  final VoidCallback? onDelete; // If null, delete button is hidden

  // State
  final bool isSaveEnabled;
  final bool isSaving;
  final bool isLoading;

  const GlobalItemFormSheet({
    super.key,
    required this.scrollController,
    required this.title,
    required this.itemCode,
    required this.itemName,
    this.itemSubtext,
    this.customFields = const [],
    required this.qtyController,
    required this.onIncrement,
    required this.onDecrement,
    this.qtyInfoText,
    this.isQtyReadOnly = false,
    required this.onSubmit,
    this.onDelete,
    this.isSaveEnabled = true,
    this.isSaving = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    // Local form key for validation
    final formKey = GlobalKey<FormState>();

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
        ),
        child: Form(
          key: formKey,
          child: ListView(
            controller: scrollController,
            shrinkWrap: true,
            children: [
              // --- Header ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$itemCode${itemSubtext != null && itemSubtext!.isNotEmpty ? ' • $itemSubtext' : ''}',
                          style: const TextStyle(color: Colors.grey, fontSize: 13, fontFamily: 'monospace'),
                        ),
                        Text(
                          itemName,
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Get.back(),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(backgroundColor: Colors.grey.shade100),
                  ),
                ],
              ),
              const Divider(height: 24),

              // --- Custom Fields (Batch, Rack, etc.) ---
              ...customFields.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: w,
              )),

              // --- Quantity Input ---
              QuantityInputWidget(
                controller: qtyController,
                onIncrement: onIncrement,
                onDecrement: onDecrement,
                isReadOnly: isQtyReadOnly,
                label: 'Quantity',
                infoText: qtyInfoText,
              ),

              const SizedBox(height: 24),

              // --- Action Buttons ---
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (isSaveEnabled && !isSaving && !isLoading)
                      ? () {
                    if (formKey.currentState!.validate()) {
                      onSubmit();
                    }
                  }
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: isSaveEnabled ? Theme.of(context).primaryColor : Colors.grey.shade300,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: isSaveEnabled ? 2 : 0,
                  ),
                  child: isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(
                    title, // "Add Item" or "Update Item" usually passed as title
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              // --- Delete Button ---
              if (onDelete != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () {
                      Get.back();
                      onDelete!();
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Remove Item', style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],

              SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
            ],
          ),
        ),
      ),
    );
  }

  /// Helper method for consistent input styling across screens
  static Widget buildInputGroup({required String label, required Color color, required Widget child, Color? bgColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
          child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        Container(
          decoration: BoxDecoration(
            color: bgColor ?? color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: child,
        ),
      ],
    );
  }
}