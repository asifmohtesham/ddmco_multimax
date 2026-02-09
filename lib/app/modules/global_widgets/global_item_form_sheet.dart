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

  final Function onSubmit;
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

  final _isInternalLoading = false.obs;

  GlobalItemFormSheet({
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
    return Obx(() {
      final internalLoading = _isInternalLoading.value;
      final showLoading = isSaving || isLoading || internalLoading;
      final canPress = enabled && !showLoading;
      final colorScheme = Theme.of(context).colorScheme;

      return FilledButton(
        onPressed: canPress
            ? () async {
          if (formKey.currentState!.validate()) {
            FocusScope.of(context).unfocus();
            _isInternalLoading.value = true;
            await Future.delayed(const Duration(milliseconds: 500));
            try {
              var result = onSubmit();
              if (result is Future) {
                await result;
              }
              // REPLACED: Get.back();
              // FIX: Use native Navigator to pop the Sheet, ignoring the Snackbar overlay
              if (context.mounted) Navigator.of(context).pop();
            } catch (e) {
              print('Error submitting form: $e');
            } finally {
              _isInternalLoading.value = false;
            }
          }
        }
            : null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: showLoading
            ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            color: colorScheme.onPrimary,
            strokeWidth: 2.5,
          ),
        )
            : Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      );
    });
  }

  static Widget buildInputGroup({
    required String label,
    required Color color,
    required Widget child,
    Color? bgColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: bgColor ?? color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.1)),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _buildMetadataHeader(BuildContext context) {
    if (owner == null && creation == null && modified == null && modifiedBy == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final variantColor = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.labelSmall?.copyWith(color: variantColor);
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (owner != null || creation != null)
            Row(
              children: [
                if (owner != null) ...[
                  Icon(Icons.person_outline, size: 14, color: variantColor),
                  const SizedBox(width: 4),
                  Text(owner!, style: style?.copyWith(fontWeight: FontWeight.w600)),
                ],
                if (owner != null && creation != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: Text('•', style: style),
                  ),
                if (creation != null) ...[
                  Text(
                    'Created ${FormattingHelper.getRelativeTime(creation)}',
                    style: style,
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
                  Icon(Icons.edit_outlined, size: 14, color: variantColor),
                  const SizedBox(width: 4),
                  Text(modifiedBy!, style: style?.copyWith(fontWeight: FontWeight.w600)),
                ],
                if (modifiedBy != null && modified != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: Text('•', style: style),
                  ),
                if (modified != null) ...[
                  Text(
                    'Modified ${FormattingHelper.getRelativeTime(modified)}',
                    style: style,
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.viewPadding.top;

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: EdgeInsets.only(top: topPadding + 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28.0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Handle Bar
            Container(
              color: colorScheme.surface,
              width: double.infinity,
              padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
              alignment: Alignment.center,
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: Form(
                key: formKey,
                child: ListView(
                  controller: scrollController,
                  primary: false, // Important: We are in a nested context
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
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
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$itemCode${itemSubtext != null && itemSubtext!.isNotEmpty ? ' • $itemSubtext' : ''}',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontFamily: 'ShureTechMono',
                                    fontSize: 16,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                itemName,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: colorScheme.onSurface,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              _buildMetadataHeader(context),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Get.back(),
                          icon: const Icon(Icons.close),
                          style: IconButton.styleFrom(
                            backgroundColor: colorScheme.surfaceContainerHigh,
                            foregroundColor: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Divider(height: 1),
                    ),
                    ...customFields.map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 20.0),
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
                    const SizedBox(height: 32),
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
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.error,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove Item'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (onScan != null)
              BarcodeInputWidget(
                onScan: onScan!,
                controller: scanController,
                isLoading: isScanning,
                hintText: 'Scan Rack / Batch / Item',
              ),
          ],
        ),
      ),
    );
  }
}