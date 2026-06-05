// Re-export shim — kept so that any remaining import of this path continues
// to compile. The live implementation is now inlined into
// PurchaseReceiptFormController._openItemSheet via UniversalItemFormSheet.
//
// Phase 3 Step 3.1: All sheet content migrated to UniversalItemFormSheet.
// This file is intentionally minimal; do not add logic here.
export 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart'
    show UniversalItemFormSheet;
