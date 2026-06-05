import 'package:flutter/material.dart';

/// A read-only, tappable text field that renders a DocType Link (reference)
/// field and delegates selection to a caller-supplied picker.
///
/// Wraps the repeated `GestureDetector > AbsorbPointer > TextFormField`
/// pattern so every link field in every form screen looks and behaves
/// identically without duplication.
///
/// The widget is intentionally free of Rx / GetX. Callers own the
/// [TextEditingController] and all picker bottom-sheet logic; this widget
/// only handles rendering.
///
/// ## States
///
/// | Condition            | Suffix icon         | Border                      |
/// |----------------------|---------------------|-----------------------------|
/// | Idle (no value)      | `arrow_drop_down`   | theme default               |
/// | Has value            | `arrow_drop_down`   | theme default               |
/// | Error (`errorText`)  | `arrow_drop_down`   | `colorScheme.error`         |
/// | Locked (`isReadOnly`)| *(none)*            | theme default, no tap       |
/// | Clearable + value    | `close` + dropdown  | theme default               |
///
/// ## Usage
///
/// ```dart
/// LinkFieldWidget(
///   controller: controller.itemController,
///   labelText: 'Item Code',
///   hintText: 'Select Item',
///   prefixIcon: Icons.inventory_2_outlined,
///   isRequired: true,
///   onTap: () => _showItemPicker(context),
/// )
/// ```
///
/// With validation error (bound inside `Obx`):
///
/// ```dart
/// Obx(() => LinkFieldWidget(
///   controller: controller.itemController,
///   labelText: 'Item Code',
///   hintText: 'Select Item',
///   prefixIcon: Icons.inventory_2_outlined,
///   isRequired: true,
///   onTap: () => _showItemPicker(context),
///   errorText: controller.itemError.value.isEmpty
///       ? null
///       : controller.itemError.value,
/// ))
/// ```
class LinkFieldWidget extends StatelessWidget {
  /// The controller whose text is displayed in the field.
  final TextEditingController controller;

  /// Label shown above the field (floating label).
  ///
  /// When [isRequired] is `true`, ` *` is automatically appended.
  final String labelText;

  /// Placeholder text shown when the field is empty.
  final String hintText;

  /// Leading icon inside the field.
  final IconData prefixIcon;

  /// Called when the user taps the field or the dropdown arrow.
  ///
  /// Pass `null` to make the field non-interactive (same as [isReadOnly]).
  final VoidCallback? onTap;

  /// When `true` the field cannot be tapped and no gesture is registered.
  ///
  /// Typically set to `true` in edit-mode screens where the linked
  /// document cannot be changed after creation.
  final bool isReadOnly;

  /// Appends ` *` to [labelText] and marks the field as required.
  ///
  /// Does not perform any validation itself — use [errorText] to
  /// display validation feedback.
  final bool isRequired;

  /// When non-null, shown below the field in [ColorScheme.error] colour.
  ///
  /// Pass an empty string or `null` to hide the error.
  final String? errorText;

  /// When non-null and the field has a value, a clear (`×`) icon button
  /// is prepended to the dropdown suffix so the user can deselect.
  ///
  /// Only shown when [controller.text] is non-empty and [isReadOnly]
  /// is `false`.
  final VoidCallback? onClear;

  const LinkFieldWidget({
    super.key,
    required this.controller,
    required this.labelText,
    required this.hintText,
    required this.prefixIcon,
    required this.onTap,
    this.isReadOnly = false,
    this.isRequired = false,
    this.errorText,
    this.onClear,
  });

  bool get _hasError => errorText != null && errorText!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveLabel = isRequired ? '$labelText *' : labelText;
    final interactive = !isReadOnly && onTap != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: interactive ? onTap : null,
          // AbsorbPointer prevents the inner TextFormField from consuming
          // the tap event so the GestureDetector above always fires first.
          child: AbsorbPointer(
            child: TextFormField(
              controller: controller,
              readOnly: true,
              decoration: InputDecoration(
                labelText: effectiveLabel,
                hintText: hintText,
                border: const OutlineInputBorder(),
                // Error state: swap border colour to colorScheme.error
                enabledBorder: _hasError
                    ? OutlineInputBorder(
                        borderSide: BorderSide(
                          color: colorScheme.error,
                        ),
                      )
                    : null,
                focusedBorder: _hasError
                    ? OutlineInputBorder(
                        borderSide: BorderSide(
                          color: colorScheme.error,
                          width: 2,
                        ),
                      )
                    : null,
                prefixIcon: Icon(prefixIcon),
                suffixIcon: _buildSuffix(context),
              ),
            ),
          ),
        ),
        // ── Inline error text ───────────────────────────────────────────────
        if (_hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(
              errorText!,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  Widget? _buildSuffix(BuildContext context) {
    // In read-only mode show no suffix — field is informational only.
    if (isReadOnly) return null;

    final hasClear = onClear != null && controller.text.isNotEmpty;

    if (hasClear) {
      // Clearable: [×][▼]
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Clear',
            onPressed: onClear,
          ),
          const Icon(Icons.arrow_drop_down),
          const SizedBox(width: 4),
        ],
      );
    }

    // Default: [▼]
    return const Icon(Icons.arrow_drop_down);
  }
}
