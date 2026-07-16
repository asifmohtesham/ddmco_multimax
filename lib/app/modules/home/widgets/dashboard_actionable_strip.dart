import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

/// Which population the actionable count strip reflects. [mine] scopes the
/// four document chips to the selected dashboard user (owner); [everyone] is
/// company-wide. The Tasks chip stays personal regardless.
enum ActionableScope { mine, everyone }

String actionableScopeToString(ActionableScope scope) =>
    scope == ActionableScope.everyone ? 'everyone' : 'mine';

ActionableScope actionableScopeFromString(String? raw) =>
    raw == 'everyone' ? ActionableScope.everyone : ActionableScope.mine;

/// Frappe filter map for the "still a Draft" documents of [doctype]. Used for
/// BOTH the `get_count` query and the tap-target list, so a chip's count and
/// its opened list always agree.
///
/// PO/PR/DN filter on `status == 'Draft'` (equivalent to docstatus 0 for these
/// submittables, and it renders a removable "Status: Draft" chip on the list).
/// Stock Entry has no `status` field — its status is derived from docstatus —
/// so it filters on `docstatus == 0`. Under [ActionableScope.mine] a non-empty
/// [email] adds an `owner` equality.
Map<String, dynamic> actionableFiltersFor(
    String doctype, ActionableScope scope, String? email) {
  final filters = <String, dynamic>{};
  if (doctype == 'Stock Entry') {
    filters['docstatus'] = 0;
  } else {
    filters['status'] = 'Draft';
  }
  if (scope == ActionableScope.mine && email != null && email.isNotEmpty) {
    filters['owner'] = email;
  }
  return filters;
}

/// Cache key for a scope's counts. `mine` depends on the viewed user; `everyone`
/// is user-independent so it collapses to a single `'all'` bucket.
String actionableCacheKey(ActionableScope scope, String? email) =>
    scope == ActionableScope.mine ? 'mine::${email ?? ''}' : 'all';

/// Static identity of one document chip — label/icon/route are presentation
/// constants; the live count is supplied separately via [ActionableChipData].
class ActionableDocConfig {
  final String doctype;
  final String label;
  final IconData icon;
  final String listRoute;
  const ActionableDocConfig(this.doctype, this.label, this.icon, this.listRoute);
}

const List<ActionableDocConfig> kActionableDocConfigs = [
  ActionableDocConfig('Purchase Order', 'PO', Icons.shopping_cart_outlined, AppRoutes.PURCHASE_ORDER),
  ActionableDocConfig('Purchase Receipt', 'PR', Icons.receipt_long_outlined, AppRoutes.PURCHASE_RECEIPT),
  ActionableDocConfig('Stock Entry', 'SE', Icons.swap_horiz, AppRoutes.STOCK_ENTRY),
  ActionableDocConfig('Delivery Note', 'DN', Icons.local_shipping_outlined, AppRoutes.DELIVERY_NOTE),
];

/// One rendered chip's data. [muted] (a zero count) renders dim and passes a
/// null [onTap] so the chip is non-interactive.
class ActionableChipData {
  final String doctype;
  final String label;
  final IconData icon;
  final int count;
  final VoidCallback? onTap;
  const ActionableChipData({
    required this.doctype,
    required this.label,
    required this.icon,
    required this.count,
    required this.onTap,
  });

  bool get muted => count == 0;
}

/// A compact pill: icon + short label + count. A [ActionableChipData.muted]
/// (zero) chip renders dim and is not wrapped in an InkWell (non-interactive);
/// otherwise the whole pill is tappable.
class ActionableCountChip extends StatelessWidget {
  final ActionableChipData data;
  const ActionableCountChip({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final cs = Theme.of(context).colorScheme;
    final muted = data.muted;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.fg,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: scheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon,
              size: 16, color: muted ? scheme.textSubtle : cs.primary),
          const SizedBox(width: 6),
          Text(
            data.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: muted ? scheme.textMuted : scheme.text,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${data.count}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: muted ? scheme.textSubtle : cs.primary,
            ),
          ),
        ],
      ),
    );

    if (muted || data.onTap == null) {
      return Opacity(opacity: 0.55, child: content);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: content,
      ),
    );
  }
}

/// Two-segment "Mine | Everyone" control, styled after DashboardColumnsToggle.
class ActionableScopeToggle extends StatelessWidget {
  final ActionableScope scope;
  final ValueChanged<ActionableScope> onChanged;
  const ActionableScopeToggle({
    super.key,
    required this.scope,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scheme = context.scheme;

    Widget seg(ActionableScope value, String label) {
      final selected = scope == value;
      return InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? cs.primary.withValues(alpha: 0.13) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? cs.primary : scheme.textSubtle,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.subtle,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: scheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(ActionableScope.mine, 'Mine'),
          const SizedBox(width: 2),
          seg(ActionableScope.everyone, 'Everyone'),
        ],
      ),
    );
  }
}

/// The wrap of actionable-count chips. Shows muted placeholder pills while
/// [isLoading]; otherwise a [Wrap] of [ActionableCountChip]s (one per [chips]).
class DashboardActionableStrip extends StatelessWidget {
  final List<ActionableChipData> chips;
  final bool isLoading;
  const DashboardActionableStrip({
    super.key,
    required this.chips,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    if (isLoading) {
      return Wrap(
        key: const ValueKey('actionable-strip-loading'),
        spacing: 8,
        runSpacing: 8,
        children: List.generate(
          5,
          (_) => Container(
            width: 64,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.subtle,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: scheme.border),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final c in chips) ActionableCountChip(data: c)],
    );
  }
}
