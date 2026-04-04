import 'dart:developer';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/batch_wise_balance_row.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

/// Drives [BatchPickerSheet].
///
/// Lifecycle: created with a unique [tag] (item code + warehouse hash) so
/// multiple concurrent pickers never share state. The sheet calls
/// [Get.delete<BatchPickerController>(tag: tag)] on close.
///
/// ## Pre-fetched data (zero-latency open)
///
/// Pass [preloadedRows] when the caller already holds fresh batch data (e.g.
/// [StockEntryItemFormController.batchWiseHistory]). When non-empty the
/// controller seeds [_allRows] immediately, sets [isLoading] = false and
/// **skips the network fetch entirely** — the picker opens instantly.
///
/// When [preloadedRows] is empty or null the controller falls back to its own
/// [_fetch] call so the sheet is always self-sufficient.
///
/// ## Total Row — discard chain
///
/// The Batch-Wise Balance History report always appends a Total Row as its
/// last entry.  This controller **never** receives that row — it is
/// discarded upstream before rows reach [_allRows].  The two paths are:
///
/// - **Network path** ([_fetch]): [ApiProvider.fetchBatchesForItem] discards
///   the Total Row before returning.  See [_fetch] inline comment.
/// - **Preload path** ([preloadedRows]): the producing controller
///   (e.g. [ItemSheetControllerBase]) discards the Total Row when it
///   builds its cached `batchWiseHistory` list.
///
/// The canonical invariant contract and discard guard snippet live on
/// [BatchNoBrowseDelegate].  Do NOT add discard logic inside this
/// controller — it would be a double-discard on the network path and has
/// no effect on the preload path (already stripped).
class BatchPickerController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  final String  itemCode;
  final String? warehouse;

  /// Optional pre-fetched rows. When non-empty, [onInit] skips the network
  /// fetch and seeds [_allRows] directly.
  ///
  /// ## Total Row — already stripped
  ///
  /// Rows in this list have already had the Total Row footer removed by
  /// the producing controller before being passed here.  No further
  /// discard is needed.  See [BatchNoBrowseDelegate] for the canonical
  /// invariant and [_fetch] for the network-path enforcement point.
  final List<BatchWiseBalanceRow> preloadedRows;

  BatchPickerController({
    required this.itemCode,
    this.warehouse,
    this.preloadedRows = const [],
  });

  // ── State ────────────────────────────────────────────────────────────────────────
  final isLoading    = true.obs;
  final errorMessage = RxnString();
  final _allRows     = <BatchWiseBalanceRow>[].obs;
  final searchQuery  = ''.obs;

  // ── Computed filtered list ────────────────────────────────────────────────────
  List<BatchWiseBalanceRow> get filtered {
    final q = searchQuery.value.trim().toLowerCase();
    if (q.isEmpty) return _allRows;
    return _allRows
        .where((r) => r.batchNo.toLowerCase().contains(q))
        .toList();
  }

  @override
  void onInit() {
    super.onInit();
    if (preloadedRows.isNotEmpty) {
      // Seed from pre-fetched data — no network call needed.
      // Total Row has already been stripped by the producing controller.
      // See [BatchNoBrowseDelegate] for the canonical discard invariant.
      _allRows.assignAll(preloadedRows);
      isLoading.value = false;
      log('[BatchPicker] seeded ${preloadedRows.length} pre-fetched rows '
          'for $itemCode @ ${warehouse ?? "any"}',
          name: 'BatchPicker');
    } else {
      // Fallback: fetch from server (covers direct instantiation / retry).
      _fetch();
    }
  }

  Future<void> _fetch() async {
    isLoading.value    = true;
    errorMessage.value = null;
    try {
      // [ApiProvider.fetchBatchesForItem] returns rows already stripped of
      // the Total Row footer from Batch-Wise Balance History.  The raw
      // report always appends a Total Row as its last entry (keyed
      // `"batch"` = '', `"balance_qty"` = aggregate sum, `"item"` = item
      // code); that row is discarded inside ApiProvider before being
      // returned here.
      //
      // Do NOT add discard logic here — the invariant is owned by
      // [BatchNoBrowseDelegate] and enforced at the ApiProvider layer.
      // Adding it here would be a double-discard that silently removes a
      // real batch row when the report changes its footer behaviour.
      final rows = await _api.fetchBatchesForItem(
        itemCode,
        warehouse: warehouse,
      );
      _allRows.assignAll(rows);
    } catch (e) {
      errorMessage.value = 'Failed to load batches. Tap to retry.';
      log('[BatchPicker] fetch error: $e', name: 'BatchPicker');
    } finally {
      isLoading.value = false;
    }
  }

  void retry() => _fetch();
}
