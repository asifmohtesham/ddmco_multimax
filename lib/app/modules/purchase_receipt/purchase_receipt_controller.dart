import 'package:flutter/material.dart';
import 'package:dio/dio.dart' hide Response;
import 'package:get/get.dart';
import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/data/providers/purchase_receipt_provider.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class PurchaseReceiptController extends GetxController {
  final PurchaseReceiptProvider _provider = Get.find<PurchaseReceiptProvider>();
  final PurchaseOrderProvider _poProvider = Get.find<PurchaseOrderProvider>();

  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;
  var purchaseReceipts = <PurchaseReceipt>[].obs;
  final int _limit = 20;
  int _currentPage = 0;

  var expandedReceiptName = ''.obs;
  var isLoadingDetails = false.obs;
  final _detailedReceiptsCache = <String, PurchaseReceipt>{}.obs;

  final activeFilters = <String, dynamic>{}.obs;

  // For PO Selection
  var isFetchingPOs = false.obs;
  var purchaseOrdersForSelection = <PurchaseOrder>[].obs;
  List<PurchaseOrder> _allFetchedPOs = [];
  var poSearchQuery = ''.obs; // Added for filtering

  PurchaseReceipt? get detailedReceipt => _detailedReceiptsCache[expandedReceiptName.value];

  @override
  void onInit() {
    super.onInit();
    fetchPurchaseReceipts();
  }

  @override
  void onReady() {
    super.onReady();
    if (Get.arguments is Map && Get.arguments['openCreate'] == true) {
      openCreateDialog();
    }
  }

  // ... (Existing Filters, Sorting, Fetch logic unchanged) ...

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchPurchaseReceipts(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    fetchPurchaseReceipts(isLoadMore: false, clear: true);
  }


  Future<void> fetchPurchaseReceipts({bool isLoadMore = false, bool clear = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      if (clear) {
        purchaseReceipts.clear();
        _currentPage = 0;
        hasMore.value = true;
      }
    }

    try {
      final response = await _provider.getPurchaseReceipts(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: activeFilters,
      );
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newReceipts = data.map((json) => PurchaseReceipt.fromJson(json)).toList();

        if (newReceipts.length < _limit) {
          hasMore.value = false;
        }

        if (isLoadMore) {
          purchaseReceipts.addAll(newReceipts);
        } else {
          purchaseReceipts.value = newReceipts;
        }
        _currentPage++;
      } else {
        Get.snackbar('Error', 'Failed to fetch purchase receipts');
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

  Future<void> _fetchAndCacheReceiptDetails(String name) async {
    if (_detailedReceiptsCache.containsKey(name)) {
      return;
    }

    isLoadingDetails.value = true;
    try {
      final response = await _provider.getPurchaseReceipt(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final receipt = PurchaseReceipt.fromJson(response.data['data']);
        _detailedReceiptsCache[name] = receipt;
      } else {
        Get.snackbar('Error', 'Failed to fetch receipt details');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      isLoadingDetails.value = false;
    }
  }

  void toggleExpand(String name) {
    if (expandedReceiptName.value == name) {
      expandedReceiptName.value = '';
    } else {
      expandedReceiptName.value = name;
      _fetchAndCacheReceiptDetails(name);
    }
  }

  // --- Creation Logic ---

  Future<void> fetchPurchaseOrdersForSelection() async {
    isFetchingPOs.value = true;
    try {
      final response = await _poProvider.getPurchaseOrders(limit: 0, filters: {'docstatus': 1, 'status': ['!=', 'Closed']}); // Only Submitted & Not Completed
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        _allFetchedPOs = data.map((json) => PurchaseOrder.fromJson(json)).toList();
        purchaseOrdersForSelection.value = _allFetchedPOs;
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to fetch Purchase Orders');
    } finally {
      isFetchingPOs.value = false;
    }
  }

  void filterPurchaseOrders(String query) {
    if (query.isEmpty) {
      purchaseOrdersForSelection.value = _allFetchedPOs;
    } else {
      final q = query.toLowerCase();
      purchaseOrdersForSelection.value = _allFetchedPOs.where((po) {
        return po.name.toLowerCase().contains(q) ||
            po.supplier.toLowerCase().contains(q);
      }).toList();
    }
  }

  void initiatePurchaseReceiptCreation(PurchaseOrder po) {
    Get.toNamed(AppRoutes.PURCHASE_RECEIPT_FORM, arguments: {
      'name': '',
      'mode': 'new',
      'purchaseOrder': po.name,
      'supplier': po.supplier,
    });
  }

  // Moved from Screen
  void openCreateDialog() {
    fetchPurchaseOrdersForSelection();

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
                      Text(
                        'Select Purchase Order',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Get.back(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: filterPurchaseOrders,
                    decoration: const InputDecoration(
                      labelText: 'Search Purchase Orders',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Obx(() {
                      if (isFetchingPOs.value) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (purchaseOrdersForSelection.isEmpty) {
                        return const Center(child: Text('No Purchase Orders found.'));
                      }

                      return ListView.separated(
                        controller: scrollController,
                        itemCount: purchaseOrdersForSelection.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                        itemBuilder: (context, index) {
                          final po = purchaseOrdersForSelection[index];
                          return ListTile(
                            title: Text(po.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${po.supplier} • ${po.transactionDate}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Get.back();
                              initiatePurchaseReceiptCreation(po);
                            },
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