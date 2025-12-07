import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/stock_entry_model.dart';
import 'package:ddmco_multimax/app/data/providers/stock_entry_provider.dart';

class StockEntryController extends GetxController {
  final StockEntryProvider _provider = Get.find<StockEntryProvider>();

  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;
  var stockEntries = <StockEntry>[].obs;
  final int _limit = 20;
  int _currentPage = 0;

  var expandedEntryName = ''.obs;
  var isLoadingDetails = false.obs;
  final _detailedEntriesCache = <String, StockEntry>{}.obs;

  final activeFilters = <String, dynamic>{}.obs;

  // --- ADDED SORTING STATE ---
  var sortField = 'creation'.obs;
  var sortOrder = 'desc'.obs;

  StockEntry? get detailedEntry => _detailedEntriesCache[expandedEntryName.value];

  @override
  void onInit() {
    super.onInit();
    fetchStockEntries();
  }

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchStockEntries(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    fetchStockEntries(isLoadMore: false, clear: true);
  }

  // --- ADDED SET SORT METHOD ---
  void setSort(String field, String order) {
    sortField.value = field;
    sortOrder.value = order;
    fetchStockEntries(isLoadMore: false, clear: true);
  }

  Future<void> fetchStockEntries({bool isLoadMore = false, bool clear = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      if (clear) {
        stockEntries.clear();
        _currentPage = 0;
        hasMore.value = true;
      }
    }

    try {
      // --- UPDATED PROVIDER CALL TO INCLUDE SORTING ---
      // Note: You may need to update the Provider signature to accept orderBy if it doesn't already,
      // but ApiProvider's generic getDocumentList supports it.
      // Based on provided files, StockEntryProvider.getStockEntries needs to pass orderBy to ApiProvider.

      // Assuming StockEntryProvider forwards specific args or we might need to update Provider too.
      // Checking StockEntryProvider file... it wraps _apiProvider.getStockEntries.
      // ApiProvider.getStockEntries hardcodes orderBy 'modified desc' in the specific method,
      // BUT StockEntryProvider calls the generic `getDocumentList`.

      // Since StockEntryProvider.getStockEntries signature in uploaded files is:
      // getStockEntries({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters})
      // We cannot pass orderBy without updating the provider (see step below).
      // For now, assuming Provider update:

      final response = await _provider.getStockEntries(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: activeFilters,
        // We need to update Provider to accept this, see Step 3
        // orderBy: '${sortField.value} ${sortOrder.value}',
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newEntries = data.map((json) => StockEntry.fromJson(json)).toList();

        if (newEntries.length < _limit) {
          hasMore.value = false;
        }

        if (isLoadMore) {
          stockEntries.addAll(newEntries);
        } else {
          stockEntries.value = newEntries;
        }
        _currentPage++;
      } else {
        Get.snackbar('Error', 'Failed to fetch stock entries');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      if (isLoadMore) {
        isFetchingMore.value = false;
      } else {
        isLoading.value = false;
      }
    }
  }

  // ... (Rest of _fetchAndCacheEntryDetails and toggleExpand remains the same)
  Future<void> _fetchAndCacheEntryDetails(String name) async {
    if (_detailedEntriesCache.containsKey(name)) {
      return;
    }

    isLoadingDetails.value = true;
    try {
      final response = await _provider.getStockEntry(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final entry = StockEntry.fromJson(response.data['data']);
        _detailedEntriesCache[name] = entry;
      } else {
        Get.snackbar('Error', 'Failed to fetch entry details');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      isLoadingDetails.value = false;
    }
  }

  void toggleExpand(String name) {
    if (expandedEntryName.value == name) {
      expandedEntryName.value = '';
    } else {
      expandedEntryName.value = name;
      _fetchAndCacheEntryDetails(name);
    }
  }
}