// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/validated_field_widget.dart';

/// Thin wrapper around [ValidatedFieldWidget] that renders the rack input
/// in its validated / validating / idle states.
///
/// ## Why this file lives in `shared/item_sheet/widgets/`
///
/// [ValidatedRackField] was originally created inside the Stock Entry module
/// because SE was the first DocType to use the validated-rack pattern.
/// As part of the [RackFieldWithBrowseDelegate] refactor (Commit 1 of 10),
/// this widget was moved here so that **any DocType** — Delivery Note, Stock
/// Entry, or a future DocType — can reference the shared path without
/// carrying a dependency on the Stock Entry module tree.
///
/// The original Stock Entry path now re-exports this file and will be
/// removed in Commit 10 (cleanup).
///
/// ## Responsibility
///
/// Accepts **plain-primitive state** so the caller can wrap it in its own
/// `Obx` with precisely-scoped reactivity. This widget owns only:
/// - Rendering the three suffix states (idle, validating, valid)
/// - Surfacing a picker button when [onPickerTap] is provided
/// - Delegating the actual form-field structure to [ValidatedFieldWidget]
///
/// It never reads from a controller, never modifies state, and never owns
/// a [TextEditingController] lifecycle.
///
/// ## Picker integration
///
/// Pass [onPickerTap] to show a rack-picker icon button (shelves icon) in
/// the suffix area in **both** idle and valid states:
///
/// | State        | Suffix row                      |
/// |--------------|---------------------------------|
/// | Idle         | `[shelves icon]` + `[✓ button]` |
/// | Valid        | `[shelves icon]` + `[✏ button]` |
/// | Validating   | spinner only (no picker)        |
///
/// The full picker lifecycle — controller creation, data load, sheet
/// presentation — is owned by the **caller** (e.g. UniversalItemFormSheet).
/// This widget only renders the button and fires [onPickerTap] on tap.
///
/// ## Usage
///
/// ```dart
/// Obx(() => ValidatedRackField(
///   key:            const ValueKey('rack_dn'),
///   textController: controller.rackController,
///   isValid:        controller.isRackValid.value,
///   isValidating:   controller.isValidatingRack.value,
///   label:          'Enter or scan rack ID',
///   color:          Colors.blueGrey,
///   onReset:        controller.resetRack,
///   onValidate:     () => controller.validateRack(controller.rackController.text),
///   onSubmitted:    controller.validateRack,
///   onPickerTap:    () => controller.browseRacks(),  // optional
/// ))
/// ```
class ValidatedRackField extends StatelessWidget {
  /// The controller whose text reflects the currently entered rack ID.
  /// The widget never modifies the controller; it only reads `.text`
  /// for the [ValidatedFieldWidget] delegation.
  final TextEditingController textController;

  /// Whether the current rack value has been confirmed valid by the server.
  /// When `true`, the field becomes read-only and the edit (✏) suffix is shown.
  final bool isValid;

  /// Whether a validation round-trip is currently in flight.
  /// When `true`, a spinner replaces all suffix actions and [onPickerTap]
  /// is not rendered (to prevent concurrent requests).
  final bool isValidating;

  /// Inner hint/label text shown inside the field boundary.
  /// Typically `'Enter or scan rack ID'` or a DocType-specific variant.
  final String label;

  /// Accent colour used for the validate icon, valid check-circle, and
  /// field border highlights. Should match the parent DocType's theme colour.
  final Color color;

  /// Callback invoked when the user clears the field or taps the edit (✏)
  /// button. The caller is responsible for resetting all rack-related
  /// reactive state (isRackValid, isValidatingRack, rackError, etc.).
  final VoidCallback onReset;

  /// Callback invoked when the user taps the validate (✓) button.
  /// The caller drives the validation round-trip.
  final VoidCallback onValidate;

  /// Callback invoked when the user submits the text field via keyboard.
  /// Receives the current field value. Typically delegates to the same
  /// method as [onValidate] with the submitted string.
  final ValueChanged<String> onSubmitted;

  /// Optional callback fired when the picker (shelves) icon button is tapped.
  ///
  /// When non-null, a shelves icon button is injected into the suffix area
  /// in idle and valid states. When null, no picker button is rendered and
  /// the suffix falls back to the plain ✓ / ✏ behaviour.
  ///
  /// The caller owns the full picker flow — sheet presentation, data load,
  /// and result handling. This widget fires [onPickerTap] and does nothing
  /// further.
  final VoidCallback? onPickerTap;

  const ValidatedRackField({
    super.key,
    required this.textController,
    required this.isValid,
    required this.isValidating,
    required this.label,
    required this.color,
    required this.onReset,
    required this.onValidate,
    required this.onSubmitted,
    this.onPickerTap,
  });

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Builds the shelves icon button used in both idle and valid suffix rows.
  /// Extracted to avoid duplicating constraints / padding.
  Widget _pickerBtn() => IconButton(
        icon: const Icon(Icons.shelves),
        onPressed: onPickerTap,
        tooltip: 'Browse racks',
        iconSize: 20,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      );

  /// Builds the composite idle suffix: `[shelves icon]` + `[✓ button]`.
  ///
  /// Used instead of the plain ✓ button when [onPickerTap] is provided,
  /// so the user can either pick from the list or type + validate manually.
  Widget _idlePickerSuffix() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pickerBtn(),
          IconButton(
            icon: Icon(Icons.check, color: color),
            onPressed: onValidate,
            tooltip: 'Validate',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
        ],
      );

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValidatedFieldWidget(
      controller: textController,
      color: color,
      hintText: label,
      // Field becomes read-only once validated so accidental edits do not
      // silently invalidate a confirmed rack without the reset action.
      isReadOnly: isValid,
      isValid: isValid,
      isValidating: isValidating,
      onValidate: onValidate,
      onReset: onReset,
      onFieldSubmitted: onSubmitted,
      fontFamily: 'ShureTechMono',
      // Valid state: picker icon precedes the edit (✏) button.
      extraSuffixActions: onPickerTap != null ? [_pickerBtn()] : const [],
      // Idle state: composite row replaces the plain ✓ button when a
      // picker is available.
      idleSuffixWidget: onPickerTap != null ? _idlePickerSuffix() : null,
    );
  }
}
