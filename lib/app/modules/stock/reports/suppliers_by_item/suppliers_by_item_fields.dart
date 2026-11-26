import 'package:multimax/app/data/utils/suppliers_by_item_labels.dart';

enum SuppliersByItemFieldGroup {
  item('Item rows'),
  supplier('Supplier rows'),
  supplierColumns('Supplier table columns'),
  component('BOM component rows'),
  bom('BOM and tree labels'),
  search('Search');

  const SuppliersByItemFieldGroup(this.label);

  final String label;
}

/// Optional row details. Row identities and tree controls are always visible.
/// The enum names are the stored preference keys.
enum SuppliersByItemField {
  itemName.item('Item Name', onByDefault: true),
  itemSupplierCount.item('Supplier Count', onByDefault: true),
  itemBalance.item(SuppliersByItemColumnLabels.balanceQty, onByDefault: true),
  itemStockUom.item('Stock UOM', onByDefault: true),
  itemProjected.item(SuppliersByItemColumnLabels.projectedQty),
  itemBelowReorder.item('Projected Qty below Reorder Level', onByDefault: true),
  itemReorderLevel.item('Reorder Level'),
  itemReorderQty.item('Reorder Qty'),
  itemOpenOrders.item(SuppliersByItemColumnLabels.openOrderQty),
  itemDraftOrders.item('Draft Order Qty'),
  itemQtyReceived.item('Total Qty Received'),
  supplierStatus.supplier('Supplier Status', onByDefault: true),
  supplierOpenOrders.supplier(
    SuppliersByItemColumnLabels.openOrderQty,
    onByDefault: true,
  ),
  supplierStockUom.supplier('Stock UOM', onByDefault: true),
  supplierDraftOrders.supplier('Draft Order Qty'),
  supplierPartNumber.supplier(SuppliersByItemColumnLabels.supplierPartNumber),
  supplierSources.supplier('Sources'),
  supplierLastPurchase.supplier('Last Purchase Date'),
  supplierLastPurchaseReceipt.supplier('Last Purchase Receipt'),
  supplierQtyReceived.supplier('Total Qty Received'),
  supplierLastPo.supplier('Last PO Date'),
  supplierRate.supplier('Last Rate'),
  supplierRateCurrency.supplier('Currency', onByDefault: true),
  supplierRateUom.supplier('Rate UOM', onByDefault: true),
  supplierRateSource.supplier('Rate Source'),
  supplierRateDate.supplier('Rate Date'),
  supplierRateDocument.supplier('Rate Document'),
  supplierLeadTime.supplier(SuppliersByItemColumnLabels.leadTimeDays),
  supplierLeadTimeReceipts.supplier(
    SuppliersByItemColumnLabels.leadTimeReceipts,
  ),
  supplierPoCount.supplier('PO Count'),
  supplierReceiptCount.supplier('Receipt Count'),
  componentName.component('Item Name', onByDefault: true),
  componentSupplierCount.component('Supplier Count', onByDefault: true),
  componentQtyPerUnit.component('BOM Qty per Unit', onByDefault: true),
  componentStockUom.component('Stock UOM', onByDefault: true),
  componentBalance.component(SuppliersByItemColumnLabels.balanceQty),
  componentProjected.component(SuppliersByItemColumnLabels.projectedQty),
  componentLastPurchase.component('Last Purchase Date'),
  componentUsedInBoms.component('BOMs using this component'),
  componentManufacturing.component(
    'Manufacturing exclusion',
    onByDefault: true,
  ),
  componentCycle.component('BOM cycle warning', onByDefault: true),
  componentDepthLimit.component('BOM depth limit warning', onByDefault: true),
  templateVariantCount.item('Variant count', onByDefault: true),
  itemOpenPoBadge.item(
    SuppliersByItemColumnLabels.openOrderQty,
    qualifier: 'Badge',
    onByDefault: true,
  ),
  itemDraftPoBadge.item(
    'Draft Order Qty',
    qualifier: 'Badge',
    onByDefault: true,
  ),
  supplierLastBuyColumn.supplierColumn('Last Purchase Date', onByDefault: true),
  supplierOpenPoBadge.supplierColumn(
    SuppliersByItemColumnLabels.openOrderQty,
    onByDefault: true,
  ),
  supplierDraftPoBadge.supplierColumn('Draft Order Qty', onByDefault: true),
  supplierMatchEmphasis.supplier(
    'Highlight Suppliers filter matches',
    onByDefault: true,
  ),
  bomDefaultMarker.visible(SuppliersByItemFieldGroup.bom, 'Default BOM label'),
  bomDraftBadge.visible(SuppliersByItemFieldGroup.bom, 'Draft BOM badge'),
  bomComponentCount.visible(SuppliersByItemFieldGroup.bom, 'BOM components'),
  treeDepthLabel.visible(
    SuppliersByItemFieldGroup.bom,
    'Depth label on deep rows',
  ),
  searchMatchCount.visible(
    SuppliersByItemFieldGroup.search,
    'Search match count',
  ),
  supplierGroupItemCount.supplier(
    'Items',
    qualifier: 'Group count',
    onByDefault: true,
  ),
  supplierGroupComponentCount.supplier(
    'BOM components',
    qualifier: 'Group count',
    onByDefault: true,
  ),
  componentMatchPath.component(
    'Item / Supplier',
    qualifier: 'BOM path',
    onByDefault: true,
  ),
  // Added after release: keep new IDs last so stored preferences stay valid.
  supplierRateColumn.supplierColumn('Last Rate'),
  supplierLeadTimeColumn.supplierColumn(
    SuppliersByItemColumnLabels.leadTimeDays,
  ),
  supplierQtyReceivedColumn.supplierColumn('Total Qty Received');

  const SuppliersByItemField.item(
    this.label, {
    this.onByDefault = false,
    this.qualifier,
  }) : group = SuppliersByItemFieldGroup.item;

  const SuppliersByItemField.supplier(
    this.label, {
    this.onByDefault = false,
    this.qualifier,
  }) : group = SuppliersByItemFieldGroup.supplier;

  const SuppliersByItemField.supplierColumn(
    this.label, {
    this.onByDefault = false,
  }) : group = SuppliersByItemFieldGroup.supplierColumns,
       qualifier = null;

  const SuppliersByItemField.component(
    this.label, {
    this.onByDefault = false,
    this.qualifier,
  }) : group = SuppliersByItemFieldGroup.component;

  const SuppliersByItemField.visible(this.group, this.label)
    : onByDefault = true,
      qualifier = null;

  final SuppliersByItemFieldGroup group;
  final String label;
  final bool onByDefault;
  final String? qualifier;

  String? get column => switch (this) {
    itemName || componentName => 'item_name',
    itemSupplierCount || componentSupplierCount => 'supplier_count',
    itemBalance || componentBalance => 'balance_qty',
    itemStockUom || supplierStockUom || componentStockUom => 'stock_uom',
    itemProjected || componentProjected => 'projected_qty',
    itemReorderLevel => 'reorder_level',
    itemReorderQty => 'reorder_qty',
    itemOpenOrders ||
    supplierOpenOrders ||
    itemOpenPoBadge ||
    supplierOpenPoBadge => 'open_order_qty',
    itemDraftOrders ||
    supplierDraftOrders ||
    itemDraftPoBadge ||
    supplierDraftPoBadge => 'draft_order_qty',
    itemQtyReceived ||
    supplierQtyReceived ||
    supplierQtyReceivedColumn => 'total_qty_received',
    supplierStatus => 'supplier_status',
    supplierPartNumber => 'supplier_part_number',
    supplierSources => 'sources',
    supplierLastPurchase ||
    componentLastPurchase ||
    supplierLastBuyColumn => 'last_purchase_date',
    supplierLastPurchaseReceipt => 'last_purchase_receipt',
    supplierLastPo => 'last_po_date',
    supplierRate || supplierRateColumn => 'last_rate',
    supplierRateCurrency => 'currency',
    supplierRateUom => 'rate_uom',
    supplierRateSource => 'rate_source',
    supplierRateDate => 'rate_date',
    supplierRateDocument => 'rate_document',
    supplierLeadTime || supplierLeadTimeColumn => 'lead_time_days',
    supplierLeadTimeReceipts => 'lead_time_receipts',
    supplierPoCount => 'po_count',
    supplierReceiptCount => 'receipt_count',
    componentQtyPerUnit => 'bom_qty_per_unit',
    _ => null,
  };

  bool get fixed => switch (this) {
    itemName ||
    componentName ||
    supplierStatus ||
    itemBelowReorder ||
    componentManufacturing ||
    componentCycle ||
    componentDepthLimit ||
    componentMatchPath ||
    bomDefaultMarker ||
    bomDraftBadge ||
    treeDepthLabel => true,
    _ => false,
  };

  bool get movedToView => column == null && !fixed;
}

/// Supplier table columns in display order. Only [maxSupplierColumns] fit on a
/// phone, so the Fields sheet stops more from being switched on.
const supplierTableColumns = [
  SuppliersByItemField.supplierLastBuyColumn,
  SuppliersByItemField.supplierOpenPoBadge,
  SuppliersByItemField.supplierDraftPoBadge,
  SuppliersByItemField.supplierRateColumn,
  SuppliersByItemField.supplierLeadTimeColumn,
  SuppliersByItemField.supplierQtyReceivedColumn,
];
const maxSupplierColumns = 3;

class SuppliersByItemFieldVisibility {
  const SuppliersByItemFieldVisibility.defaults() : overrides = const {};

  SuppliersByItemFieldVisibility(Map<String, bool> overrides)
    : overrides = Map.unmodifiable({
        for (final entry in overrides.entries)
          if (_fieldsByName.containsKey(entry.key)) entry.key: entry.value,
      });

  static final _fieldsByName = SuppliersByItemField.values.asNameMap();
  final Map<String, bool> overrides;

  bool shows(SuppliersByItemField field) =>
      field.fixed || (overrides[field.name] ?? field.onByDefault);

  /// The supplier table's columns, capped at [maxSupplierColumns]. Draft Order
  /// Qty needs draft purchase orders to be included by the report filter.
  List<SuppliersByItemField> supplierColumns({required bool includeDrafts}) => [
    for (final field in supplierTableColumns)
      if (shows(field) &&
          (includeDrafts || field != SuppliersByItemField.supplierDraftPoBadge))
        field,
  ].take(maxSupplierColumns).toList();

  int get supplierColumnCount => supplierTableColumns.where(shows).length;

  SuppliersByItemFieldVisibility withField(
    SuppliersByItemField field,
    bool visible,
  ) {
    if (field.fixed) return this;
    final updated = Map<String, bool>.of(overrides);
    if (visible == field.onByDefault) {
      updated.remove(field.name);
    } else {
      updated[field.name] = visible;
    }
    return SuppliersByItemFieldVisibility(updated);
  }
}
