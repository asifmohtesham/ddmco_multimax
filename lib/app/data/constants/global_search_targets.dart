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

  /// Whether to offer this doctype to the user as a browsable target — the
  /// Dashboard fan-out, its scope chips, and the ToDo reference-type picker.
  ///
  /// `false` registers the doctype for routing ONLY: its list screen can run
  /// an in-list search and open a hit, but it never appears in a cross-doctype
  /// result list. For doctypes whose `name` is a random hash that is the whole
  /// point — the hash is meaningless next to other doctypes' hits, but
  /// irrelevant inside its own list, where the row is matched on real fields.
  final bool discoverable;

  /// Navigation arguments that open a BLANK document of this doctype — the
  /// Awesome Bar's "New *DocType*" contract. `null` = the app has no bare
  /// create path for the doctype (Item, Job Card), so no "New" option is
  /// ever offered for it.
  ///
  /// Traced per doctype from the list screen's own create affordance (FAB /
  /// `openCreate…`), exactly as [argsFor] is traced from the row tap. Some
  /// doctypes create through a picker dialog on their LIST screen rather
  /// than the form (Packing Slip); those set [newRoute] to the list route
  /// and pass the list's `openCreate` flag.
  final Map<String, dynamic>? newArgs;

  /// Route [newArgs] are sent to. Defaults to [route] (the form).
  final String? newRoute;

  const GlobalSearchTarget({
    required this.doctype,
    required this.label,
    required this.icon,
    required this.color,
    required this.route,
    required this.argsFor,
    this.discoverable = true,
    this.newArgs,
    this.newRoute,
  });

  /// Whether a "New *DocType*" option can be offered.
  bool get canCreate => newArgs != null;

  /// The route a "New *DocType*" option opens.
  String get createRoute => newRoute ?? route;
}

/// `{'name': '', 'mode': 'new'}` — the create contract shared by most form
/// controllers (`name = Get.arguments['name']; mode = Get.arguments['mode']`).
const Map<String, dynamic> _kNewNameMode = {'name': '', 'mode': 'new'};

Map<String, dynamic> _nameView(String id) => {'name': id, 'mode': 'view'};
Map<String, dynamic> _nameEdit(String id) => {'name': id, 'mode': 'edit'};

/// Every doctype a search hit can be OPENED as, in display order.
///
/// This is the routing registry: [searchNavArgsFor] and [searchTargetForDoctype]
/// read it, so a doctype missing from here cannot be navigated to from a search
/// result (the lookup degrades to a bare id, which forms reading
/// `Get.arguments['name']` throw on).
///
/// It is NOT the list of doctypes offered to users for browsing — that is
/// [kDiscoverableSearchTargets], the `discoverable` subset.
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
    // DeliveryNoteController.openCreate… → {'name': '', 'mode': 'new'}.
    newArgs: _kNewNameMode,
  ),
  GlobalSearchTarget(
    doctype: 'Purchase Receipt',
    label: 'Purchase Receipts',
    icon: Icons.receipt_long_outlined,
    color: Colors.green,
    route: AppRoutes.PURCHASE_RECEIPT_FORM,
    argsFor: _nameView,
    // PurchaseReceiptFormController._initNewPurchaseReceipt tolerates a
    // missing `purchaseOrder` / `supplier` (blank receipt).
    newArgs: _kNewNameMode,
  ),
  GlobalSearchTarget(
    doctype: 'Stock Entry',
    label: 'Stock Entries',
    icon: Icons.compare_arrows_outlined,
    color: Colors.orange,
    route: AppRoutes.STOCK_ENTRY_FORM,
    argsFor: _nameView,
    // StockEntryController create dialog → blank type + reference.
    newArgs: {
      'name': '',
      'mode': 'new',
      'stockEntryType': '',
      'customReferenceNo': '',
    },
  ),
  GlobalSearchTarget(
    doctype: 'Packing Slip',
    label: 'Packing Slips',
    icon: Icons.assignment_return_outlined,
    color: Colors.purple,
    route: AppRoutes.PACKING_SLIP_FORM,
    argsFor: _nameView,
    // A Packing Slip is created from a Delivery Note picked on the LIST
    // screen (PackingSlipController.openCreateDialog via `openCreate`).
    newRoute: AppRoutes.PACKING_SLIP,
    newArgs: {'openCreate': true},
  ),
  GlobalSearchTarget(
    doctype: 'POS Upload',
    label: 'POS Uploads',
    icon: Icons.shopping_bag_outlined,
    color: Colors.deepPurple,
    route: AppRoutes.POS_UPLOAD_FORM,
    argsFor: _nameView,
    // PosUploadScreen FAB → {'name': '', 'mode': 'new'}.
    newArgs: _kNewNameMode,
  ),
  GlobalSearchTarget(
    doctype: 'Purchase Order',
    label: 'Purchase Orders',
    icon: Icons.shopping_cart_outlined,
    color: Colors.brown,
    route: AppRoutes.PURCHASE_ORDER_FORM,
    argsFor: _nameView,
    // PurchaseOrderController.openCreateForm → {'name': '', 'mode': 'new'}.
    newArgs: _kNewNameMode,
  ),
  GlobalSearchTarget(
    doctype: 'Sales Order',
    label: 'Sales Orders',
    icon: Icons.request_quote_outlined,
    color: Colors.teal,
    route: AppRoutes.SALES_ORDER_FORM,
    argsFor: _nameView,
    // SalesOrderController.openCreate → {'name': '', 'mode': 'new'}.
    newArgs: _kNewNameMode,
  ),
  GlobalSearchTarget(
    doctype: 'Material Request',
    label: 'Material Requests',
    icon: Icons.request_page_outlined,
    color: Colors.pink,
    route: AppRoutes.MATERIAL_REQUEST_FORM,
    argsFor: _nameView,
    // MaterialRequestController.openCreateForm → {'name': '', 'mode': 'new'}.
    newArgs: _kNewNameMode,
  ),
  GlobalSearchTarget(
    doctype: 'Work Order',
    label: 'Work Orders',
    icon: Icons.precision_manufacturing_outlined,
    color: Colors.indigo,
    route: AppRoutes.WORK_ORDER_FORM,
    argsFor: _nameView,
    // WorkOrderScreen FAB → {'name': '', 'mode': 'new'}.
    newArgs: _kNewNameMode,
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
    // BomScreen FAB → {'name': '', 'mode': 'new'}.
    newArgs: _kNewNameMode,
  ),
  GlobalSearchTarget(
    doctype: 'Batch',
    label: 'Batches',
    icon: Icons.layers_outlined,
    color: Colors.amber,
    route: AppRoutes.BATCH_FORM,
    argsFor: _batchArgs,
    // BatchController.openBatchForm() → {'name': '', 'mode': 'new'}.
    newArgs: _kNewNameMode,
  ),
  GlobalSearchTarget(
    doctype: 'ToDo',
    label: 'ToDos',
    icon: Icons.check_circle_outline,
    color: Colors.cyan,
    route: AppRoutes.TODO_FORM,
    argsFor: _nameView,
    // TodoScreen FAB → {'name': '', 'mode': 'new'}.
    newArgs: _kNewNameMode,
  ),
  GlobalSearchTarget(
    doctype: 'Pricing Rule',
    label: 'Pricing Rules',
    icon: Icons.discount_outlined,
    color: Colors.deepOrange,
    route: AppRoutes.PRICING_RULE_FORM,
    argsFor: _nameEdit,
    // PricingRuleController.openRule(null) → {'name': '', 'mode': 'new'}.
    newArgs: _kNewNameMode,
  ),
  GlobalSearchTarget(
    doctype: 'Item Price',
    label: 'Item Prices',
    icon: Icons.sell_outlined,
    color: Colors.indigo,
    route: AppRoutes.ITEM_PRICE_FORM,
    // ItemPriceController.openPrice opens an existing row in `edit`.
    argsFor: _nameEdit,
    // ItemPriceController.openPrice(null) → {'name': '', 'mode': 'new'}.
    newArgs: _kNewNameMode,
    // Item Price names are random hashes — useless in a cross-doctype result
    // list, but the Item Price list screen searches its own rows on item_code
    // / price list, so it still needs a route to open a hit with.
    discoverable: false,
  ),
];

/// The targets offered to the user for browsing: the Dashboard's all-doctype
/// fan-out, its scope chips, and the ToDo reference-type picker.
///
/// Derived from [kGlobalSearchTargets]; see [GlobalSearchTarget.discoverable].
final List<GlobalSearchTarget> kDiscoverableSearchTargets =
    kGlobalSearchTargets.where((t) => t.discoverable).toList();

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
