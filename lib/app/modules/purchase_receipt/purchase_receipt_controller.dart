import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/data/providers/purchase_receipt_provider.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/app_notification.dart';
import 'package:multimax/app/modules/purchase_receipt/widgets/purchase_receipt_po_selection_sheet.dart';

class PurchaseReceiptController extends GetxController {
  final PurchaseReceiptProvider _provider = Get.find<PurchaseReceiptProvider>();
  final PurchaseOrderProvider _poProvider = Get.find<PurchaseOrderProvider>();

  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;
  var purchaseReceipts = <PurchaseReceipt>[].obs;
  final int _limit = 20;
  int _currentPage = 0;

  // Sorting state
  var sortField = 'creation'.obs;
  var sortOrder = 'desc'.obs;

  var expandedReceiptName = ''.obs;
  var isLoadingDetails = false.obs;
  final _detailedReceiptsCache = <String, PurchaseReceipt>{}.obs;

  final activeFilters = <String, dynamic>{}.obs;

  // PO selection
  var isFetchingPOs = false.obs;
  var purchaseOrdersForSelection = <PurchaseOrder>[].obs;
  List<PurchaseOrder> _allFetchedPOs = [];

  PurchaseReceipt? get detailedReceipt =>
      _detailedReceiptsCache[expandedReceiptName.value];

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

  // ── Sorting / filtering ───────────────────────────────────────────────

  void setSort(String field, String order) {
    sortField.value = field;
    sortOrder.value = order;
    fetchPurchaseReceipts(isLoadMore: false, clear: true);
  }

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchPurchaseReceipts(isLoadMore: false, clear: true);
  }

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetchPurchaseReceipts(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    fetchPurchaseReceipts(isLoadMore: false, clear: true);
  }

  // ── List fetching ──────────────────────────────────────────────────────

  Future<void> fetchPurchaseReceipts(
      {bool isLoadMore = false, bool clear = false}) async {
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
      final orderBy = '${sortField.value} ${sortOrder.value}';
      final response = await _provider.getPurchaseReceipts(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: activeFilters,
        orderBy: orderBy,
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newReceipts =
            data.map((json) => PurchaseReceipt.fromJson(json)).toList();

        if (newReceipts.length < _limit) hasMore.value = false;

        if (isLoadMore) {
          purchaseReceipts.addAll(newReceipts);
        } else {
          purchaseReceipts.value = newReceipts;
        }
        _currentPage++;
      } else {
        AppNotification.error(message: 'Failed to fetch purchase receipts');
      }
    } catch (e) {
      AppNotification.error(message: e.toString());
    } finally {
      if (isLoadMore) {
        isFetchingMore.value = false;
      } else {
        isLoading.value = false;
      }
    }
  }

  // ── Expanded-row detail cache ────────────────────────────────────────────

  Future<void> _fetchAndCacheReceiptDetails(String name) async {
    if (_detailedReceiptsCache.containsKey(name)) return;
    isLoadingDetails.value = true;
    try {
      final response = await _provider.getPurchaseReceipt(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final receipt = PurchaseReceipt.fromJson(response.data['data']);
        _detailedReceiptsCache[name] = receipt;
      } else {
        AppNotification.error(message: 'Failed to fetch receipt details');
      }
    } catch (e) {
      AppNotification.error(message: e.toString());
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

  // ── PO selection (used by PurchaseReceiptPoSelectionSheet) ─────────────────

  Future<void> fetchPurchaseOrdersForSelection() async {
    isFetchingPOs.value = true;
    purchaseOrdersForSelection.clear();
    _allFetchedPOs = [];
    try {
      final response = await _poProvider.getPurchaseOrders(
        limit: 0,
        filters: {'docstatus': 1, 'status': ['!=', 'Closed']},
      );
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        _allFetchedPOs =
            data.map((json) => PurchaseOrder.fromJson(json)).toList();
        purchaseOrdersForSelection.value = _allFetchedPOs;
      }
    } catch (e) {
      AppNotification.error(message: 'Failed to fetch Purchase Orders');
    } finally {
      isFetchingPOs.value = false;
    }
  }

  void filterPurchaseOrders(String query) {
    if (query.isEmpty) {
      purchaseOrdersForSelection.value = _allFetchedPOs;
      return;
    }
    final q = query.toLowerCase();
    purchaseOrdersForSelection.value = _allFetchedPOs.where((po) {
      return po.name.toLowerCase().contains(q) ||
          po.supplier.toLowerCase().contains(q);
    }).toList();
  }

  void initiatePurchaseReceiptCreation(PurchaseOrder po) {
    Get.toNamed(AppRoutes.PURCHASE_RECEIPT_FORM, arguments: {
      'name': '',
      'mode': 'new',
      'purchaseOrder': po.name,
      'supplier': po.supplier,
    });
  }

  // ── Create dialog ──────────────────────────────────────────────────────

  void openCreateDialog() {
    fetchPurchaseOrdersForSelection();
    Get.bottomSheet(
      const PurchaseReceiptPoSelectionSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }
}
