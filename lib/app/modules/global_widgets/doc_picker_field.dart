import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// A tappable `label / value` picker field for DocType form screens — the
/// standard affordance for a value chosen via a picker (bottom sheet, dialog,
/// date picker) rather than typed.
///
/// Extracted from the Material Request form's private `_buildCompactField`.
/// Pair it with [DocSectionCard]: the field's `colorScheme.surface` fill
/// reads as an input well against the card's `surfaceContainerLow`.
///
/// States (all inks from [AppScheme] / `ColorScheme` — never hardcoded):
/// * **Editable** (`onTap != null`): surface fill, strong border, trailing
///   affordance icon, value in `onSurface`.
/// * **Read-only** (`onTap == null`): subtle fill, soft border, no trailing
///   icon, value in `textMuted`.
/// * **Empty** (`value` null/empty): shows [placeholder] in `textMuted`.
class DocPickerField extends StatelessWidget {
  const DocPickerField({
    super.key,
    required this.label,
    required this.icon,
    this.value,
    this.placeholder = 'Select',
    this.helperText,
    this.trailingIcon = Icons.arrow_drop_down,
    this.onTap,
  });

  /// Small field label rendered above the value (e.g. "Request Type").
  final String label;

  /// Leading glyph identifying the field.
  final IconData icon;

  /// Current value; null or empty renders [placeholder] instead.
  final String? value;

  /// Shown in `textMuted` when [value] is null or empty.
  final String placeholder;

  /// Optional caption under the value (e.g. what the selected type does).
  final String? helperText;

  /// Trailing affordance when editable. `arrow_drop_down` for inline pickers,
  /// `chevron_right` for full-screen/sheet pickers, `edit_calendar_outlined`
  /// for dates.
  final IconData trailingIcon;

  /// Null renders the read-only state.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final cs = Theme.of(context).colorScheme;
    final bool editable = onTap != null;
    final bool hasValue = value != null && value!.isNotEmpty;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: editable ? cs.surface : scheme.subtle,
        border: Border.all(
            color: editable ? scheme.borderStrong : scheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon,
              size: 16,
              color: editable ? scheme.textMuted : scheme.textSubtle),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 10, color: scheme.textMuted)),
                Text(
                  hasValue ? value! : placeholder,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: hasValue && editable
                        ? cs.onSurface
                        : scheme.textMuted,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (helperText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    helperText!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.textMuted),
                  ),
                ],
              ],
            ),
          ),
          if (editable) ...[
            const SizedBox(width: 8),
            Icon(trailingIcon, size: 18, color: scheme.textSubtle),
          ],
        ],
      ),
    );

    if (!editable) return content;
    return InkWell(
        borderRadius: BorderRadius.circular(12), onTap: onTap, child: content);
  }
}
