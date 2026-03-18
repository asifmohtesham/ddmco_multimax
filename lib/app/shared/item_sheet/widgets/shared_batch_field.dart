import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';

/// A reusable batch-number input field driven by [ItemSheetControllerBase].
///
/// Renders identically for Delivery Note, Purchase Receipt, and Stock Entry.
/// DocType-specific behaviour (validation, focus-next) is delegated to
/// [controller.validateBatch] and [controller.requestRackFocus], both
/// defined on the base class.
///
/// Usage:
/// ```dart
/// SharedBatchField(controller: c)
/// ```
class SharedBatchField extends StatelessWidget {
  const SharedBatchField({super.key, required this.controller});

  final ItemSheetControllerBase controller;

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fieldColor  = colorScheme.secondary;

    return Obx(() {
      final isValid      = controller.isBatchValid.value;
      final isValidating = controller.isValidatingBatch.value;
      final errorText    = controller.batchError.value;
      final tooltipText  = controller.batchInfoTooltip.value;

      return GlobalItemFormSheet.buildInputGroup(
        label: 'Batch No.',
        color: fieldColor,
        child: Column(
          children: [
            TextFormField(
              controller: controller.batchController,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Enter or scan batch',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                suffixIcon: _BatchSuffix(
                  isValid:      isValid,
                  isValidating: isValidating,
                  tooltipText:  tooltipText,
                  onClear: controller.batchController.text.isNotEmpty
                      ? () {
                          controller.batchController.clear();
                          controller.resetBatch();
                        }
                      : null,
                ),
              ),
              onFieldSubmitted: (v) => controller.validateBatch(v.trim()),
            ),
            if (errorText != null)
              Padding(
                padding: const EdgeInsets.only(
                    left: 16, right: 16, bottom: 10),
                child: Text(
                  errorText,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: colorScheme.error),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _BatchSuffix extends StatelessWidget {
  const _BatchSuffix({
    required this.isValid,
    required this.isValidating,
    this.tooltipText,
    this.onClear,
  });

  final bool          isValid;
  final bool          isValidating;
  final String?       tooltipText;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (isValidating) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (isValid) {
      final icon = Icon(Icons.check_circle_outline,
          color: colorScheme.primary, size: 20);
      return tooltipText != null
          ? Tooltip(message: tooltipText!, child: icon)
          : icon;
    }

    if (onClear != null) {
      return IconButton(
        icon:     const Icon(Icons.clear, size: 20),
        onPressed: onClear,
        color:    colorScheme.onSurfaceVariant,
        tooltip:  'Clear batch',
      );
    }

    return const SizedBox.shrink();
  }
}
