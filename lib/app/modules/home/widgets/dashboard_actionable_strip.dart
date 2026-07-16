import 'package:flutter/material.dart';
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
