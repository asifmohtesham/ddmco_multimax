import 'dart:developer';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/data/utils/search_helper.dart';

/// Model to represent a single row in the unified filter list
class FilterRow {
  String field;       // The db field name or '_attribute' for attribute filters
  String label;       // Label shown to user
  String operator;    // e.g., 'like', '='
  String value;       // User entered value
  String fieldType;   // 'Data', 'Link', 'Attribute'
  String? doctype;    // For Link fields, e.g., 'Item Group'
  String attributeName; // Only used if fieldType == 'Attribute' (e.g., 'Color')

  FilterRow({
    required this.field,
    required this.label,
    this.operator = 'like',
    this.value = '',
    this.fieldType = 'Data',
    this.doctype,
    this.attributeName = '',
  });

  // Clone for local editing in the UI
  FilterRow clone() {
    return FilterRow(
      field: field,
      label: label,
      operator: operator,
      value: value,
      fieldType: fieldType,
      doctype: doctype,
      attributeName: attributeName,
    );
  }
}

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

  // --- UNIFIED FILTER STATE ---
  final activeFilters = <FilterRow>[].obs;

  // Configuration for Available Fields
  final List<FilterRow> availableFields = [
    FilterRow(field: 'item_code', label: 'Item Code', operator: 'like'),
    FilterRow(field: 'item_name', label: 'Item Name', operator: 'like'),
    FilterRow(field: 'item_group', label: 'Item Group', operator: '=', fieldType: 'Link', doctype: 'Item Group'),
    FilterRow(field: 'description', label: 'Description', operator: 'like'),
    FilterRow(field: 'variant_of', label: 'Variant Of', operator: '=', fieldType: 'Link', doctype: 'Item'),
    FilterRow(field: 'customer_name', label: 'Customer Name', operator: 'like'),
    FilterRow(field: 'ref_code', label: 'Customer Ref Code', operator: 'like'),
    // Special Option to trigger Attribute UI
    FilterRow(field: '_attribute', label: 'Item Attribute', operator: '=', fieldType: 'Attribute'),
  ];

  final List<String> availableOperators = ['like', '=', '!=', '>', '<', '>=', '<='];

  var sortField = '`tabItem`.`modified`'.obs;
  var sortOrder = 'desc'.obs;

  var searchQuery = ''.obs;

  // Reference Data
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

  // Helper for Badge Count
  int get filterCount => activeFilters.length + (showImagesOnly.value ? 1 : 0);

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

  void applyFilters(List<FilterRow> filters) {
    activeFilters.assignAll(filters);
    fetchItems(clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
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
      final List<FilterRow> attributeFiltersToProcess = [];

      // 1. Separate Filters (Standard vs Attribute)
      for (var filter in activeFilters) {
        if (filter.value.isEmpty) continue;

        if (filter.fieldType == 'Attribute') {
          if (filter.attributeName.isNotEmpty) {
            attributeFiltersToProcess.add(filter);
          }
          continue;
        }

        // --- UPDATE: Apply % wildcards for 'like' operator to ALL fields ---
        String val = filter.value;
        if (filter.operator == 'like' && !val.contains('%')) {
          val = '%$val%';
        }

        // Apply filters to appropriate tables
        if (filter.field == 'customer_name') {
          reportFilters.add(['Item Customer Detail', 'customer_name', filter.operator, val]);
        } else if (filter.field == 'ref_code') {
          reportFilters.add(['Item Customer Detail', 'ref_code', filter.operator, val]);
        } else {
          reportFilters.add(['Item', filter.field, filter.operator, val]);
        }
      }

      if (showImagesOnly.value) {
        reportFilters.add(['Item', 'image', '!=', '']);
      }

      // 2. Process Attribute Filters (Intersection Logic)
      if (attributeFiltersToProcess.isNotEmpty) {
        Set<String>? commonItemCodes;
        bool permissionErrorOccurred = false;

        for (var filter in attributeFiltersToProcess) {
          try {
            final response = await _provider.getItemVariantsByAttribute(
                filter.attributeName,
                filter.value
            );

            if (response.statusCode == 200 && response.data['data'] != null) {
              final List<String> fetchedCodes = (response.data['data'] as List)
                  .map((e) => e['parent'].toString())
                  .toList();

              if (commonItemCodes == null) {
                commonItemCodes = Set.from(fetchedCodes);
              } else {
                commonItemCodes = commonItemCodes.intersection(Set.from(fetchedCodes));
              }
              if (commonItemCodes.isEmpty) break;
            }
          } catch (e) {
            permissionErrorOccurred = true;
            // Fallback: simple text search in description if exact match fails
            reportFilters.add(['Item', 'description', 'like', '%${filter.value}%']);
          }
        }

        if (!permissionErrorOccurred) {
          if (commonItemCodes != null && commonItemCodes.isNotEmpty) {
            reportFilters.add(['Item', 'name', 'in', commonItemCodes.toList()]);
          } else if (commonItemCodes != null && commonItemCodes.isEmpty) {
            // No matches for attributes
            items.clear();
            isLoading.value = false;
            hasMore.value = false;
            isFetchingMore.value = false;
            return;
          }
        }
      }

      final result = await _provider.getItems(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: reportFilters,
        orderBy: '${sortField.value} ${sortOrder.value}',
      );

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

  // --- Reference Data Fetchers ---
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