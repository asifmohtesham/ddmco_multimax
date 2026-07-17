typedef PermEntry = ({String doctype, String permType});

// Top-level drawer items (outside any _ModuleGroup)
const List<PermEntry> kTopLevelPermissions = [
  (doctype: 'ToDo', permType: 'read'),
  (doctype: 'ToDo', permType: 'create'), // New ToDo FAB
  (doctype: 'ToDo', permType: 'write'),  // ToDo Edit / Close / Delete
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
  (doctype: 'Item',             permType: 'write'),  // Item Re-order rules editing
  (doctype: 'Stock Entry',      permType: 'report'), // Stock Balance report
  // Gate the create/edit affordances so they resolve at login (no on-screen
  // delay). create+write for one doctype share a single getdoctype fetch.
  (doctype: 'Material Request', permType: 'create'), // New MR FAB
  (doctype: 'Material Request', permType: 'write'),  // MR Delete / Edit
  (doctype: 'Packing Slip',     permType: 'create'), // New PS FAB
  (doctype: 'Packing Slip',     permType: 'write'),  // PS Edit
  (doctype: 'Stock Entry',      permType: 'create'), // New Stock Entry FAB
  (doctype: 'Stock Entry',      permType: 'write'),  // Stock Entry Edit
  (doctype: 'Delivery Note',    permType: 'create'), // New Delivery Note FAB
  (doctype: 'Delivery Note',    permType: 'write'),  // Delivery Note Edit
];

const List<PermEntry> kBuyingPermissions = [
  (doctype: 'Purchase Order',   permType: 'read'),
  (doctype: 'Purchase Receipt', permType: 'read'),
  (doctype: 'Purchase Order',   permType: 'create'), // New Purchase Order FAB
  (doctype: 'Purchase Order',   permType: 'write'),  // Purchase Order Edit
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
  (doctype: 'POS Upload', permType: 'report'), // POS & DN Item Rate report
];

const List<PermEntry> kAppPermissions = [
  ...kTopLevelPermissions,
  ...kStockPermissions,
  ...kBuyingPermissions,
  ...kManufacturingPermissions,
  ...kSellingPermissions,
];
