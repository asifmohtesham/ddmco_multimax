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
class BatchPickerController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  final String  itemCode;
  final String? warehouse;

  /// Optional pre-fetched rows. When non-empty, [onInit] skips the network
  /// fetch and seeds [_allRows] directly.
  final List<BatchWiseBalanceRow> preloadedRows;

  BatchPickerController({
    required this.itemCode,
    this.warehouse,
    this.preloadedRows = const [],
  });

  // ── State ──────────────────────────────────────────────────────────────
  final isLoading    = true.obs;
  final errorMessage = RxnString();
  final _allRows     = <BatchWiseBalanceRow>[].obs;
  final searchQuery  = ''.obs;

  // ── Computed filtered list ─────────────────────────────────────────────
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
