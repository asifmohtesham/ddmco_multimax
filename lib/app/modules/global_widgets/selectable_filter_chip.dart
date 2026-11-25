import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'list_header_accessibility.dart';

/// A native choice with shared selection and focus styling for in-screen
/// filters such as item status, document scope and warehouse.
class SelectableFilterChip extends StatelessWidget {
  const SelectableFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.count,
    this.dotColor,
    this.focusNode,
    this.semanticLabel,
  });

  final String label;

  /// When non-null, rendered as `label (count)`.
  final int? count;

  /// Leading status dot that remains visible with the selection check.
  final Color? dotColor;

  final bool selected;
  final ValueChanged<bool>? onSelected;
  final FocusNode? focusNode;

  /// The full spoken option name when the caller uses a shorter visual name.
  final String? semanticLabel;

  String get caption => _captionFor(label);

  String _captionFor(String name) => count == null ? name : '$name ($count)';

  @override
  Widget build(BuildContext context) {
    final palette = HeaderPalette.of(context);
    final enabled = onSelected != null;
    final fill = WidgetStatePropertyAll(palette.choiceFill(selected, enabled));
    final ink = palette.choiceInk(selected, enabled);
    final style = choiceLabelStyle(context).copyWith(color: ink);
    const padding = EdgeInsets.all(8);
    const labelPadding = EdgeInsets.symmetric(horizontal: 8);
    const density = VisualDensity.standard;
    const tapTarget = MaterialTapTargetSize.padded;
    final name = semanticLabel;
    final spokenCaption = name == null ? null : _captionFor(name);
    final text = Text(
      caption,
      semanticsLabel: spokenCaption,
      maxLines: 1,
      softWrap: false,
    );
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 16),
      child: dotColor == null
          ? text
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: ink),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                text,
              ],
            ),
    );
    final Widget chip;
    if (enabled) {
      chip = ChoiceChip(
        label: body,
        labelStyle: style,
        selected: selected,
        onSelected: onSelected,
        focusNode: focusNode,
        showCheckmark: true,
        checkmarkColor: ink,
        color: fill,
        padding: padding,
        labelPadding: labelPadding,
        pressElevation: 0,
        visualDensity: density,
        materialTapTargetSize: tapTarget,
      );
    } else {
      // Render the disabled palette at full opacity and exclude the inert
      // chip's native semantics in favour of a single named disabled node.
      chip = Semantics(
        container: true,
        excludeSemantics: true,
        button: true,
        enabled: false,
        selected: kIsWeb ? null : selected,
        checked: kIsWeb ? selected : null,
        label: spokenCaption ?? caption,
        child: ExcludeFocus(
          child: RawChip(
            tapEnabled: false,
            isEnabled: true,
            label: body,
            labelStyle: style,
            selected: selected,
            showCheckmark: true,
            checkmarkColor: ink,
            color: fill,
            side: BorderSide(
              color: selected ? Colors.transparent : palette.muted,
            ),
            padding: padding,
            labelPadding: labelPadding,
            elevation: 0,
            pressElevation: 0,
            visualDensity: density,
            materialTapTargetSize: tapTarget,
          ),
        ),
      );
    }
    return ListHeaderQuickChipTheme(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 48,
          minHeight: choiceTargetHeight(context, [caption]),
        ),
        child: chip,
      ),
    );
  }
}
