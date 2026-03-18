import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';

/// A reusable Rack input field backed by any [ItemSheetControllerBase].
///
/// Renders:
///  - A text field that accepts rack scan or manual entry
///  - Inline validation spinner while [isValidatingRack] is true
///  - Green tick icon when [isRackValid] is true
///  - Per-rack stock tooltip via [rackStockTooltip]
///  - Error text from [rackError]
///
/// Identical logic previously duplicated in DN, PR, SE item sheets.
class SharedRackField extends StatelessWidget {
  final ItemSheetControllerBase c;
  final Color accentColor;
  final String label;
  final String hint;

  const SharedRackField({
    super.key,
    required this.c,
    required this.accentColor,
    this.label = 'Rack',
    this.hint  = 'Enter or scan rack ID',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      final hasError   = c.rackError.value != null;
      final isValid    = c.isRackValid.value;
      final validating = c.isValidatingRack.value;

      final borderColor = hasError
          ? theme.colorScheme.error
          : isValid
              ? Colors.green
              : accentColor;

      return GlobalItemFormSheet.buildInputGroup(
        label: label,
        color: borderColor,
        child: TextField(
          controller: c.rackController,
          focusNode: c.rackFocusNode,
          style: theme.textTheme.bodyMedium,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) {
            if (v.isNotEmpty) c.validateRack(v);
          },
          decoration: InputDecoration(
            hintText: hint,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            errorText: c.rackError.value,
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
                if (c.rackStockTooltip.value != null)
                  Tooltip(
                    message: c.rackStockTooltip.value!,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.inventory_2_outlined,
                          color: accentColor, size: 20),
                    ),
                  ),
                if (c.rackController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      c.rackController.clear();
                      c.resetRack();
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
