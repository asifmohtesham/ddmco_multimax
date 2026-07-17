import 'package:multimax/app/data/models/item_model.dart';

/// Valid `Item Reorder.material_request_type` options in ERPNext version-15.
///
/// Note `Transfer`, not `Material Transfer` — the value is remapped to
/// `Material Transfer` server-side when the Material Request is created.
const List<String> kReorderMaterialRequestTypes = [
  'Purchase',
  'Transfer',
  'Material Issue',
  'Manufacture',
];

/// The type a newly added reorder row should start with.
///
/// Mirrors erpnext item.js:292-298, which seeds the row from the Item's
/// `default_material_request_type`, remapping `Material Transfer` → `Transfer`.
///
/// **Deliberate deviation from v15:** `Item.default_material_request_type` also
/// offers `Customer Provided`, which is *not* a valid `Item Reorder` option.
/// Desk copies it verbatim and produces a row carrying an invalid Select value.
/// Here an unmappable default returns `''` so the user must choose explicitly.
String defaultReorderTypeFor(String? itemDefaultMaterialRequestType) {
  final t = itemDefaultMaterialRequestType;
  if (t == null || t.isEmpty) return '';
  final mapped = t == 'Material Transfer' ? 'Transfer' : t;
  return kReorderMaterialRequestTypes.contains(mapped) ? mapped : '';
}

/// Client-side mirror of `validate_warehouse_for_reorder`
/// (erpnext item.py:497-534) for the checks evaluable without the warehouse
/// tree. Returns the first error message, or null when [rows] are valid.
///
/// **Not checked here:** that `warehouse` is a descendant of `warehouse_group`
/// (item.py:523-534). That needs the warehouse tree; the server is the
/// authority and its message is already specific, so it is surfaced verbatim
/// from the save response instead.
String? validateReorderRows(List<ItemReorder> rows) {
  final seen = <String>{};

  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final rowNo = i + 1;

    if (r.warehouse.trim().isEmpty) {
      return 'Row #$rowNo: Please select a warehouse in "Request for"';
    }
    if (r.materialRequestType.trim().isEmpty) {
      return 'Row #$rowNo: Please set the material request type';
    }

    // item.py:510-518 — uniqueness is the (warehouse, type) TUPLE. Two rows
    // for one warehouse with different types are legal.
    final key = '${r.warehouse}|${r.materialRequestType}';
    if (!seen.add(key)) {
      return 'Row #$rowNo: A reorder entry already exists for warehouse '
          '${r.warehouse} with reorder type ${r.materialRequestType}.';
    }

    // item.py:520-521 — one-directional: qty-without-level is allowed.
    if (r.warehouseReorderLevel != 0 && r.warehouseReorderQty == 0) {
      return 'Row #$rowNo: Please set reorder quantity';
    }
  }

  return null;
}
