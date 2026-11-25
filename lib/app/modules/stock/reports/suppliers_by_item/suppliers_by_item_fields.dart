import 'package:multimax/app/data/utils/suppliers_by_item_labels.dart';

enum SuppliersByItemFieldGroup {
  item('Item rows'),
  supplier('Supplier rows'),
  component('BOM component rows'),
  bom('BOM and tree labels'),
  summary('Report summary'),
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
  itemTemplateContext.item('Variant Of', onByDefault: true),
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
  supplierLastBuyColumn.supplier(
    'Last Purchase Date',
    qualifier: 'Comparison column',
    onByDefault: true,
  ),
  supplierOpenPoBadge.supplier(
    SuppliersByItemColumnLabels.openOrderQty,
    qualifier: 'Badge',
    onByDefault: true,
  ),
  supplierDraftPoBadge.supplier(
    'Draft Order Qty',
    qualifier: 'Badge',
    onByDefault: true,
  ),
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
  summaryItemCount.visible(SuppliersByItemFieldGroup.summary, 'Items'),
  summarySupplierCount.visible(SuppliersByItemFieldGroup.summary, 'Suppliers'),
  summaryNoDirectCount.visible(
    SuppliersByItemFieldGroup.summary,
    SuppliersByItemColumnLabels.noSupplierRecorded,
  ),
  summaryStockByUom.visible(
    SuppliersByItemFieldGroup.summary,
    SuppliersByItemColumnLabels.balanceQty,
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
  );

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
}

class SuppliersByItemFieldVisibility {
  const SuppliersByItemFieldVisibility.defaults() : overrides = const {};

  SuppliersByItemFieldVisibility(Map<String, bool> overrides)
    : overrides = Map.unmodifiable(overrides);

  final Map<String, bool> overrides;

  bool shows(SuppliersByItemField field) =>
      overrides[field.name] ?? field.onByDefault;

  SuppliersByItemFieldVisibility withField(
    SuppliersByItemField field,
    bool visible,
  ) {
    final updated = Map<String, bool>.of(overrides);
    if (visible == field.onByDefault) {
      updated.remove(field.name);
    } else {
      updated[field.name] = visible;
    }
    return SuppliersByItemFieldVisibility(updated);
  }
}
