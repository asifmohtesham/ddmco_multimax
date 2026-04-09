/// Enumerates every field slot inside an [ItemFormSheet] that can receive
/// a barcode scan from [DataWedgeService] or [ScanService].
///
/// [BarcodeAwareMixin] uses this enum to drive the 3-level routing priority
/// chain inside [BarcodeAwareMixin.onBarcodeScanned]:
///
/// ## Priority chain (highest → lowest)
/// 1. Focused field — the scope whose [FocusNode] currently has primary focus.
/// 2. First unfilled field — determined by walking [activeScanScopes] in
///    declaration order.
/// 3. Fallback — overwrites [activeScanScopes.first] when all fields are filled.
///
/// ## Adding a new scannable field
/// 1. Add a value here.
/// 2. Register its [FocusNode] in [ItemSheetControllerBase] (or on the
///    concrete controller for DocType-specific fields).
/// 3. Wire the [FocusNode] listener in the field widget.
/// 4. Add the value to the concrete controller's [activeScanScopes] list.
///
/// No other files need to change.
enum ScanScope {
  /// Primary Item Code / barcode field.  This is the default and reset
  /// state; every DocType supports scanning an item barcode.
  itemBarcode,

  /// Batch No field.  Active only when [ItemSheetControllerBase.requiresBatch]
  /// is true for the current item.
  batchNo,

  /// Source rack — or the single rack field for DocTypes that have only one
  /// rack (Delivery Note, Purchase Receipt, etc.).
  sourceRack,

  /// Target rack field, used exclusively by Stock Entry when
  /// [DualRackDelegate] is active (e.g. Material Transfer entries).
  targetRack,
}
