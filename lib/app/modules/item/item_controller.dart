import 'dart:developer';

import 'package:get/get.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

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

  // Filter Data Sources
  var itemGroups = <String>[].obs;
  var itemAttributes = <String>[].obs;
  var currentAttributeValues = <String>[].obs; // Values for the selected attribute

  var isLoadingGroups = false.obs;
  var isLoadingAttributes = false.obs;
  var isLoadingAttributeValues = false.obs;

  // Default to true as per requirements: "display only those items that have an image set"
  var showImagesOnly = true.obs;

  // Layout state
  var isGridView = false.obs;

  @override
  void onInit() {
    super.onInit();
    fetchItems();
    fetchItemGroups();
    fetchItemAttributes(); // Load attributes on init
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

      // Handle Attribute filtering
      // If we have a specific attribute value selected in UI, map it to description search
      // as standard Item list API doesn't support deep child table filtering easily.
      if (queryFilters.containsKey('_attribute_value')) {
        final val = queryFilters['_attribute_value'];
        // Remove internal key
        queryFilters.remove('_attribute_value');
        queryFilters.remove('_attribute_name');
        // Apply to description (e.g., finding "Red", "Large")
        queryFilters['description'] = ['like', '%$val%'];
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
        GlobalSnackbar.error(message: 'Failed to fetch items');
      }
    } catch (e) {
      GlobalSnackbar.error(message: e.toString());
    } finally {
      if (isLoadMore) {
        isFetchingMore.value = false;
      } else {
        isLoading.value = false;
      }
    }
  }

  Future<void> fetchItemGroups() async {
    isLoadingGroups.value = true;
    try {
      final response = await _provider.getItemGroups();
      if (response.statusCode == 200 && response.data['data'] != null) {
        itemGroups.value = (response.data['data'] as List)
            .map((e) => e['name'] as String)
            .toList();
      }
    } catch (e) {
      print('Error fetching item groups: $e');
    } finally {
      isLoadingGroups.value = false;
    }
  }

  Future<void> fetchItemAttributes() async {
    isLoadingAttributes.value = true;
    try {
      final response = await _provider.getItemAttributes();
      if (response.statusCode == 200 && response.data['data'] != null) {
        itemAttributes.value = (response.data['data'] as List)
            .map((e) => e['name'] as String)
            .toList();
      }
    } catch (e) {
      print('Error fetching item attributes: $e');
    } finally {
      isLoadingAttributes.value = false;
    }
  }

  Future<void> fetchAttributeValues(String attributeName) async {
    isLoadingAttributeValues.value = true;
    currentAttributeValues.clear();
    try {
      final response = await _provider.getItemAttributeDetails(attributeName);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'];
        if (data['item_attribute_values'] != null) {
          currentAttributeValues.value = (data['item_attribute_values'] as List)
              .map((e) => e['attribute_value'] as String)
              .toList();
        }
      }
    } catch (e) {
      print('Error fetching attribute values: $e');
    } finally {
      isLoadingAttributeValues.value = false;
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