import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';

/// A reusable rack input field driven by [ItemSheetControllerBase].
///
/// Renders identically for Delivery Note, Purchase Receipt, and Stock Entry.
/// Pass [isTarget: true] for the "To Rack" field (SE Material Transfer).
///
/// Usage:
/// ```dart
/// // Source rack (all DocTypes)
/// SharedRackField(controller: c)
///
/// // Target rack (Stock Entry Material Transfer only)
/// SharedRackField(controller: c, isTarget: true)
/// ```
class SharedRackField extends StatelessWidget {
  const SharedRackField({
    super.key,
    required this.controller,
    this.isTarget = false,
  });

  final ItemSheetControllerBase controller;

  /// When true, renders as "To Rack" using the tertiary colour palette.
  /// The base class exposes a single rackController; SE Transfer subclass
  /// should override with a dedicated targetRackController if needed.
  final bool isTarget;

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Colour convention: source = tertiary  |  target = secondary
    final fieldColor = isTarget ? colorScheme.secondary : colorScheme.tertiary;
    final label      = isTarget ? 'To Rack'             : 'From Rack';
    final hint       = isTarget ? 'Scan target rack'    : 'Scan or enter rack';

    return Obx(() {
      final isValid      = controller.isRackValid.value;
      final isValidating = controller.isValidatingRack.value;
      final errorText    = controller.rackError.value;
      final tooltip      = controller.rackStockTooltip.value;

      return GlobalItemFormSheet.buildInputGroup(
        label: label,
        color: fieldColor,
        child: Column(
          children: [
            TextFormField(
              controller: controller.rackController,
              focusNode:  isTarget ? null : controller.rackFocusNode,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                suffixIcon: _RackSuffix(
                  isValid:      isValid,
                  isValidating: isValidating,
                  tooltipText:  tooltip,
                  onClear: controller.rackController.text.isNotEmpty
                      ? () {
                          controller.rackController.clear();
                          controller.resetRack();
                        }
                      : null,
                ),
              ),
              onFieldSubmitted: (v) => controller.validateRack(v.trim()),
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

class _RackSuffix extends StatelessWidget {
  const _RackSuffix({
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
      final icon = Icon(Icons.warehouse_outlined,
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
        tooltip:  'Clear rack',
      );
    }

    return const SizedBox.shrink();
  }
}
