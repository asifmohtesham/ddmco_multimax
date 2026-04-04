// ignore_for_file: lines_longer_than_80_chars

/// Browse-batch capability contract.
///
/// A controller that implements this interface can open the shared
/// [BatchPickerSheet] and return the user's selection as a plain [String]
/// (the selected batch number).
///
/// ## Responsibility boundary
///
/// This interface owns **only the browse flow**:
/// - Checking pre-conditions ([canBrowseBatches]).
/// - Opening the picker sheet ([browseBatches]).
/// - Returning the selection result.
///
/// It does **not** write into any form field.  Post-selection handling
/// (writing to `batchController`, triggering [validateBatch]) is the
/// **calling DocType's responsibility** via [handleBatchPicked] on
/// [BatchNoFieldWithBrowseDelegate].  This boundary is intentional:
/// different DocTypes may have different post-pick validation flows and
/// may map the selected batch to different form fields.
///
/// ## Data source — Batch-Wise Balance History
///
/// [browseBatches] populates the picker from the ERPNext
/// **Batch-Wise Balance History** report.  The following field-name
/// facts are documented here as the **canonical cross-file reference**
/// for every class in this browse flow:
///
/// | ERPNext column key | Dart mapping                                  |
/// |--------------------|-----------------------------------------------|
/// | `"batch"`          | `BatchWiseBalanceRow.batchNo` — the batch     |
/// |                    | number identifier shown in the picker list    |
/// | `"balance_qty"`    | `BatchWiseBalanceRow.balanceQty` — available  |
/// |                    | stock qty shown in the balance chip           |
/// | `"item"`           | Item Code — used as a **server-side filter**  |
/// |                    | parameter; NOT stored on the row model        |
///
/// These keys are consumed by `BatchWiseBalanceRow.fromMap` and
/// `BatchWiseBalanceRow.fromReportRow` in `batch_wise_balance_row.dart`.
/// `ApiProvider.getBatchWiseBalance` reads them from the raw report
/// response.
///
/// ## Total Row — MUST be discarded
///
/// The Batch-Wise Balance History report **always appends a Total Row as
/// its last entry**.  This row is a report-footer aggregate — it is NOT
/// a real batch record and must **never** be exposed as a selectable
/// option in the picker.
///
/// `ApiProvider.getBatchWiseBalance` is responsible for discarding this
/// row before returning results to [BatchPickerController].  This
/// contract documents the invariant here for cross-file traceability:
/// any future implementation of [browseBatches] that bypasses the shared
/// API helper **must** replicate the Total Row discard.
///
/// The canonical discard guard is:
/// ```dart
/// // Discard the last row — it is the Total Row footer from
/// // Batch-Wise Balance History, not a real batch record.
/// if (rows.isNotEmpty) rows.removeLast();
/// ```
///
/// See also [BatchPickerController._fetch] for the enforcement-point
/// comment that cross-references this invariant.
///
/// ## Pre-conditions
///
/// Implementations must check [canBrowseBatches] before opening the sheet.
/// Typical pre-conditions:
///   - `itemCode` is non-empty.
///   - `resolvedWarehouse` is known, or the caller accepts
///     warehouse-agnostic results.
///
/// ## Return type rationale
///
/// [browseBatches] returns `Future<String?>` (plain batch number) rather
/// than a result object.  Batch selection carries only one meaningful
/// value: the batch number.  Contrast with [RackBrowseDelegate.browseRacks]
/// which returns a [RackPickerResult] because rack selection may carry
/// extra metadata (balance, rack ID vs display name, etc.).
///
/// Post-selection handling is performed by
/// [BatchNoFieldWithBrowseDelegate.handleBatchPicked].
///
/// ## Usage example
///
/// ```dart
/// // In the DocType controller — implement BatchNoFieldWithBrowseDelegate
/// // (which extends both BatchNoFieldDelegate and BatchNoBrowseDelegate):
/// class MyController extends GetxController
///     implements BatchNoFieldWithBrowseDelegate {
///
///   @override
///   bool get canBrowseBatches => itemCode.value.isNotEmpty;
///
///   @override
///   Future<String?> browseBatches() async {
///     if (!canBrowseBatches) return null;
///     return showBatchPickerSheet(
///       Get.context!,
///       itemCode:    itemCode.value,
///       warehouse:   resolvedWarehouse,
///       accentColor: accentColor,
///     );
///   }
///
///   // handleBatchPicked is the canonical post-pick hook.
///   // ItemSheetControllerBase supplies a default implementation that
///   // writes batchNo into batchController and calls validateBatch().
///   // Override when DocType-specific post-pick logic is required:
///   @override
///   Future<void> handleBatchPicked(String batchNo) async {
///     batchController.text = batchNo;
///     await validateBatch(batchNo);
///     // DocType-specific extra logic here…
///   }
/// }
///
/// // In the sheet orchestrator — call handleBatchPicked after browseBatches:
/// final batchNo = await controller.browseBatches();
/// if (batchNo != null) await controller.handleBatchPicked(batchNo);
/// ```
///
/// ## Changelog
///
/// Commit 2 of 7 — Extract BatchNoBrowseDelegate:
///   • New file.  Mirrors RackBrowseDelegate in structure and Dartdoc
///     conventions.
///   • Carries canonical ERPNext field-name and Total Row Dartdoc.
///   • No existing files modified.  No call sites changed.
abstract interface class BatchNoBrowseDelegate {
  /// Whether the controller currently satisfies the pre-conditions required
  /// to open the batch picker.
  ///
  /// When `false`, the picker button in [ValidatedBatchField] must be
  /// disabled or hidden.  Implementations must not rely on the widget to
  /// guard calls to [browseBatches] — callers may invoke [browseBatches]
  /// directly (e.g. from a test or an alternative UI path).
  bool get canBrowseBatches;

  /// Opens the shared batch picker and returns the selected batch number,
  /// or `null` if the user dismissed the sheet without a selection.
  ///
  /// ## ERPNext field names (Batch-Wise Balance History)
  ///
  /// The underlying report returns rows keyed by:
  ///   - `"batch"`       → the batch identifier shown in the picker list
  ///   - `"balance_qty"` → the available qty shown in the balance chip
  ///   - `"item"`        → the item code filter applied server-side
  ///
  /// See [BatchNoBrowseDelegate] class-level doc for the full field-name
  /// reference table.
  ///
  /// ## Total Row — MUST be discarded
  ///
  /// The report **always** appends a Total Row as the last entry.
  /// Implementations must ensure it is discarded before passing rows to
  /// the picker.  The canonical discard guard and cross-file traceability
  /// chain are documented on [BatchNoBrowseDelegate] (class level).
  ///
  /// ## Return contract
  ///
  /// Returns a plain [String?] (not a result object) because a batch
  /// selection carries only one meaningful value: the batch number.
  /// Post-selection handling is performed by
  /// [BatchNoFieldWithBrowseDelegate.handleBatchPicked].
  ///
  /// ## Concurrency
  ///
  /// Implementations should guard against re-entrant calls (e.g. two
  /// rapid taps opening two sheets).  A simple [isValidatingBatch] check
  /// is sufficient in most cases.
  Future<String?> browseBatches();
}
