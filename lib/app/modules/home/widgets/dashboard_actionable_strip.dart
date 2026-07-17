import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

/// Which population the actionable count strip reflects. [mine] scopes the
/// five document chips to the selected dashboard user (owner); [everyone] is
/// company-wide. The Tasks chip stays personal regardless.
enum ActionableScope { mine, everyone }

String actionableScopeToString(ActionableScope scope) =>
    scope == ActionableScope.everyone ? 'everyone' : 'mine';

ActionableScope actionableScopeFromString(String? raw) =>
    raw == 'everyone' ? ActionableScope.everyone : ActionableScope.mine;

/// Frappe filter map for the "still a Draft" documents of [doctype]. Used for
/// the `get_count` query, the 3-document preview, AND the tap-target list, so a
/// chip's count, its preview, and its opened list always agree.
///
/// PO/PR/DN filter on `status == 'Draft'` (equivalent to docstatus 0 for these
/// submittables, and it renders a removable "Status: Draft" chip on the list).
/// Stock Entry has no `status` field, and Packing Slip's `status` is a VIRTUAL
/// field that raises a Frappe FieldError when queried — both filter on
/// `docstatus == 0`. Under [ActionableScope.mine] a non-empty [email] adds an
/// `owner` equality.
Map<String, dynamic> actionableFiltersFor(
    String doctype, ActionableScope scope, String? email) {
  final filters = <String, dynamic>{};
  if (doctype == 'Stock Entry' || doctype == 'Packing Slip') {
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

/// Static identity of one document chip. [label] is the presentation label
/// (currently the full DocType name; the Tasks chip built in the screen uses a
/// different label, which is why this is a separate field). [previewFields] are
/// the ONLY fields the 3-document preview requests for this DocType.
class ActionableDocConfig {
  final String doctype;
  final String label;
  final IconData icon;
  final String listRoute;
  final String formRoute;
  final List<String> previewFields;
  const ActionableDocConfig({
    required this.doctype,
    required this.label,
    required this.icon,
    required this.listRoute,
    required this.formRoute,
    required this.previewFields,
  });
}

const List<ActionableDocConfig> kActionableDocConfigs = [
  ActionableDocConfig(
    doctype: 'Purchase Order',
    label: 'Purchase Order',
    icon: Icons.shopping_cart_outlined,
    listRoute: AppRoutes.PURCHASE_ORDER,
    formRoute: AppRoutes.PURCHASE_ORDER_FORM,
    previewFields: ['name', 'supplier', 'transaction_date', 'owner'],
  ),
  ActionableDocConfig(
    doctype: 'Purchase Receipt',
    label: 'Purchase Receipt',
    icon: Icons.receipt_long_outlined,
    listRoute: AppRoutes.PURCHASE_RECEIPT,
    formRoute: AppRoutes.PURCHASE_RECEIPT_FORM,
    previewFields: ['name', 'supplier', 'posting_date', 'owner'],
  ),
  ActionableDocConfig(
    doctype: 'Stock Entry',
    label: 'Stock Entry',
    icon: Icons.swap_horiz,
    listRoute: AppRoutes.STOCK_ENTRY,
    formRoute: AppRoutes.STOCK_ENTRY_FORM,
    previewFields: ['name', 'stock_entry_type', 'posting_date', 'owner'],
  ),
  ActionableDocConfig(
    doctype: 'Delivery Note',
    label: 'Delivery Note',
    icon: Icons.local_shipping_outlined,
    listRoute: AppRoutes.DELIVERY_NOTE,
    formRoute: AppRoutes.DELIVERY_NOTE_FORM,
    previewFields: ['name', 'customer', 'posting_date', 'owner'],
  ),
  // Packing Slip: `status` is virtual (FieldError if queried) and there is no
  // posting_date on its list — the row falls back to `creation`.
  ActionableDocConfig(
    doctype: 'Packing Slip',
    label: 'Packing Slip',
    icon: Icons.inventory_2_outlined,
    listRoute: AppRoutes.PACKING_SLIP,
    formRoute: AppRoutes.PACKING_SLIP_FORM,
    previewFields: ['name', 'delivery_note', 'creation', 'owner'],
  ),
];

/// The chip selected on load: 'ToDo' (Tasks) when it has work, else the first
/// [kActionableDocConfigs] doctype with a non-zero count, else null (every chip
/// is muted/inert, so nothing is selectable).
String? defaultActionableSelection(Map<String, int> counts, int todoCount) {
  if (todoCount > 0) return 'ToDo';
  for (final cfg in kActionableDocConfigs) {
    if ((counts[cfg.doctype] ?? 0) > 0) return cfg.doctype;
  }
  return null;
}

/// One rendered chip's data. [muted] (a zero count) renders dim with a null
/// [onTap] so the chip is non-interactive and cannot be selected.
class ActionableChipData {
  final String doctype;
  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback? onTap;
  const ActionableChipData({
    required this.doctype,
    required this.label,
    required this.icon,
    required this.count,
    required this.onTap,
    this.selected = false,
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
    final selected = data.selected;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? cs.primary.withValues(alpha: 0.13) : scheme.fg,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: selected ? cs.primary : scheme.border),
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
              color: muted
                  ? scheme.textMuted
                  : (selected ? cs.primary : scheme.text),
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
      return content;
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

/// The horizontally-scrolling row of actionable chips — a DocType selector.
/// Never wraps (the previous Wrap spilled onto a second row). Shows muted
/// placeholder pills while [isLoading]. Selection is carried per-chip via
/// [ActionableChipData.selected] / [ActionableChipData.onTap].
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
      return SingleChildScrollView(
        key: const ValueKey('actionable-strip-loading'),
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          children: [
            for (var i = 0; i < 6; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Container(
                width: 96,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.subtle,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: scheme.border),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return SingleChildScrollView(
      key: const ValueKey('actionable-strip'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            ActionableCountChip(data: chips[i]),
          ],
        ],
      ),
    );
  }
}
