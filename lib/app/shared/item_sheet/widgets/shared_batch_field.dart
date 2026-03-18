import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';

/// A reusable Batch No input field backed by any [ItemSheetControllerBase].
///
/// Renders:
///  - A text field with clear + submit actions
///  - Inline validation spinner while [isValidatingBatch] is true
///  - Error text from [batchError]
///  - Info tooltip icon when [batchInfoTooltip] is populated
///
/// Identical logic previously duplicated in DN, PR, SE item sheets.
class SharedBatchField extends StatelessWidget {
  final ItemSheetControllerBase c;
  final Color accentColor;
  final bool readOnly;

  const SharedBatchField({
    super.key,
    required this.c,
    required this.accentColor,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      final hasError   = c.batchError.value != null;
      final isValid    = c.isBatchValid.value;
      final validating = c.isValidatingBatch.value;

      final borderColor = hasError
          ? theme.colorScheme.error
          : isValid
              ? Colors.green
              : accentColor;

      return GlobalItemFormSheet.buildInputGroup(
        label: 'Batch No',
        color: borderColor,
        child: TextField(
          controller: c.batchController,
          readOnly: readOnly,
          style: theme.textTheme.bodyMedium,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) {
            if (v.isNotEmpty) c.validateBatch(v);
          },
          decoration: InputDecoration(
            hintText: 'Enter or scan batch number',
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            errorText: c.batchError.value,
            errorMaxLines: 2,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (validating)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (isValid)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.check_circle,
                        color: Colors.green, size: 20),
                  ),
                if (c.batchInfoTooltip.value != null)
                  Tooltip(
                    message: c.batchInfoTooltip.value!,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.info_outline,
                          color: accentColor, size: 20),
                    ),
                  ),
                if (c.batchController.text.isNotEmpty && !readOnly)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      c.batchController.clear();
                      c.resetBatch();
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
