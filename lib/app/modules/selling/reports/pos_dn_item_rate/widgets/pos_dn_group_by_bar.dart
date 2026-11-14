import 'package:flutter/material.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart';

/// "Group by" control row: a primary field chip, an optional secondary field
/// chip (shown once a primary is chosen), and expand/collapse-all buttons.
/// Selection uses a bottom-sheet menu (None + the five groupable fields).
class PosDnGroupByBar extends StatelessWidget {
  final PosDnGroupField? primary;
  final PosDnGroupField? secondary;
  final ValueChanged<PosDnGroupField?> onPrimaryChanged;
  final ValueChanged<PosDnGroupField?> onSecondaryChanged;
  final VoidCallback onExpandAll;
  final VoidCallback onCollapseAll;

  const PosDnGroupByBar({
    super.key,
    required this.primary,
    required this.secondary,
    required this.onPrimaryChanged,
    required this.onSecondaryChanged,
    required this.onExpandAll,
    required this.onCollapseAll,
  });

  Future<void> _pick(
    BuildContext context, {
    required PosDnGroupField? current,
    required PosDnGroupField? exclude,
    required ValueChanged<PosDnGroupField?> onChanged,
  }) async {
    final options = <PosDnGroupField?>[
      null,
      ...PosDnGroupField.values.where((f) => f != exclude),
    ];
    final chosen = await showModalBottomSheet<Object?>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in options)
                ListTile(
                  title: Text(f?.label ?? 'None'),
                  trailing: f == current
                      ? Icon(Icons.check, color: cs.primary)
                      : null,
                  // Wrap null in a sentinel so it survives the pop.
                  onTap: () => Navigator.pop(ctx, f ?? _none),
                ),
            ],
          ),
        );
      },
    );
    if (chosen == null) return; // dismissed
    onChanged(identical(chosen, _none) ? null : chosen as PosDnGroupField);
  }

  static const Object _none = Object();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      children: [
        Text('Group by:',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip(
                avatar: Icon(Icons.layers_outlined, size: 16, color: cs.primary),
                label: Text(primary?.label ?? 'Group by'),
                onPressed: () => _pick(
                  context,
                  current: primary,
                  exclude: null,
                  onChanged: onPrimaryChanged,
                ),
              ),
              if (primary != null)
                ActionChip(
                  avatar: Icon(Icons.subdirectory_arrow_right,
                      size: 16, color: cs.primary),
                  label: Text(secondary?.label ?? '+ Then by'),
                  onPressed: () => _pick(
                    context,
                    current: secondary,
                    exclude: primary,
                    onChanged: onSecondaryChanged,
                  ),
                ),
            ],
          ),
        ),
        if (primary != null) ...[
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.unfold_more),
            tooltip: 'Expand all',
            onPressed: onExpandAll,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.unfold_less),
            tooltip: 'Collapse all',
            onPressed: onCollapseAll,
          ),
        ],
      ],
    );
  }
}
