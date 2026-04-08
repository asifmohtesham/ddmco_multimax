/// Enumerates every field slot inside an [ItemFormSheet] that can receive
/// a barcode scan from [DataWedgeService] or [ScanService].
///
/// [BarcodeAwareMixin] exposes an `activeScanScope` reactive field of this
/// type on every [ItemSheetControllerBase] subclass.  When a [FocusNode]
/// fires (Commit 4), the corresponding scope value is written so that the
/// next incoming scan is routed to the correct [TextEditingController]
/// without ad-hoc if/else chains inside each DocType controller.
///
/// ## Priority chain (highest → lowest)
/// 1. Focused field — the scope whose [FocusNode] currently has primary focus.
/// 2. First unfilled field — determined by [BarcodeAwareMixin.onBarcodeScanned]
///    walking [activeScanScopes] in declaration order.
/// 3. [itemCode] fallback — always safe when nothing else matches.
///
/// ## Adding a new scannable field
/// 1. Add a value here.
/// 2. Register its [FocusNode] in [ItemSheetControllerBase] (Commit 2).
/// 3. Wire the [FocusNode] listener in the field widget (Commit 4).
/// 4. Add the value to the concrete controller's [activeScanScopes] set.
///
/// No other files need to change.
enum ScanScope {
  /// Primary Item Code field.  This is the default and reset state; every
  /// DocType supports scanning an item code.
  itemCode,

  /// Batch No field.  Active only when [ItemSheetControllerBase.requiresBatch]
  /// is true for the current item.
  batch,

  /// Source rack — or the single rack field for DocTypes that have only one
  /// rack (Delivery Note, Purchase Receipt, etc.).
  sourceRack,

  /// Target rack field, used exclusively by Stock Entry when
  /// [DualRackDelegate] is active (e.g. Material Transfer entries).
  targetRack,
}
