import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/data/models/material_request_model.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/material_request_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/providers/warehouse_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

class StockEntryController extends GetxController {
  final StockEntryProvider _provider = Get.find<StockEntryProvider>();
  final PosUploadProvider _posUploadProvider = Get.find<PosUploadProvider>();
  final MaterialRequestProvider _materialRequestProvider =
      Get.find<MaterialRequestProvider>();
  final UserProvider _userProvider = Get.find<UserProvider>();
  final WarehouseProvider _warehouseProvider = Get.find<WarehouseProvider>();

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

  var searchQuery = ''.obs;

  var sortField = 'creation'.obs;
  var sortOrder = 'desc'.obs;

  var isFetchingPosUploads = false.obs;
  var posUploadsForSelection = <PosUpload>[].obs;
  List<PosUpload> _allFetchedPosUploads = [];

  var isFetchingMaterialRequests = false.obs;
  var materialRequestsForSelection = <MaterialRequest>[].obs;
  List<MaterialRequest> _allFetchedMaterialRequests = [];

  var stockEntryTypes = <String>[].obs;
  var isFetchingTypes = false.obs;

  var users = <User>[].obs;
  var isFetchingUsers = false.obs;

  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;

  StockEntry? get detailedEntry =>
      _detailedEntriesCache[expandedEntryName.value];

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args is Map && args['filters'] is Map) {
      activeFilters.value = Map<String, dynamic>.from(args['filters'] as Map);
    }
    // ignore: unawaited_futures
    Future.wait([
      fetchStockEntries(),
      fetchStockEntryTypes(),
      fetchUsers(),
      fetchWarehouses(),
    ]);
    debounce(searchQuery, (_) => fetchStockEntries(clear: true),
        time: const Duration(milliseconds: 500));
  }

  @override
  void onReady() {
    super.onReady();
    final args = Get.arguments;
    if (args is Map && args['openCreate'] == true) {
      openCreateDialog();
    }
  }

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchStockEntries(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    if (searchQuery.value.isEmpty) {
      fetchStockEntries(isLoadMore: false, clear: true);
    } else {
      searchQuery.value = '';
    }
  }

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetchStockEntries(isLoadMore: false, clear: true);
  }

  void setSort(String field, String order) {
    sortField.value = field;
    sortOrder.value = order;
    fetchStockEntries(isLoadMore: false, clear: true);
  }

  void onSearchChanged(String val) => searchQuery.value = val;

  Future<void> fetchStockEntries(
      {bool isLoadMore = false, bool clear = false}) async {
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
      final Map<String, dynamic> queryFilters = Map.from(activeFilters);
      if (searchQuery.value.isNotEmpty) {
        queryFilters['name'] = ['like', '%${searchQuery.value}%'];
      }

      final response = await _provider.getStockEntries(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: queryFilters,
        orderBy: '${sortField.value} ${sortOrder.value}',
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newEntries =
            data.map((json) => StockEntry.fromJson(json)).toList();
        if (newEntries.length < _limit) hasMore.value = false;
        if (isLoadMore) {
          stockEntries.addAll(newEntries);
        } else {
          stockEntries.value = newEntries;
        }
        _currentPage++;
      } else {
        GlobalDialog.showError(
          title: 'Could not load Stock Entries',
          message: 'The server returned an unexpected response. '
              'Check your connection and try again.',
          onRetry: () =>
              fetchStockEntries(isLoadMore: isLoadMore, clear: clear),
        );
      }
    } catch (e) {
      GlobalDialog.showError(
        title: 'Could not load Stock Entries',
        message: e.toString(),
        onRetry: () =>
            fetchStockEntries(isLoadMore: isLoadMore, clear: clear),
      );
    } finally {
      if (isLoadMore) {
        isFetchingMore.value = false;
      } else {
        isLoading.value = false;
      }
    }
  }

  Future<void> fetchStockEntryTypes() async {
    if (stockEntryTypes.isNotEmpty) return;
    isFetchingTypes.value = true;
    try {
      final response = await _provider.getStockEntryTypes();
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        stockEntryTypes.value =
            data.map((e) => e['name'].toString()).toList();
      }
    } catch (e) {
      print('Error fetching stock entry types: $e');
    } finally {
      isFetchingTypes.value = false;
    }
  }

  Future<void> fetchUsers() async {
    if (users.isNotEmpty) return;
    isFetchingUsers.value = true;
    try {
      final response = await _userProvider.getUsers();
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        users.value = data.map((json) => User.fromJson(json)).toList();
      }
    } catch (e) {
      print('Error fetching users: $e');
    } finally {
      isFetchingUsers.value = false;
    }
  }

  Future<void> fetchWarehouses() async {
    if (warehouses.isNotEmpty) return;
    isFetchingWarehouses.value = true;
    try {
      final response = await _warehouseProvider.getWarehouses();
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        warehouses.value =
            data.map((e) => e['name'].toString()).toList();
      }
    } catch (e) {
      print('Error fetching warehouses: $e');
    } finally {
      isFetchingWarehouses.value = false;
    }
  }

  Future<void> _fetchAndCacheEntryDetails(String name) async {
    if (_detailedEntriesCache.containsKey(name)) return;
    isLoadingDetails.value = true;
    try {
      final response = await _provider.getStockEntry(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final entry = StockEntry.fromJson(response.data['data']);
        _detailedEntriesCache[name] = entry;
      } else {
        GlobalDialog.showError(
          title: 'Could not load entry details',
          message: 'Failed to fetch details for $name. '
              'Check your connection and try again.',
          onRetry: () => _fetchAndCacheEntryDetails(name),
        );
      }
    } catch (e) {
      GlobalDialog.showError(
        title: 'Could not load entry details',
        message: e.toString(),
        onRetry: () => _fetchAndCacheEntryDetails(name),
      );
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

  Future<void> fetchPosUploadsForSelection() async {
    isFetchingPosUploads.value = true;
    try {
      final kxFuture = _posUploadProvider.getPosUploads(
          limit: 50,
          filters: {
            'status': [
              'in',
              ['Pending', 'In Progress']
            ],
            'name': ['like', 'KX%']
          },
          orderBy: 'modified desc');
      final mxFuture = _posUploadProvider.getPosUploads(
          limit: 50,
          filters: {
            'status': [
              'in',
              ['Pending', 'In Progress']
            ],
            'name': ['like', 'MX%']
          },
          orderBy: 'modified desc');
      final results = await Future.wait([kxFuture, mxFuture]);
      final List<PosUpload> mergedList = [];
      for (var response in results) {
        if (response.statusCode == 200 && response.data['data'] != null) {
          final List<dynamic> data = response.data['data'];
          mergedList.addAll(data.map((json) => PosUpload.fromJson(json)));
        }
      }
      final uniqueMap = {for (var item in mergedList) item.name: item};
      final sortedList = uniqueMap.values.toList()
        ..sort((a, b) => b.modified.compareTo(a.modified));
      _allFetchedPosUploads = sortedList;
      posUploadsForSelection.value = _allFetchedPosUploads;
    } catch (e) {
      // Selection sheet is still interactive — a non-blocking notification
      // is appropriate here rather than a blocking dialog.
      AppNotification.error('Failed to fetch POS Uploads: $e');
    } finally {
      isFetchingPosUploads.value = false;
    }
  }

  void filterPosUploads(String query) {
    if (query.isEmpty) {
      posUploadsForSelection.value = _allFetchedPosUploads;
    } else {
      final q = query.toLowerCase();
      posUploadsForSelection.value = _allFetchedPosUploads
          .where((u) =>
              u.name.toLowerCase().contains(q) ||
              u.customer.toLowerCase().contains(q))
          .toList();
    }
  }

  Future<void> fetchPendingMaterialRequests() async {
    isFetchingMaterialRequests.value = true;
    try {
      final response = await _materialRequestProvider.getMaterialRequests(
          limit: 50,
          filters: {
            'docstatus': 1,
            'status': ['!=', 'Stopped'],
            'material_request_type': ['!=', 'Purchase'],
          },
          orderBy: 'modified desc');
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        _allFetchedMaterialRequests =
            data.map((json) => MaterialRequest.fromJson(json)).toList();
        materialRequestsForSelection.value = _allFetchedMaterialRequests;
      }
    } catch (e) {
      // Selection sheet is still interactive — a non-blocking notification
      // is appropriate here rather than a blocking dialog.
      AppNotification.error('Failed to fetch Material Requests: $e');
    } finally {
      isFetchingMaterialRequests.value = false;
    }
  }

  void filterMaterialRequests(String query) {
    if (query.isEmpty) {
      materialRequestsForSelection.value = _allFetchedMaterialRequests;
    } else {
      final q = query.toLowerCase();
      materialRequestsForSelection.value = _allFetchedMaterialRequests
          .where((mr) =>
              mr.name.toLowerCase().contains(q) ||
              mr.materialRequestType.toLowerCase().contains(q))
          .toList();
    }
  }

  void openCreateDialog() {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Get.theme.colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16.0)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Create Stock Entry', style: Get.textTheme.titleLarge),
              const SizedBox(height: 16),
              ListTile(
                leading: const CircleAvatar(
                  // x700/x600 fills keep the white glyphs ≥4.5:1.
                  backgroundColor: AppColors.orange700,
                  child: Icon(Icons.outbond, color: Colors.white),
                ),
                title: const Text('From POS Upload'),
                subtitle: const Text('Material Issue (KX/MX)'),
                onTap: () {
                  Get.back();
                  _showPosSelectionBottomSheet();
                },
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.cyan700,
                  child: Icon(Icons.assignment, color: Colors.white),
                ),
                title: const Text('From Material Request'),
                subtitle: const Text('Transfer / Issue / Manufacture'),
                onTap: () {
                  Get.back();
                  _showMaterialRequestSelectionBottomSheet();
                },
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.blue600,
                  child: Icon(Icons.add, color: Colors.white),
                ),
                title: const Text('New Stock Entry'),
                subtitle: const Text('Select type after creating'),
                onTap: () {
                  Get.back();
                  Get.toNamed(AppRoutes.STOCK_ENTRY_FORM, arguments: {
                    'name': '',
                    'mode': 'new',
                    'stockEntryType': '',
                    'customReferenceNo': ''
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPosSelectionBottomSheet() {
    fetchPosUploadsForSelection();
    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            final scheme = context.scheme;
            return Container(
              decoration: BoxDecoration(
                color: scheme.fg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16.0)),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select POS Upload',
                          style: Theme.of(context).textTheme.titleLarge),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Get.back()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: filterPosUploads,
                    decoration: InputDecoration(
                      labelText: 'Search (KX/MX Only)',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: scheme.subtle,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Obx(() {
                      if (isFetchingPosUploads.value) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (posUploadsForSelection.isEmpty) {
                        return const Center(
                            child:
                                Text('No matching POS Uploads found.'));
                      }
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: posUploadsForSelection.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final pos = posUploadsForSelection[index];
                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: scheme.border)),
                            child: InkWell(
                              onTap: () {
                                Get.back();
                                Get.toNamed(
                                    AppRoutes.STOCK_ENTRY_FORM,
                                    arguments: {
                                      'name': '',
                                      'mode': 'new',
                                      'stockEntryType': 'Material Issue',
                                      'customReferenceNo': pos.name
                                    });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(pos.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16)),
                                        Container(
                                          padding: const EdgeInsets
                                              .symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                              color: AppColors.orange500
                                                  .withValues(alpha: 0.13),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      8),
                                              border: Border.all(
                                                  color: AppColors
                                                      .orange500
                                                      .withValues(
                                                          alpha: 0.35))),
                                          child: Text(pos.status,
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Theme.of(context)
                                                              .brightness ==
                                                          Brightness.dark
                                                      ? AppColors.orange300
                                                      : AppColors
                                                          .orange700,
                                                  fontWeight:
                                                      FontWeight.bold)),
                                        )
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(pos.customer,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 8),
                                    const Divider(height: 1),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                                Icons.inventory_2_outlined,
                                                size: 14,
                                                color: scheme.textMuted),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${pos.totalQty?.toStringAsFixed(0) ?? 0} Items',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight:
                                                      FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                        Text(pos.date,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: scheme.textMuted)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      isScrollControlled: true,
    );
  }

  void _showMaterialRequestSelectionBottomSheet() {
    fetchPendingMaterialRequests();
    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            final scheme = context.scheme;
            return Container(
              decoration: BoxDecoration(
                color: scheme.fg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16.0)),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select Material Request',
                          style: Theme.of(context).textTheme.titleLarge),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Get.back()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: filterMaterialRequests,
                    decoration: InputDecoration(
                      labelText: 'Search',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: scheme.subtle,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Obx(() {
                      if (isFetchingMaterialRequests.value) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (materialRequestsForSelection.isEmpty) {
                        return const Center(
                            child: Text(
                                'No matching Material Requests found.'));
                      }
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: materialRequestsForSelection.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final mr = materialRequestsForSelection[index];
                          final String seType =
                              mapMrTypeToSeType(mr.materialRequestType);
                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: scheme.border)),
                            child: InkWell(
                              onTap: () {
                                Get.back();
                                final itemsList = mr.items
                                    .map((i) => {
                                          'item_code': i.itemCode,
                                          'qty': i.qty,
                                          'material_request': mr.name,
                                          'material_request_item': i.name,
                                        })
                                    .toList();
                                Get.toNamed(
                                    AppRoutes.STOCK_ENTRY_FORM,
                                    arguments: {
                                      'name': '',
                                      'mode': 'new',
                                      'stockEntryType': seType,
                                      'customReferenceNo': mr.name,
                                      'items': itemsList
                                    });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(mr.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16)),
                                        StatusPill(status: mr.status)
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                        'Type: ${mr.materialRequestType}',
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 8),
                                    const Divider(height: 1),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.date_range,
                                                size: 14,
                                                color: scheme.textMuted),
                                            const SizedBox(width: 4),
                                            Text(mr.transactionDate,
                                                style: const TextStyle(
                                                    fontSize: 12)),
                                          ],
                                        ),
                                        Text(
                                            'Items: ${mr.items.length}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: scheme.textMuted)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      isScrollControlled: true,
    );
  }

  /// Maps a Frappe Material Request type to its corresponding Stock Entry type.
  ///
  /// Exposed as package-visible (no leading underscore) so it can be
  /// unit-tested directly in
  /// test/unit/stock_entry/mr_type_mapping_test.dart.
  String mapMrTypeToSeType(String mrType) {
    switch (mrType) {
      case 'Material Transfer':
        return 'Material Transfer';
      case 'Material Issue':
        return 'Material Issue';
      case 'Manufacture':
        return 'Material Transfer for Manufacture';
      case 'Material Receipt':
      default:
        return mrType;
    }
  }
}
