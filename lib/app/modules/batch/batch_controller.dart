import 'package:get/get.dart';
import 'package:multimax/app/data/models/batch_model.dart';
import 'package:multimax/app/data/providers/batch_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class BatchController extends GetxController {
  final BatchProvider _provider = Get.find<BatchProvider>();

  /// Exposed so widgets (e.g. BatchFilterBottomSheet) can call provider
  /// search helpers without a second Get.find registration.
  BatchProvider get batchProvider => _provider;

  // ── List state ─────────────────────────────────────────────────────────────
  var batches = <Batch>[].obs;
  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;

  // ── Expansion ──────────────────────────────────────────────────────────────
  var expandedBatchName = ''.obs;
  var isLoadingDetails = false.obs;
  var itemVariants = <String, String>{}.obs;

  // ── Pagination ────────────────────────────────────────────────────────────
  final int _limit = 20;
  int _currentPage = 0;

  // ── Search ────────────────────────────────────────────────────────────────
  var searchQuery = ''.obs;

  // ── Filters ───────────────────────────────────────────────────────────────
  /// Active filters keyed by Frappe field name.
  /// Supported keys:
  ///   'item'                  → String (exact)
  ///   'name'                  → String (like)
  ///   'custom_purchase_order' → String (exact)
  ///   'custom_supplier'       → String (exact)
  ///   'disabled'              → int (0 = active, 1 = disabled)
  ///   'expiry_date'           → List ['between', [from, to]] (ISO dates)
  var activeFilters = <String, dynamic>{}.obs;

  // ── Sort ──────────────────────────────────────────────────────────────────
  var sortField = 'modified'.obs;
  var sortOrder = 'desc'.obs;

  // ── Derived ───────────────────────────────────────────────────────────────
  int get filterCount =>
      activeFilters.length + (searchQuery.value.isNotEmpty ? 1 : 0);

  @override
  void onInit() {
    super.onInit();
    fetchBatches();
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<void> fetchBatches(
      {bool isLoadMore = false, bool clear = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      if (clear) {
        batches.clear();
        _currentPage = 0;
        hasMore.value = true;
        expandedBatchName.value = '';
      }
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
        final newBatches =
            data.map((json) => Batch.fromJson(json)).toList();

        if (newBatches.length < _limit) hasMore.value = false;

        if (isLoadMore) {
          batches.addAll(newBatches);
        } else {
          batches.value = newBatches;
        }
        _currentPage++;
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to fetch batches: $e');
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

  // ── Search ────────────────────────────────────────────────────────────────

  void onSearchChanged(String val) {
    searchQuery.value = val;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (searchQuery.value == val) fetchBatches(clear: true);
    });
  }

  // ── Filter API ────────────────────────────────────────────────────────────

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = Map.from(filters);
    fetchBatches(clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    sortField.value = 'modified';
    sortOrder.value = 'desc';
    fetchBatches(clear: true);
  }

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetchBatches(clear: true);
  }

  void setSort(String field, String order) {
    sortField.value = field;
    sortOrder.value = order;
    fetchBatches(clear: true);
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void openBatchForm([String? name]) {
    Get.toNamed(
      AppRoutes.BATCH_FORM,
      arguments: {
        'name': name ?? '',
        'mode': name != null ? 'edit' : 'new',
      },
    )?.then((_) => fetchBatches(clear: true));
  }

  // ── Expansion ─────────────────────────────────────────────────────────────

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
