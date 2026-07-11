import 'package:flutter/material.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

/// One searchable doctype for the Dashboard global search.
///
/// [argsFor] returns the exact navigation arguments the target form expects —
/// traced per-doctype from each form controller / list-row tap. This is the
/// canonical "open this document" contract for the doctype.
class GlobalSearchTarget {
  /// Frappe DocType queried, e.g. 'Delivery Note'.
  final String doctype;

  /// Section header shown in the grouped results, e.g. 'Delivery Notes'.
  final String label;

  /// Decorative leading icon (reuses the Quick-Create tile visuals).
  final IconData icon;

  /// Decorative tint for [icon] (rendered at low alpha over the surface).
  final Color color;

  /// Form route to navigate to on tap.
  final String route;

  /// Builds the navigation arguments for document [id].
  final Map<String, dynamic> Function(String id) argsFor;

  const GlobalSearchTarget({
    required this.doctype,
    required this.label,
    required this.icon,
    required this.color,
    required this.route,
    required this.argsFor,
  });
}

Map<String, dynamic> _nameView(String id) => {'name': id, 'mode': 'view'};

/// Every routed doctype the Dashboard search can reach, in display order.
const List<GlobalSearchTarget> kGlobalSearchTargets = [
  GlobalSearchTarget(
    doctype: 'Item',
    label: 'Items',
    icon: Icons.inventory_2_outlined,
    color: Colors.blueGrey,
    route: AppRoutes.ITEM_FORM,
    argsFor: _itemArgs,
  ),
  GlobalSearchTarget(
    doctype: 'Delivery Note',
    label: 'Delivery Notes',
    icon: Icons.local_shipping_outlined,
    color: Colors.blue,
    route: AppRoutes.DELIVERY_NOTE_FORM,
    argsFor: _nameView,
  ),
  GlobalSearchTarget(
    doctype: 'Purchase Receipt',
    label: 'Purchase Receipts',
    icon: Icons.receipt_long_outlined,
    color: Colors.green,
    route: AppRoutes.PURCHASE_RECEIPT_FORM,
    argsFor: _nameView,
  ),
  GlobalSearchTarget(
    doctype: 'Stock Entry',
    label: 'Stock Entries',
    icon: Icons.compare_arrows_outlined,
    color: Colors.orange,
    route: AppRoutes.STOCK_ENTRY_FORM,
    argsFor: _nameView,
  ),
  GlobalSearchTarget(
    doctype: 'Packing Slip',
    label: 'Packing Slips',
    icon: Icons.assignment_return_outlined,
    color: Colors.purple,
    route: AppRoutes.PACKING_SLIP_FORM,
    argsFor: _nameView,
  ),
  GlobalSearchTarget(
    doctype: 'POS Upload',
    label: 'POS Uploads',
    icon: Icons.shopping_bag_outlined,
    color: Colors.deepPurple,
    route: AppRoutes.POS_UPLOAD_FORM,
    argsFor: _nameView,
  ),
  GlobalSearchTarget(
    doctype: 'Purchase Order',
    label: 'Purchase Orders',
    icon: Icons.shopping_cart_outlined,
    color: Colors.brown,
    route: AppRoutes.PURCHASE_ORDER_FORM,
    argsFor: _nameView,
  ),
  GlobalSearchTarget(
    doctype: 'Material Request',
    label: 'Material Requests',
    icon: Icons.request_page_outlined,
    color: Colors.pink,
    route: AppRoutes.MATERIAL_REQUEST_FORM,
    argsFor: _nameView,
  ),
  GlobalSearchTarget(
    doctype: 'Work Order',
    label: 'Work Orders',
    icon: Icons.precision_manufacturing_outlined,
    color: Colors.indigo,
    route: AppRoutes.WORK_ORDER_FORM,
    argsFor: _nameView,
  ),
  GlobalSearchTarget(
    doctype: 'Job Card',
    label: 'Job Cards',
    icon: Icons.assignment_ind_outlined,
    color: Colors.deepOrange,
    route: AppRoutes.JOB_CARD_FORM,
    argsFor: _nameOnly,
  ),
  GlobalSearchTarget(
    doctype: 'BOM',
    label: 'BOMs',
    icon: Icons.account_tree_outlined,
    color: Colors.teal,
    route: AppRoutes.BOM_FORM,
    argsFor: _nameOnly,
  ),
  GlobalSearchTarget(
    doctype: 'Batch',
    label: 'Batches',
    icon: Icons.layers_outlined,
    color: Colors.amber,
    route: AppRoutes.BATCH_FORM,
    argsFor: _batchArgs,
  ),
  GlobalSearchTarget(
    doctype: 'ToDo',
    label: 'ToDos',
    icon: Icons.check_circle_outline,
    color: Colors.cyan,
    route: AppRoutes.TODO_FORM,
    argsFor: _nameView,
  ),
];

// Top-level functions (const list requires const-tear-off-able references).
Map<String, dynamic> _itemArgs(String id) => {'itemCode': id};
Map<String, dynamic> _nameOnly(String id) => {'name': id};
Map<String, dynamic> _batchArgs(String id) => {'name': id, 'mode': 'edit'};

/// Canonical navigation arguments for opening document [id] on form [route].
///
/// Routes registered in [kGlobalSearchTargets] get that target's [argsFor]
/// map — the shape the form controller actually reads (`{'name': …, 'mode':
/// …}` etc.). Unregistered routes fall back to the bare [id] for callers
/// whose forms accept a plain String argument.
dynamic searchNavArgsFor(String route, String id) {
  for (final t in kGlobalSearchTargets) {
    if (t.route == route) return t.argsFor(id);
  }
  return id;
}

/// Looks up the registered [GlobalSearchTarget] for [doctype], e.g. to
/// resolve where a ToDo's `reference_type` should navigate to. Returns
/// `null` when the doctype has no registered form route — callers should
/// render the reference as non-tappable in that case.
GlobalSearchTarget? searchTargetForDoctype(String doctype) {
  for (final t in kGlobalSearchTargets) {
    if (t.doctype == doctype) return t;
  }
  return null;
}
