// ignore_for_file: lines_longer_than_80_chars

import 'batch_no_browse_delegate.dart';
import 'batch_no_field_delegate.dart';

/// Combined batch-field + Browse Batches contract.
///
/// This is the **primary interface** that [SharedBatchField] depends on.
/// Any controller that implements this interface can fully drive the batch
/// field widget, including the optional Browse Batches picker flow.
///
/// ## Composition
///
/// [BatchNoFieldWithBrowseDelegate] is the union of two narrower interfaces:
///
/// | Interface               | Responsibility                               |
/// |-------------------------|----------------------------------------------|
/// | [BatchNoFieldDelegate]  | Reactive state, text controller, validation  |
/// | [BatchNoBrowseDelegate] | Browse Batches picker flow                   |
///
/// Keeping them separate means a controller can implement
/// [BatchNoFieldDelegate] alone (no picker support) and still work with
/// the widget in non-picker mode.  Only when [BatchNoFieldWithBrowseDelegate]
/// is fully implemented does the picker button become active.
///
/// ## Adoption series — 7-commit plan
///
/// The refactor is phased to avoid breaking changes:
///
/// | Commit | Action                                                         |
/// |--------|----------------------------------------------------------------|
/// | 1      | Extract BatchNoFieldDelegate interface.                        |
/// | 2      | Extract BatchNoBrowseDelegate interface with ERPNext           |
/// |        | field-name Dartdoc (canonical Total Row + key names).         |
/// | 3      | Extract BatchNoFieldWithBrowseDelegate (this file).           |
/// | 4      | Dartdoc ERPNext field names + Total Row on                    |
/// |        | BatchWiseBalanceRow.fromMap and fromReportRow.                |
/// | 5      | Dartdoc Total Row discard chain reference on                  |
/// |        | BatchPickerController._fetch.                                 |
/// | 6      | Extract ValidatedBatchField widget +                          |
/// |        | BrowseBatchButton widget under shared/item_sheet/widgets/.    |
/// | 7      | SharedBatchField.c re-typed to BatchNoFieldWithBrowseDelegate |
/// |        | + ItemSheetControllerBase adopts interface with 4 overrides.  |
///
/// New DocType controllers (e.g. Material Request item sheet, Job Card)
/// can implement this interface directly without inheriting
/// [ItemSheetControllerBase].
///
/// ## BatchNoFieldDelegate-only path (non-picker mode)
///
/// A lightweight controller that does NOT need Browse Batches support can
/// implement [BatchNoFieldDelegate] directly.  The call site simply omits
/// the [onPickerTap] callback when constructing [SharedBatchField], which
/// suppresses the picker button:
///
/// ```dart
/// class LightweightBatchController extends GetxController
///     implements BatchNoFieldDelegate {
///   @override final isBatchValid      = false.obs;
///   @override final isValidatingBatch = false.obs;
///   @override final isBatchReadOnly   = false.obs;
///   @override final batchError        = RxString('');
///   @override final batchInfoTooltip  = RxnString(null);
///   @override final batchController   = TextEditingController();
///
///   @override double batchBalanceFor(String batchNo) => _balance;
///   @override void   resetBatch()                    { /* ... */ }
///   @override Future<void> validateBatch(String batchNo) async { /* ... */ }
/// }
///
/// // In the sheet — no picker button shown because c does not implement
/// // BatchNoBrowseDelegate:
/// SharedBatchField(c: lightweightController, accentColor: Colors.teal, ...)
/// ```
///
/// To enable the picker button, upgrade to [BatchNoFieldWithBrowseDelegate].
///
/// ## Post-pick responsibility
///
/// [handleBatchPicked] is the standard hook for DocType-owned post-selection
/// logic.  [ItemSheetControllerBase] will supply a default implementation
/// (Commit 7) that writes [batchNo] into `batchController` and calls
/// `validateBatch`.  DocTypes with divergent post-pick behaviour override
/// this method.
///
/// [SharedBatchField] does **not** call [handleBatchPicked] itself.  The
/// widget fires `onPickerTap` (a callback), and the DocType-owned sheet
/// orchestrator decides when and how to call [handleBatchPicked].
///
/// ## ERPNext field names (delegated to BatchNoBrowseDelegate)
///
/// The canonical Dartdoc for ERPNext Batch-Wise Balance History field names
/// (`"batch"`, `"balance_qty"`, `"item"`) and the Total Row discard
/// invariant lives on [BatchNoBrowseDelegate].  See that file for the
/// full cross-file reference table.
///
/// ## Changelog
///
/// Commit 3 of 7 — Extract BatchNoFieldWithBrowseDelegate:
///   • New file.  Mirrors RackFieldWithBrowseDelegate in structure and
///     Dartdoc conventions.
///   • Adds handleBatchPicked — declared on the interface to prevent
///     silent no-ops in future lightweight controllers.
///   • Documents the full 7-commit adoption series.
///   • No existing files modified.  No call sites changed.
abstract interface class BatchNoFieldWithBrowseDelegate
    implements BatchNoFieldDelegate, BatchNoBrowseDelegate {
  /// Standard post-selection hook.
  ///
  /// Called by the DocType orchestrator after [browseBatches] returns a
  /// non-null batch number.  The default implementation supplied by
  /// [ItemSheetControllerBase] (Commit 7) writes [batchNo] into
  /// `batchController` and calls `validateBatch`.
  ///
  /// Override in the concrete controller to apply DocType-specific
  /// post-pick behaviour before or after calling the default logic.
  ///
  /// ## Why this is on the interface (not just the base class)
  ///
  /// Declaring it here means any controller that implements this interface
  /// — including ones that do not extend [ItemSheetControllerBase] — must
  /// explicitly decide what happens after a batch is picked.  This
  /// prevents silent no-ops in future lightweight DocType controllers.
  ///
  /// ## Contrast with RackFieldWithBrowseDelegate
  ///
  /// [RackFieldWithBrowseDelegate.handleRackPicked] receives a
  /// [RackPickerResult] (an object) because rack selection may carry extra
  /// metadata.  [handleBatchPicked] receives a plain [String] because
  /// batch selection carries only one meaningful value: the batch number.
  Future<void> handleBatchPicked(String batchNo);
}
