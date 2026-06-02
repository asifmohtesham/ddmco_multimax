/// Project-wide string constants.
///
/// Centralises GetX registration tags, route arguments keys, and any other
/// literal strings that are referenced from more than one file, preventing
/// silent runtime mismatches from typos.
library app_constants;

// ── GetX controller tags ────────────────────────────────────────────────────

/// Tag used to register and locate [PurchaseOrderItemFormController] inside
/// the Purchase Order item-sheet lifecycle.
///
/// Must match in every [Get.lazyPut], [Get.find], and [Get.delete] call that
/// targets this controller.
const String kPoItemSheetTag = 'po_item_sheet';
