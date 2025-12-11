import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class StockEntryController extends GetxController {
  final StockEntryProvider _provider = Get.find<StockEntryProvider>();
  final PosUploadProvider _posUploadProvider = Get.find<PosUploadProvider>();

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

  var sortField = 'creation'.obs;
  var sortOrder = 'desc'.obs;

  // For POS Selection
  var isFetchingPosUploads = false.obs;
  var posUploadsForSelection = <PosUpload>[].obs;
  List<PosUpload> _allFetchedPosUploads = [];

  StockEntry? get detailedEntry => _detailedEntriesCache[expandedEntryName.value];

  @override
  void onInit() {
    super.onInit();
    fetchStockEntries();
  }

  @override
  void onReady() {
    super.onReady();
    if (Get.arguments is Map && Get.arguments['openCreate'] == true) {
      openCreateDialog();
    }
  }

  // ... (Existing Fetch, Filter, Sort, Expand logic unchanged) ...
  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchStockEntries(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    fetchStockEntries(isLoadMore: false, clear: true);
  }

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
      final response = await _provider.getStockEntries(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: activeFilters,
        orderBy: '${sortField.value} ${sortOrder.value}',
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

  // --- UPDATED POS FETCHING LOGIC (API SIDE FILTER) ---
  Future<void> fetchPendingPosUploads() async {
    isFetchingPosUploads.value = true;
    try {
      // API Call 1: Fetch items starting with KX
      final kxFuture = _posUploadProvider.getPosUploads(
          limit: 50,
          filters: {
            'status': ['in', ['Pending', 'In Progress']],
            'name': ['like', 'KX%']
          },
          orderBy: 'modified desc'
      );

      // API Call 2: Fetch items starting with MX
      final mxFuture = _posUploadProvider.getPosUploads(
          limit: 50,
          filters: {
            'status': ['in', ['Pending', 'In Progress']],
            'name': ['like', 'MX%']
          },
          orderBy: 'modified desc'
      );

      final results = await Future.wait([kxFuture, mxFuture]);

      final List<PosUpload> mergedList = [];

      for (var response in results) {
        if (response.statusCode == 200 && response.data['data'] != null) {
          final List<dynamic> data = response.data['data'];
          mergedList.addAll(data.map((json) => PosUpload.fromJson(json)));
        }
      }

      // Deduplicate (using name as key) & Sort
      final uniqueMap = {for (var item in mergedList) item.name: item};
      final sortedList = uniqueMap.values.toList()
        ..sort((a, b) => b.modified.compareTo(a.modified));

      _allFetchedPosUploads = sortedList;
      posUploadsForSelection.value = _allFetchedPosUploads;

    } catch (e) {
      Get.snackbar('Error', 'Failed to fetch POS Uploads: $e');
    } finally {
      isFetchingPosUploads.value = false;
    }
  }

  void filterPosUploads(String query) {
    if (query.isEmpty) {
      posUploadsForSelection.value = _allFetchedPosUploads;
    } else {
      final q = query.toLowerCase();
      posUploadsForSelection.value = _allFetchedPosUploads.where((upload) {
        return upload.name.toLowerCase().contains(q) ||
            upload.customer.toLowerCase().contains(q);
      }).toList();
    }
  }

  void openCreateDialog() {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Create Stock Entry', style: Get.textTheme.titleLarge),
              const SizedBox(height: 16),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Icon(Icons.outbond, color: Colors.white),
                ),
                title: const Text('Material Issue'),
                subtitle: const Text('From POS Upload (KX/MX only)'),
                onTap: () {
                  Get.back();
                  _showPosSelectionBottomSheet();
                },
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.transform, color: Colors.white),
                ),
                title: const Text('Material Transfer'),
                subtitle: const Text('Internal Transfer'),
                onTap: () {
                  Get.back();
                  Get.toNamed(AppRoutes.STOCK_ENTRY_FORM, arguments: {
                    'name': '',
                    'mode': 'new',
                    'stockEntryType': 'Material Transfer',
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
    fetchPendingPosUploads();

    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select POS Upload', style: Theme.of(context).textTheme.titleLarge),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Get.back()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: filterPosUploads,
                    decoration: InputDecoration(
                      labelText: 'Search (KX/MX Only)',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Obx(() {
                      if (isFetchingPosUploads.value) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (posUploadsForSelection.isEmpty) {
                        return const Center(child: Text('No matching POS Uploads found.'));
                      }

                      return ListView.separated(
                        controller: scrollController,
                        itemCount: posUploadsForSelection.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final pos = posUploadsForSelection[index];
                          // --- UPDATED UI with Status, Total Qty, Date ---
                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.shade200)
                            ),
                            child: InkWell(
                              onTap: () {
                                Get.back();
                                Get.toNamed(AppRoutes.STOCK_ENTRY_FORM, arguments: {
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(pos.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                              color: Colors.orange.shade50,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.orange.shade200)
                                          ),
                                          child: Text(pos.status, style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
                                        )
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(pos.customer, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 8),
                                    const Divider(height: 1),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.inventory_2_outlined, size: 14, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${pos.totalQty?.toStringAsFixed(0) ?? 0} Items',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                        Text(pos.date, style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
}