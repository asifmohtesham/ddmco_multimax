import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/quantity_input_widget.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';

class GlobalItemFormSheet extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final ScrollController? scrollController;
  final String title;
  final String itemCode;
  final String itemName;
  final String? itemSubtext;
  final List<Widget> customFields;

  final TextEditingController qtyController;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final String? qtyInfoText;
  final bool isQtyReadOnly;

  final VoidCallback onSubmit;
  final VoidCallback? onDelete;

  // State
  final bool isSaveEnabled;
  final RxBool? isSaveEnabledRx;
  final bool isSaving;
  final bool isLoading;

  // Metadata Fields
  final String? owner;
  final String? creation;
  final String? modified;
  final String? modifiedBy;

  // Scan Integration
  final Function(String)? onScan;
  final TextEditingController? scanController;
  final bool isScanning;

  const GlobalItemFormSheet({
    super.key,
    required this.formKey,
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
    this.isSaveEnabledRx,
    this.isSaving = false,
    this.isLoading = false,
    this.owner,
    this.creation,
    this.modified,
    this.modifiedBy,
    this.onScan,
    this.scanController,
    this.isScanning = false,
  });

  Widget _buildSaveButton(BuildContext context, bool enabled) {
    final bool canPress = enabled && !isSaving && !isLoading;

    return ElevatedButton(
      onPressed: canPress
          ? () {
        if (formKey.currentState!.validate()) {
          onSubmit();
        }
      }
          : null,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: enabled ? Theme.of(context).primaryColor : Colors.grey.shade300,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: enabled ? 2 : 0,
      ),
      child: isSaving
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

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

  // ... (Metadata Header Builder unchanged) ...
  Widget _buildMetadataHeader(BuildContext context) {
    if (owner == null && creation == null && modified == null && modifiedBy == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (owner != null || creation != null)
            Row(
              children: [
                if (owner != null) ...[
                  const Icon(Icons.person_outline, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    owner!,
                    style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
                  ),
                ],
                if (owner != null && creation != null)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.0),
                    child: Text('•', style: TextStyle(color: Colors.grey, fontSize: 10)),
                  ),
                if (creation != null) ...[
                  const Icon(Icons.access_time, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Created ${FormattingHelper.getRelativeTime(creation)}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ],
            ),
          if ((modified != null || modifiedBy != null) &&
              (modified != creation || modifiedBy != owner)) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (modifiedBy != null) ...[
                  const Icon(Icons.edit_outlined, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    modifiedBy!,
                    style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
                  ),
                ],
                if (modifiedBy != null && modified != null)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.0),
                    child: Text('•', style: TextStyle(color: Colors.grey, fontSize: 10)),
                  ),
                if (modified != null) ...[
                  const Icon(Icons.history, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Modified ${FormattingHelper.getRelativeTime(modified)}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
        ),
        child: Column(
          children: [
            Expanded(
              child: Form(
                key: formKey,
                child: ListView(
                  controller: scrollController,
                  shrinkWrap: true,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                              _buildMetadataHeader(context),
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

                    ...customFields.map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: w,
                    )),

                    QuantityInputWidget(
                      controller: qtyController,
                      onIncrement: onIncrement,
                      onDecrement: onDecrement,
                      isReadOnly: isQtyReadOnly,
                      label: 'Quantity',
                      infoText: qtyInfoText,
                    ),

                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: isSaveEnabledRx != null
                          ? Obx(() => _buildSaveButton(context, isSaveEnabledRx!.value))
                          : _buildSaveButton(context, isSaveEnabled),
                    ),

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
                  ],
                ),
              ),
            ),

            // Standardised Global Scanner in Sheet
            if (onScan != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: BarcodeInputWidget(
                  onScan: onScan!,
                  controller: scanController,
                  isLoading: isScanning,
                  hintText: 'Scan Rack / Batch / Item',
                  isEmbedded: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}