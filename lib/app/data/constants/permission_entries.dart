typedef PermEntry = ({String doctype, String permType});

// Top-level drawer items (outside any _ModuleGroup)
const List<PermEntry> kTopLevelPermissions = [
  (doctype: 'ToDo', permType: 'read'),
];

const List<PermEntry> kStockPermissions = [
  (doctype: 'Item',             permType: 'read'),
  (doctype: 'Batch',            permType: 'read'),
  (doctype: 'Material Request', permType: 'read'),
  (doctype: 'Stock Entry',      permType: 'read'),
  (doctype: 'Delivery Note',    permType: 'read'),
  (doctype: 'Packing Slip',     permType: 'read'),
  (doctype: 'Batch',            permType: 'report'), // Batch-Wise Balance History report
  (doctype: 'Item',             permType: 'report'), // Item Variant Details report
  (doctype: 'Stock Entry',      permType: 'report'), // Stock Balance report
];

const List<PermEntry> kBuyingPermissions = [
  (doctype: 'Purchase Order',   permType: 'read'),
  (doctype: 'Purchase Receipt', permType: 'read'),
];

const List<PermEntry> kManufacturingPermissions = [
  (doctype: 'BOM',       permType: 'read'),
  (doctype: 'Work Order', permType: 'read'),
  (doctype: 'Job Card',  permType: 'read'),
  (doctype: 'BOM',       permType: 'report'), // BOM Search report
  (doctype: 'Job Card',  permType: 'report'), // Job Card Summary report
];

const List<PermEntry> kSellingPermissions = [
  (doctype: 'POS Upload', permType: 'read'),
];

const List<PermEntry> kAppPermissions = [
  ...kTopLevelPermissions,
  ...kStockPermissions,
  ...kBuyingPermissions,
  ...kManufacturingPermissions,
  ...kSellingPermissions,
];
