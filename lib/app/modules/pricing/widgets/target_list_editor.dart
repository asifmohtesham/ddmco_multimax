import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';

/// Rule targets (items / item groups / brands) with an optional unit chip,
/// remove button and an "Add …" footer row.
class TargetListEditor extends StatelessWidget {
  const TargetListEditor({
    super.key,
    required this.targets,
    required this.applyOn,
    required this.readOnly,
    required this.onAdd,
    required this.onRemove,
    required this.onPickUom,
  });

  final List<PricingRuleTarget> targets;
  final String applyOn;
  final bool readOnly;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onPickUom;

  static const _addLabel = {
    'Item Code': 'Add item',
    'Item Group': 'Add item group',
    'Brand': 'Add brand',
  };

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final isItem = applyOn == 'Item Code';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < targets.length; i++)
              Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: EdgeInsets.fromLTRB(12, 3, readOnly ? 12 : 4, 3),
                decoration: BoxDecoration(
                  color: s.fg,
                  border: Border(bottom: BorderSide(color: s.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isItem && targets[i].label != null)
                            Text(targets[i].value,
                                style: TextStyle(
                                    fontFamily: 'ShureTechMono',
                                    fontSize: 11,
                                    color: s.textMuted)),
                          Text(
                            (isItem ? targets[i].label : null) ?? targets[i].value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: s.text),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _UomChip(
                      uom: targets[i].uom,
                      onTap: readOnly ? null : () => onPickUom(i),
                    ),
                    if (!readOnly)
                      IconButton(
                        tooltip: 'Remove',
                        icon: Icon(Icons.close, size: 20, color: s.textSubtle),
                        onPressed: () => onRemove(i),
                      ),
                  ],
                ),
              ),
            if (!readOnly)
              InkWell(
                onTap: onAdd,
                child: Container(
                  height: 44,
                  color: s.subtle,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(Icons.add, size: 18, color: s.primary),
                      const SizedBox(width: 8),
                      Text(_addLabel[applyOn] ?? 'Add',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: s.primary)),
                      const Spacer(),
                      // The item picker listens for scans (enableBarcodeScan).
                      if (isItem)
                        Icon(Icons.qr_code_scanner, size: 20, color: s.primary),
                    ],
                  ),
                ),
              )
            else if (targets.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('None', style: TextStyle(color: s.textMuted)),
              ),
          ],
        ),
      ),
    );
  }
}

class _UomChip extends StatelessWidget {
  const _UomChip({required this.uom, required this.onTap});

  final String? uom;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: uom == null ? s.border : s.borderStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(uom ?? 'Any unit',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: uom == null ? s.textSubtle : s.textMuted)),
            if (onTap != null)
              Icon(Icons.arrow_drop_down, size: 14, color: s.textSubtle),
          ],
        ),
      ),
    );
  }
}
