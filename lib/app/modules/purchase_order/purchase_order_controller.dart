import 'package:get/get.dart';
import 'package:multimax/app/data/models/supplier_model.dart';
import 'package:multimax/app/data/providers/supplier_provider.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class PurchaseOrderController extends GetxController {
  final PurchaseOrderProvider _provider = Get.find<PurchaseOrderProvider>();
  final SupplierProvider _supplierProvider = Get.find<SupplierProvider>();

  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;
  var purchaseOrders = <PurchaseOrder>[].obs;
  final int _limit = 20;
  int _currentPage = 0;

  // Cache for expanded view
  var expandedPoName = ''.obs;
  var isLoadingDetails = false.obs;
  final _detailedPoCache = <String, PurchaseOrder>{}.obs;

  final activeFilters = <String, dynamic>{}.obs;
  var sortField = 'creation'.obs;
  var sortOrder = 'desc'.obs;

  /// Local text-search query — mirrors the pattern in StockEntryController.
  var searchQuery = ''.obs;

  PurchaseOrder? get detailedPo => _detailedPoCache[expandedPoName.value];

  // Supplier list for filter picker
  var suppliers = <SupplierEntry>[].obs;
  var isFetchingSuppliers = false.obs;

  @override
  void onInit() {
    super.onInit();
    fetchPurchaseOrders();
    fetchSuppliers();
  }

  Future<void> fetchSuppliers() async {
    if (suppliers.isNotEmpty) return;
    if (isFetchingSuppliers.value) return;
    isFetchingSuppliers.value = true;
    try {
      final response = await _supplierProvider.getSuppliers(limit: 0);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        suppliers.value =
            data.map((json) => SupplierEntry.fromJson(json)).toList();
      }
    } catch (_) {
      // non-fatal — picker shows empty list
    } finally {
      isFetchingSuppliers.value = false;
    }
  }


  // ── Filter / sort ─────────────────────────────────────────────────────────

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchPurchaseOrders(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    searchQuery.value = '';
    fetchPurchaseOrders(isLoadMore: false, clear: true);
  }

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetchPurchaseOrders(isLoadMore: false, clear: true);
  }

  void setSort(String field, String order) {
    sortField.value = field;
    sortOrder.value = order;
    fetchPurchaseOrders(isLoadMore: false, clear: true);
  }

  // ── Search ────────────────────────────────────────────────────────────────

  /// Debounced handler wired to the SearchBar's [onChanged].
  void onSearchChanged(String val) {
    searchQuery.value = val;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (searchQuery.value == val) {
        fetchPurchaseOrders(clear: true);
      }
    });
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> fetchPurchaseOrders({bool isLoadMore = false, bool clear = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      if (clear) {
        purchaseOrders.clear();
        _currentPage = 0;
        hasMore.value = true;
      }
    }

    try {
      final Map<String, dynamic> queryFilters = Map.from(activeFilters);
      if (searchQuery.value.isNotEmpty) {
        // Search by PO name or supplier name
        queryFilters['name'] = ['like', '%${searchQuery.value}%'];
      }

      final response = await _provider.getPurchaseOrders(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: queryFilters,
        orderBy: '${sortField.value} ${sortOrder.value}',
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newOrders = data.map((json) => PurchaseOrder.fromJson(json)).toList();

        if (newOrders.length < _limit) hasMore.value = false;

        if (isLoadMore) {
          purchaseOrders.addAll(newOrders);
        } else {
          purchaseOrders.value = newOrders;
        }
        _currentPage++;
      } else {
        Get.snackbar('Error', 'Failed to fetch Purchase Orders');
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

  Future<void> _fetchAndCachePoDetails(String name) async {
    if (_detailedPoCache.containsKey(name)) return;
    isLoadingDetails.value = true;
    try {
      final response = await _provider.getPurchaseOrder(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final po = PurchaseOrder.fromJson(response.data['data']);
        _detailedPoCache[name] = po;
      }
    } catch (e) {
      print('Error details: $e');
    } finally {
      isLoadingDetails.value = false;
    }
  }

  void toggleExpand(String name) {
    if (expandedPoName.value == name) {
      expandedPoName.value = '';
    } else {
      expandedPoName.value = name;
      _fetchAndCachePoDetails(name);
    }
  }

  void createNewPO() {
    Get.toNamed(AppRoutes.PURCHASE_ORDER_FORM, arguments: {'name': '', 'mode': 'new'});
  }
}
