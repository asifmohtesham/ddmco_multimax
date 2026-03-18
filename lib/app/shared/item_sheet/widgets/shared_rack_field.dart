import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';

/// A reusable Rack input field backed by any [ItemSheetControllerBase].
///
/// ## Modes
///
/// ### `editMode: false` (default — SE style)
/// Borderless [TextField], green check-circle when valid, clear + validate
/// icons, optional per-rack stock tooltip.
///
/// ### `editMode: true` (PR / DN style)
/// [OutlineInputBorder] [TextFormField], readOnly-when-valid, spinner →
/// Edit-btn → forward-arrow suffix pattern. `rackError` rendered as
/// `helperText`. Replaces the inline Obx rack field in PurchaseReceiptItemFormSheet.
class SharedRackField extends StatelessWidget {
  final ItemSheetControllerBase c;
  final Color  accentColor;
  final String label;
  final String hint;
  final bool   editMode;

  const SharedRackField({
    super.key,
    required this.c,
    required this.accentColor,
    this.label    = 'Rack',
    this.hint     = 'Enter or scan rack ID',
    this.editMode = false,
  });

  Color get _validFill {
    if (accentColor is MaterialColor) {
      return (accentColor as MaterialColor).shade50;
    }
    return accentColor.withOpacity(0.08);
  }

  Color get _validBorder {
    if (accentColor is MaterialColor) {
      return (accentColor as MaterialColor).shade200;
    }
    return accentColor.withOpacity(0.5);
  }

  @override
  Widget build(BuildContext context) {
    return editMode ? _EditModeRack(this) : _SimpleRack(this);
  }
}

// ── Simple (borderless) mode ─────────────────────────────────────────────────
class _SimpleRack extends StatelessWidget {
  final SharedRackField w;
  const _SimpleRack(this.w);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c     = w.c;

    return Obx(() {
      final hasError   = c.rackError.value != null;
      final isValid    = c.isRackValid.value;
      final validating = c.isValidatingRack.value;

      final borderColor = hasError
          ? theme.colorScheme.error
          : isValid
              ? Colors.green
              : w.accentColor;

      return GlobalItemFormSheet.buildInputGroup(
        label: w.label,
        color: borderColor,
        child: TextField(
          controller: c.rackController,
          focusNode:  c.rackFocusNode,
          style:      theme.textTheme.bodyMedium,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) {
            if (v.isNotEmpty) c.validateRack(v);
          },
          decoration: InputDecoration(
            hintText:    w.hint,
            border:      InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            errorText:   c.rackError.value,
            errorMaxLines: 2,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (validating)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 16, height: 16,
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
                          color: w.accentColor, size: 20),
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

// ── Edit-mode (OutlineInputBorder, readOnly-when-valid) ──────────────────────
// Replaces the inline Obx rack field in PurchaseReceiptItemFormSheet.
class _EditModeRack extends StatelessWidget {
  final SharedRackField w;
  const _EditModeRack(this.w);

  @override
  Widget build(BuildContext context) {
    final c = w.c;

    return Obx(() {
      final isValid    = c.isRackValid.value;
      final validating = c.isValidatingRack.value;
      final hasError   = c.rackError.value != null;

      return GlobalItemFormSheet.buildInputGroup(
        label:   w.label,
        color:   w.accentColor,
        bgColor: isValid ? w._validFill : null,
        child: TextFormField(
          key:        const ValueKey('shared_rack_edit'),
          controller: c.rackController,
          readOnly:   isValid,
          autofocus:  false,
          decoration: InputDecoration(
            hintText: w.hint,
            helperText: c.rackError.value,
            helperStyle: TextStyle(
              color:      hasError ? Colors.red : Colors.grey,
              fontWeight: hasError ? FontWeight.bold : FontWeight.normal,
            ),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                  color: hasError ? Colors.red : w._validBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: w.accentColor, width: 2),
            ),
            filled:    true,
            fillColor: isValid ? w._validFill : Colors.white,
            suffixIcon: _suffixIcon(c, isValid, validating),
          ),
          onChanged: isValid
              ? null
              : (_) {
                  if (c.isRackValid.value) c.isRackValid.value = false;
                  c.validateSheet();
                },
          onFieldSubmitted: (val) => c.validateRack(val),
        ),
      );
    });
  }

  Widget _suffixIcon(
    ItemSheetControllerBase c,
    bool isValid,
    bool validating,
  ) {
    if (validating) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: w.accentColor),
        ),
      );
    }
    if (isValid) {
      return IconButton(
        icon:    Icon(Icons.edit, color: w.accentColor, size: 20),
        onPressed: c.resetRack,
        tooltip: 'Edit Rack',
      );
    }
    return IconButton(
      icon:      const Icon(Icons.arrow_forward),
      onPressed: () => c.validateRack(c.rackController.text),
      tooltip:   'Validate',
      color:     Colors.grey,
    );
  }
}
