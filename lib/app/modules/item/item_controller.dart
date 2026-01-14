import 'dart:developer';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/controllers/frappe_list_controller.dart';
import 'package:multimax/models/frappe_filter.dart';

class ItemController extends FrappeListController {
  final ItemProvider _provider = Get.find<ItemProvider>();

  @override
  String get doctype => 'Item';

  // Inherits 'orderBy' from FrappeListController now.

  @override
  int get pageSize => 20;

  @override
  List<FrappeFilterField> get filterableFields => [
    const FrappeFilterField(fieldname: 'item_code', label: 'Item Code'),
    const FrappeFilterField(fieldname: 'item_name', label: 'Item Name'),
    const FrappeFilterField(
      fieldname: 'item_group',
      label: 'Item Group',
      fieldtype: 'Link',
      doctype: 'Item Group',
    ),
    const FrappeFilterField(fieldname: 'description', label: 'Description'),
    const FrappeFilterField(
      fieldname: 'variant_of',
      label: 'Variant Of',
      fieldtype: 'Link',
      doctype: 'Item',
    ),
    const FrappeFilterField(fieldname: 'customer_name', label: 'Customer Name'),
    const FrappeFilterField(fieldname: 'ref_code', label: 'Customer Ref Code'),
    const FrappeFilterField(
      fieldname: '_attribute',
      label: 'Item Attribute',
      fieldtype: 'Attribute',
    ),
  ];

  // Typed getter for the UI
  List<Item> get items => list.map((json) => Item.fromJson(json)).toList();

  // --- STATE ---
  var expandedItemName = ''.obs;
  var isLoadingStock = false.obs;
  final _stockLevelsCache = <String, List<WarehouseStock>>{}.obs;

  var isGridView = false.obs;
  var showImagesOnly = true.obs;

  // Helper Lists
  var itemGroups = <String>[].obs;
  var templateItems = <String>[].obs;
  var itemAttributes = <String>[].obs;
  var currentAttributeValues = <String>[].obs;
  var isLoadingGroups = false.obs;
  var isLoadingTemplates = false.obs;
  var isLoadingAttributes = false.obs;
  var isLoadingAttributeValues = false.obs;

  int get filterCount => activeFilters.length + (showImagesOnly.value ? 1 : 0);

  @override
  void onInit() {
    super.onInit();
    _parseArguments();
    fetchItemGroups();
    fetchTemplateItems();
    fetchItemAttributes();
  }

  void _parseArguments() {
    if (Get.arguments != null && Get.arguments is Map) {
      final args = Get.arguments as Map;
      if (args.containsKey('filters') && args['filters'] is Map) {
        final filtersMap = args['filters'] as Map;
        final List<FrappeFilter> parsedFilters = [];

        filtersMap.forEach((key, valueList) {
          if (valueList is List && valueList.length >= 2) {
            final String op = valueList[0];
            String val = valueList[1].toString();
            if (op == 'like') val = val.replaceAll('%', '');

            final config =
                filterableFields.firstWhereOrNull((f) => f.fieldname == key) ??
                FrappeFilterField(fieldname: key, label: key);

            parsedFilters.add(
              FrappeFilter(
                fieldname: key,
                label: config.label,
                config: config,
                operator: op,
                value: val,
              ),
            );
          }
        });

        if (parsedFilters.isNotEmpty) {
          activeFilters.assignAll(parsedFilters);
          showImagesOnly.value = false;
        }
      }
    }
  }

  void toggleLayout() => isGridView.value = !isGridView.value;

  void setImagesOnly(bool value) => showImagesOnly.value = value;

  // Override to use specialized ItemProvider logic
  @override
  Future<void> refreshList() async {
    isLoading.value = true;
    hasMore.value = true;
    list.clear();
    await _fetchItemsInternal(isLoadMore: false);
    isLoading.value = false;
  }

  @override
  Future<void> loadMore() async {
    if (isFetchingMore.value || !hasMore.value) return;
    isFetchingMore.value = true;
    await _fetchItemsInternal(isLoadMore: true);
    isFetchingMore.value = false;
  }

  Future<void> _fetchItemsInternal({required bool isLoadMore}) async {
    try {
      final List<List<dynamic>> reportFilters = [];
      final List<FrappeFilter> attributeFiltersToProcess = [];

      for (var filter in activeFilters) {
        if (filter.value.isEmpty) continue;

        if (filter.config.fieldtype == 'Attribute') {
          if (filter.extras.containsKey('attributeName')) {
            attributeFiltersToProcess.add(filter);
          }
          continue;
        }

        String val = filter.value;
        if (filter.operator == 'like' && !val.contains('%')) val = '%$val%';

        if (filter.fieldname == 'customer_name' ||
            filter.fieldname == 'ref_code') {
          reportFilters.add([
            'Item Customer Detail',
            filter.fieldname,
            filter.operator,
            val,
          ]);
        } else {
          reportFilters.add(['Item', filter.fieldname, filter.operator, val]);
        }
      }

      if (searchQuery.value.isNotEmpty) {
        reportFilters.add([
          'Item',
          'item_code',
          'like',
          '%${searchQuery.value}%',
        ]);
      }

      if (showImagesOnly.value) {
        reportFilters.add(['Item', 'image', '!=', '']);
      }

      if (attributeFiltersToProcess.isNotEmpty) {
        Set<String>? commonItemCodes;
        for (var filter in attributeFiltersToProcess) {
          final attrName = filter.extras['attributeName'] ?? '';
          try {
            final response = await _provider.getItemVariantsByAttribute(
              attrName,
              filter.value,
            );
            if (response.statusCode == 200 && response.data['data'] != null) {
              final List<String> fetchedCodes = (response.data['data'] as List)
                  .map((e) => e['parent'].toString())
                  .toList();
              commonItemCodes = commonItemCodes == null
                  ? Set.from(fetchedCodes)
                  : commonItemCodes.intersection(Set.from(fetchedCodes));
              if (commonItemCodes.isEmpty) break;
            }
          } catch (e) {
            reportFilters.add([
              'Item',
              'description',
              'like',
              '%${filter.value}%',
            ]);
          }
        }
        if (commonItemCodes != null) {
          if (commonItemCodes.isNotEmpty) {
            reportFilters.add(['Item', 'name', 'in', commonItemCodes.toList()]);
          } else {
            hasMore.value = false;
            return;
          }
        }
      }

      final result = await _provider.getItems(
        limit: pageSize,
        limitStart: isLoadMore ? list.length : 0,
        filters: reportFilters,
        orderBy: orderBy, // FIX: Inherited Getter
      );

      final List<dynamic> data = result['data'] ?? [];
      final newMaps = data.map((e) => e as Map<String, dynamic>).toList();

      if (newMaps.length < pageSize) hasMore.value = false;

      if (isLoadMore) {
        list.addAll(newMaps);
      } else {
        list.assignAll(newMaps);
      }
    } catch (e) {
      log('Error fetching items: $e');
      GlobalSnackbar.error(message: "Failed to load items");
    }
  }

  // --- Helpers for Stock & Attributes ---

  List<WarehouseStock>? getStockFor(String itemCode) =>
      _stockLevelsCache[itemCode];

  Future<void> fetchStockLevels(String itemCode) async {
    if (_stockLevelsCache.containsKey(itemCode)) return;
    isLoadingStock.value = true;
    try {
      final response = await _provider.getStockLevels(itemCode);
      if (response.statusCode == 200 &&
          response.data['message']?['result'] != null) {
        final List<dynamic> data = response.data['message']['result'];
        _stockLevelsCache[itemCode] = data
            .whereType<Map<String, dynamic>>()
            .map((json) => WarehouseStock.fromJson(json))
            .toList();
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
      /*...*/
    } finally {
      isLoadingGroups.value = false;
    }
  }

  Future<void> fetchTemplateItems() async {
    isLoadingTemplates.value = true;
    try {
      final response = await _provider.getTemplateItems();
      if (response.statusCode == 200 && response.data['data'] != null) {
        templateItems.value = (response.data['data'] as List)
            .map((e) => e['name'] as String)
            .toList();
      }
    } catch (e) {
      /*...*/
    } finally {
      isLoadingTemplates.value = false;
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
      /*...*/
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
      /*...*/
    } finally {
      isLoadingAttributeValues.value = false;
    }
  }
}
