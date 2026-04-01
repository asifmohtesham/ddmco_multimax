import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/models/batch_model.dart';
import 'package:multimax/app/data/providers/batch_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

/// GetX controller for the **Batch list** screen.
///
/// Responsibilities:
/// - Owns the [ScrollController] so [BatchScreen] stays stateless.
/// - Manages lazy pagination: page cursor advances on each successful
///   [fetchBatches] call; [hasMore] gates further loads.
/// - Debounces search input (500 ms) via [onSearchChanged].
/// - Exposes [activeFilters] as an [RxMap] so [DocTypeListHeader] and
///   [BatchFilterBottomSheet] can subscribe to the same reactive stream.
/// - Holds expansion state for the inline detail row ([toggleExpand]).
class BatchController extends GetxController {
  final BatchProvider _provider = Get.find<BatchProvider>();

  /// Exposed so widgets (e.g. [BatchFilterBottomSheet]) can call provider
  /// search helpers without a second [Get.find] registration.
  BatchProvider get batchProvider => _provider;

  // ── Scroll ────────────────────────────────────────────────────────────

  /// Owned by the controller so [BatchScreen] needs no [StatefulWidget].
  /// Listener is attached in [onInit] and cleaned up in [onClose].
  final scrollController = ScrollController();

  // ── List state ────────────────────────────────────────────────────────

  /// The currently loaded [Batch] items.
  var batches = <Batch>[].obs;

  /// `true` during the initial (non-paginated) fetch.
  var isLoading = true.obs;

  /// `true` while an incremental page load is in flight.
  var isFetchingMore = false.obs;

  /// `false` once a fetch returns fewer items than [_limit], signalling
  /// that no further pages exist.
  var hasMore = true.obs;

  // ── Expansion ──────────────────────────────────────────────────────────

  /// Name of the currently expanded batch row, or `''` when collapsed.
  var expandedBatchName = ''.obs;

  /// `true` while [_fetchVariantDetails] is in flight.
  var isLoadingDetails = false.obs;

  /// Cache of `item → variant_of` strings fetched from the Item master.
  /// Prevents duplicate API calls when the same item appears multiple times.
  var itemVariants = <String, String>{}.obs;

  // ── Pagination ──────────────────────────────────────────────────────────
  final int _limit = 20;
  int _currentPage = 0;

  // ── Search ────────────────────────────────────────────────────────────

  /// Current search query string.  Mutated by [onSearchChanged] and
  /// cleared by [clearFilters] / the search-bar clear button.
  var searchQuery = ''.obs;

  // ── Filters ───────────────────────────────────────────────────────────

  /// Active filters keyed by Frappe field name.
  ///
  /// Supported keys:
  ///   `'item'`                  → `String` (exact match)
  ///   `'name'`                  → `String` (LIKE `%value%`)
  ///   `'custom_purchase_order'` → `String` (exact match)
  ///   `'custom_supplier_name'`  → `String` (exact match)
  ///   `'disabled'`              → `int` (0 = active only, 1 = disabled only)
  ///   `'expiry_date'`           → `List` `['between', [isoFrom, isoTo]]`
  var activeFilters = <String, dynamic>{}.obs;

  // ── Sort ──────────────────────────────────────────────────────────────

  /// Frappe field name to sort by. Defaults to `'modified'`.
  var sortField = 'modified'.obs;

  /// Sort direction: `'asc'` or `'desc'`. Defaults to `'desc'`.
  var sortOrder = 'desc'.obs;

  // ── Derived ────────────────────────────────────────────────────────────

  /// Total number of active constraints shown in the filter badge.
  /// Includes both [activeFilters] entries and a non-empty [searchQuery].
  int get filterCount =>
      activeFilters.length + (searchQuery.value.isNotEmpty ? 1 : 0);

  // ── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
  }

  @override
  void onReady() {
    super.onReady();
    // onReady fires after the first frame, so the screen is fully mounted.
    // Fetching here (rather than onInit) ensures the list always refreshes
    // when the screen is navigated to, even if the controller is kept alive
    // across navigations by lazyPut.
    fetchBatches();
  }

  @override
  void onClose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    super.onClose();
  }

  // ── Scroll handler ───────────────────────────────────────────────────────

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final atBottom = scrollController.offset >=
        scrollController.position.maxScrollExtent * 0.9;
    if (atBottom && hasMore.value && !isFetchingMore.value) {
      fetchBatches(isLoadMore: true);
    }
  }

  // ── Fetch ──────────────────────────────────────────────────────────────

  /// Loads (or appends) batches from ERPNext.
  ///
  /// - [isLoadMore]: when `true`, appends the next page to [batches].
  ///   When `false` (default), resets the list and fetches from page 0.
  /// - [clear]: accepted for call-site symmetry (e.g. filter/search
  ///   callbacks) but has no additional effect beyond `isLoadMore: false`
  ///   behaviour — both paths reset state identically.
  Future<void> fetchBatches(
      {bool isLoadMore = false, bool clear = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      batches.clear();
      _currentPage = 0;
      hasMore.value = true;
      expandedBatchName.value = '';
    }

    try {
      final filters = _buildFilters();
      final orderBy = '${sortField.value} ${sortOrder.value}';

      final response = await _provider.getBatches(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: filters,
        orderBy: orderBy,
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newBatches = data.map((json) => Batch.fromJson(json)).toList();

        if (newBatches.length < _limit) hasMore.value = false;

        if (isLoadMore) {
          batches.addAll(newBatches);
        } else {
          batches.value = newBatches;
        }
        _currentPage++;
      }
    } catch (e) {
      AppNotification.error('Failed to fetch batches: $e');
    } finally {
      isLoading.value = false;
      isFetchingMore.value = false;
    }
  }

  Map<String, dynamic> _buildFilters() {
    final filters = <String, dynamic>{};

    if (searchQuery.value.isNotEmpty) {
      filters['name'] = ['like', '%${searchQuery.value}%'];
    }

    activeFilters.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.isEmpty) return;
      filters[key] = value;
    });

    return filters;
  }

  // ── Search ────────────────────────────────────────────────────────────

  /// Debounced search: waits 500 ms after the last keystroke before
  /// triggering [fetchBatches].  Ignores the delayed callback if the
  /// query has changed in the interim.
  void onSearchChanged(String val) {
    searchQuery.value = val;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (searchQuery.value == val) fetchBatches(clear: true);
    });
  }

  // ── Filter API ──────────────────────────────────────────────────────────

  /// Replaces [activeFilters] with [filters] and refreshes the list.
  /// Called by [BatchFilterBottomSheet] on apply.
  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = Map.from(filters);
    fetchBatches(clear: true);
  }

  /// Clears all active filters, search query, and sort state, then
  /// refreshes the list.
  void clearFilters() {
    activeFilters.clear();
    searchQuery.value = '';
    sortField.value = 'modified';
    sortOrder.value = 'desc';
    fetchBatches(clear: true);
  }

  /// Removes a single filter by [key] and refreshes the list.
  /// Used by the chip row delete buttons in [BatchListAppBar].
  void removeFilter(String key) {
    activeFilters.remove(key);
    fetchBatches(clear: true);
  }

  /// Updates [sortField] and [sortOrder], then refreshes the list.
  void setSort(String field, String order) {
    sortField.value = field;
    sortOrder.value = order;
    fetchBatches(clear: true);
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  /// Navigates to [AppRoutes.BATCH_FORM].
  ///
  /// - Omit [name] (or pass `null`) to open a blank **new** form.
  /// - Pass a batch name to open in **edit** mode.
  ///
  /// Refreshes the list when the form route pops.
  void openBatchForm([String? name]) {
    Get.toNamed(
      AppRoutes.BATCH_FORM,
      arguments: {
        'name': name ?? '',
        'mode': name != null ? 'edit' : 'new',
      },
    )?.then((_) => fetchBatches(clear: true));
  }

  // ── Expansion ───────────────────────────────────────────────────────────

  /// Toggles the inline detail row for [batchName].
  ///
  /// Tapping an already-expanded row collapses it (sets
  /// [expandedBatchName] to `''`).  Tapping a different row collapses
  /// the previous one and expands the new one, fetching variant details
  /// if not yet cached in [itemVariants].
  void toggleExpand(String batchName) {
    if (expandedBatchName.value == batchName) {
      expandedBatchName.value = '';
    } else {
      expandedBatchName.value = batchName;
      _fetchVariantDetails(batchName);
    }
  }

  Future<void> _fetchVariantDetails(String batchName) async {
    final batch = batches.firstWhereOrNull((b) => b.name == batchName);
    if (batch == null || itemVariants.containsKey(batch.item)) return;

    isLoadingDetails.value = true;
    try {
      final response = await _provider.getItemDetails(batch.item);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final itemData = response.data['data'];
        final variantOf = itemData['variant_of'] ?? '';
        itemVariants[batch.item] =
            variantOf.isNotEmpty ? variantOf : 'N/A';
      }
    } catch (e) {
      itemVariants[batch.item] = 'Error';
    } finally {
      isLoadingDetails.value = false;
    }
  }
}
