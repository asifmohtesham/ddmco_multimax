import 'dart:developer';

import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/item_model.dart';
import 'package:ddmco_multimax/app/data/providers/item_provider.dart';

class ItemController extends GetxController {
  final ItemProvider _provider = Get.find<ItemProvider>();

  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;
  var items = <Item>[].obs;
  final int _limit = 20;
  int _currentPage = 0;

  var expandedItemName = ''.obs;
  var isLoadingStock = false.obs;
  final _stockLevelsCache = <String, List<WarehouseStock>>{}.obs;

  final activeFilters = <String, dynamic>{}.obs;
  var sortField = 'modified'.obs;
  var sortOrder = 'desc'.obs;

  // Default to true as per requirements: "display only those items that have an image set"
  var showImagesOnly = true.obs;

  // Layout state
  var isGridView = false.obs;

  @override
  void onInit() {
    super.onInit();
    fetchItems();
  }

  void toggleLayout() {
    isGridView.value = !isGridView.value;
  }

  void setImagesOnly(bool value) {
    showImagesOnly.value = value;
  }

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchItems(clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    // Reset image filter to default requirement? Or keep user preference?
    // User probably expects "Clear" to reset to the default state defined by the screen logic.
    showImagesOnly.value = true;
    fetchItems(clear: true);
  }

  void setSort(String field, String order) {
    sortField.value = field;
    sortOrder.value = order;
    fetchItems(clear: true);
  }

  Future<void> fetchItems({bool isLoadMore = false, bool clear = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      if (clear) {
        items.clear();
        _currentPage = 0;
        hasMore.value = true;
      }
    }

    try {
      // Construct effective filters
      final Map<String, dynamic> queryFilters = Map.from(activeFilters);

      if (showImagesOnly.value) {
        queryFilters['image'] = ['!=', ''];
      }

      final response = await _provider.getItems(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: queryFilters,
        orderBy: '${sortField.value} ${sortOrder.value}',
      );
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newItems = data.map((json) => Item.fromJson(json)).toList();

        if (newItems.length < _limit) {
          hasMore.value = false;
        }

        if (isLoadMore) {
          items.addAll(newItems);
        } else {
          items.value = newItems;
        }
        _currentPage++;
      } else {
        Get.snackbar('Error', 'Failed to fetch items');
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

  List<WarehouseStock>? getStockFor(String itemCode) => _stockLevelsCache[itemCode];

  Future<void> fetchStockLevels(String itemCode) async {
    if (_stockLevelsCache.containsKey(itemCode)) return;

    isLoadingStock.value = true;
    try {
      final response = await _provider.getStockLevels(itemCode);
      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> data = response.data['message']['result'];
        _stockLevelsCache[itemCode] = data.whereType<Map<String, dynamic>>().map((json) => WarehouseStock.fromJson(json)).toList();
      } else {
        // Silent fail or low priority snackbar
        print('Failed to fetch stock levels');
      }
    } catch (e) {
      print('Failed to fetch stock levels: $e');
    } finally {
      isLoadingStock.value = false;
    }
  }

  void toggleExpand(String name, String itemCode) {
    if (expandedItemName.value == name) {
      expandedItemName.value = '';
    } else {
      expandedItemName.value = name;
      fetchStockLevels(itemCode);
    }
  }
}