import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/controllers/frappe_filter_sheet_controller.dart';
import 'package:multimax/widgets/frappe_filter_bottom_sheet.dart';
import '../services/frappe_api.dart';
import '../models/frappe_filter.dart';

abstract class FrappeListController extends GetxController {
  final FrappeApiService api = FrappeApiService();

  // --- Abstract Config ---
  String get doctype;

  List<FrappeFilterField> get filterableFields;

  List<String> get defaultFields => ['name', 'modified', 'docstatus'];

  int get pageSize => 20;

  // --- State ---
  final RxList<Map<String, dynamic>> list = <Map<String, dynamic>>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isFetchingMore = false.obs;
  final RxBool hasMore = true.obs;

  // --- Sorting ---
  final RxString sortField = 'modified'.obs;
  final RxString sortOrder = 'desc'.obs;

  String get orderBy => '${sortField.value} ${sortOrder.value}';

  // --- Filtering ---
  final RxList<FrappeFilter> activeFilters = <FrappeFilter>[].obs;
  final RxString searchQuery = ''.obs;

  final List<String> availableOperators = [
    'like',
    '=',
    '!=',
    '>',
    '<',
    '>=',
    '<=',
  ];

  int _start = 0;
  Worker? _debounceWorker;

  @override
  void onInit() {
    super.onInit();
    _debounceWorker = debounce(
      searchQuery,
      (q) => refreshList(),
      time: const Duration(milliseconds: 500),
    );
    refreshList();
  }

  @override
  void onClose() {
    _debounceWorker?.dispose();
    super.onClose();
  }

  // --- Actions ---

  void setSort(String field, String order) {
    sortField.value = field;
    sortOrder.value = order;
    refreshList();
  }

  void applyFilters(List<FrappeFilter> filters) {
    activeFilters.assignAll(filters);
    refreshList();
  }

  void clearFilters() {
    activeFilters.clear();
    searchQuery.value = '';
    refreshList();
  }

  // Also ensure onSearchChanged is defined if it wasn't:
  void onSearchChanged(String query) {
    searchQuery.value = query;
  }

  Future<void> refreshList() async {
    isLoading.value = true;
    _start = 0;
    hasMore.value = true;
    list.clear();
    await _fetchItemsInternal();
    isLoading.value = false;
  }

  Future<void> loadMore() async {
    if (isFetchingMore.value || !hasMore.value) return;
    isFetchingMore.value = true;
    await _fetchItemsInternal();
    isFetchingMore.value = false;
  }

  // Generic Search for Link Fields (used by Filter Sheet)
  Future<List<String>> searchLink(String doctype, String txt) {
    return api.searchLink(doctype, txt);
  }

  Future<void> _fetchItemsInternal() async {
    try {
      final filters = _buildApiFilters();

      // Explicitly List<Map...>
      final List<Map<String, dynamic>> results = await api.getList(
        doctype: doctype,
        fields: defaultFields,
        filters: filters,
        orderBy: orderBy,
        limitStart: _start,
        limit: pageSize,
      );

      if (results.length < pageSize) hasMore.value = false;

      _start += results.length;
      list.addAll(results);
    } catch (e) {
      debugPrint("❌ Error fetching $doctype: $e");
    }
  }

  Map<String, dynamic> _buildApiFilters() {
    final Map<String, dynamic> filters = {};

    // 1. Search Query
    if (searchQuery.isNotEmpty) {
      filters['name'] = ['like', '%${searchQuery.value}%'];
    }

    // 2. Active Filters
    for (var f in activeFilters) {
      if (f.value.isNotEmpty) {
        String val = f.value;
        if (f.operator == 'like' && !val.contains('%')) val = '%$val%';
        filters[f.fieldname] = [f.operator, val];
      }
    }

    return filters;
  }

  void showFilterBottomSheet() {
    // Inject the Sheet Controller manually before showing
    final sheetCtrl = Get.put(FrappeFilterSheetController());
    sheetCtrl.initialize(this);

    Get.bottomSheet(
      const FrappeFilterBottomSheet(), // Ensure this widget imports the generic one
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    ).then((_) {
      // Cleanup when closed
      Get.delete<FrappeFilterSheetController>();
    });
  }
}
