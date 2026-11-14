import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// 20dp neutral tag (DESIGN_SPEC "ScopeTag"): customer / supplier / batch /
/// dates on list rows. [ink] recolours text + icon (price-list / side tags).
class ScopeTag extends StatelessWidget {
  const ScopeTag({super.key, required this.label, this.icon, this.ink});

  final String label;
  final IconData? icon;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final color = ink ?? s.textMuted;
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: s.subtle,
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w500, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

Color _sideInk(BuildContext context, {required bool selling}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (selling) return dark ? AppColors.green300 : AppColors.green700;
  return dark ? AppColors.blue300 : AppColors.blue700;
}

/// Price-list tag: green ink for selling lists, blue for buying.
Widget priceListTag(BuildContext context, String name, {required bool selling}) =>
    ScopeTag(label: name, ink: _sideInk(context, selling: selling));

/// "Selling" / "Buying" / "Selling & Buying" tag for rule rows.
Widget sideTag(BuildContext context,
        {required bool selling, required bool buying}) =>
    ScopeTag(
      label: selling && buying
          ? 'Selling & Buying'
          : buying
              ? 'Buying'
              : 'Selling',
      ink: _sideInk(context, selling: !(buying && !selling)),
    );

/// "P5" accent badge.
class PriorityBadge extends StatelessWidget {
  const PriorityBadge({super.key, required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    // No `alignment:` — a Container with an alignment and no width expands to
    // the incoming max width, which stretched the badge across the whole row.
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(s.primary.withValues(alpha: 0.12), s.fg),
        borderRadius: BorderRadius.circular(6),
      ),
      // widthFactor keeps the box tight around the label while still
      // centring it vertically inside the fixed 20dp height.
      child: Center(
        widthFactor: 1,
        child: Text(
          'P$priority',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: s.primary),
        ),
      ),
    );
  }
}
