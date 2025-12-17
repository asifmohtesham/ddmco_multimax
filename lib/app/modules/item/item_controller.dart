import 'dart:developer';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/data/utils/search_helper.dart';

class ItemController extends GetxController {
  final ItemProvider _provider = Get.find<ItemProvider>();

  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;

  var items = <Item>[].obs;
  var displayedItems = <Item>[].obs;

  final int _limit = 20;
  int _currentPage = 0;

  var expandedItemName = ''.obs;
  var isLoadingStock = false.obs;
  final _stockLevelsCache = <String, List<WarehouseStock>>{}.obs;

  final activeFilters = <String, dynamic>{}.obs;
  var attributeFilters = <Map<String, String>>[].obs;

  var sortField = '`tabItem`.`modified`'.obs;
  var sortOrder = 'desc'.obs;

  var searchQuery = ''.obs;

  var itemGroups = <String>[].obs;
  var templateItems = <String>[].obs;
  var itemAttributes = <String>[].obs;
  var currentAttributeValues = <String>[].obs;

  var isLoadingGroups = false.obs;
  var isLoadingTemplates = false.obs;
  var isLoadingAttributes = false.obs;
  var isLoadingAttributeValues = false.obs;

  var showImagesOnly = true.obs;
  var isGridView = false.obs;

  @override
  void onInit() {
    super.onInit();
    fetchItems();
    fetchItemGroups();
    fetchTemplateItems();
    fetchItemAttributes();

    ever(items, (_) => _applySearch());
    ever(searchQuery, (_) => _applySearch());
  }

  void toggleLayout() {
    isGridView.value = !isGridView.value;
  }

  void setImagesOnly(bool value) {
    showImagesOnly.value = value;
  }

  void onSearchChanged(String query) {
    searchQuery.value = query;
  }

  void _applySearch() {
    displayedItems.value = SearchHelper.search<Item>(
      items,
      searchQuery.value,
          (item) => [
        item.itemName,
        item.itemCode,
        item.itemGroup,
        item.variantOf,
        item.description,
        ...item.customerItems.map((e) => e.customerName),
        ...item.customerItems.map((e) => e.refCode),
      ],
    );
  }

  void applyFilters(Map<String, dynamic> filters, List<Map<String, String>> attributes) {
    activeFilters.value = filters;
    attributeFilters.assignAll(attributes);
    fetchItems(clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    attributeFilters.clear();
    showImagesOnly.value = true;
    searchQuery.value = '';
    fetchItems(clear: true);
  }

  void setSort(String field, String order) {
    if (!field.contains('`')) {
      field = '`tabItem`.`$field`';
    }
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
      final List<List<dynamic>> reportFilters = [];

      activeFilters.forEach((key, value) {
        dynamic filterVal = value;
        String op = '=';

        if (value is List && value.isNotEmpty) {
          op = value[0];
          filterVal = value.length > 1 ? value[1] : '';
        }

        if (key == 'customer_name') {
          reportFilters.add(['Item Customer Detail', 'customer_name', 'like', filterVal]);
        } else if (key == 'ref_code') {
          reportFilters.add(['Item Customer Detail', 'ref_code', 'like', filterVal]);
        } else {
          reportFilters.add(['Item', key, op, filterVal]);
        }
      });

      if (showImagesOnly.value) {
        reportFilters.add(['Item', 'image', '!=', '']);
      }

      if (attributeFilters.isNotEmpty) {
        for (var filter in attributeFilters) {
          reportFilters.add(['Item', 'description', 'like', '%${filter['value']}%']);
        }
      }

      final result = await _provider.getItems(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: reportFilters,
        orderBy: '${sortField.value} ${sortOrder.value}',
      );
log(name: 'fetchItems', result.toString());
      final List<dynamic> data = result['data'] ?? [];
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

    } catch (e) {
      log('Error fetching items: $e');
      String msg = e.toString().replaceAll('Exception:', '').trim();
      if (msg.length > 150) msg = "${msg.substring(0, 150)}... (Check logs)";
      GlobalSnackbar.error(message: msg);
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
        itemGroups.value = (response.data['data'] as List).map((e) => e['name'] as String).toList();
      }
    } catch (e) {
      print('Error fetching item groups: $e');
    } finally {
      isLoadingGroups.value = false;
    }
  }

  Future<void> fetchTemplateItems() async {
    isLoadingTemplates.value = true;
    try {
      final response = await _provider.getTemplateItems();
      if (response.statusCode == 200 && response.data['data'] != null) {
        templateItems.value = (response.data['data'] as List).map((e) => e['name'] as String).toList();
      }
    } catch (e) {
      print('Error fetching template items: $e');
    } finally {
      isLoadingTemplates.value = false;
    }
  }

  Future<void> fetchItemAttributes() async {
    isLoadingAttributes.value = true;
    try {
      final response = await _provider.getItemAttributes();
      if (response.statusCode == 200 && response.data['data'] != null) {
        itemAttributes.value = (response.data['data'] as List).map((e) => e['name'] as String).toList();
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
          currentAttributeValues.value = (data['item_attribute_values'] as List).map((e) => e['attribute_value'] as String).toList();
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