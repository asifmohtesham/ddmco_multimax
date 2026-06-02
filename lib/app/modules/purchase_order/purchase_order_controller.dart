import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/models/supplier_model.dart';
import 'package:multimax/app/data/providers/supplier_provider.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/providers/warehouse_provider.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';

class PurchaseOrderController extends GetxController {
  final PurchaseOrderProvider _provider = Get.find<PurchaseOrderProvider>();
  final SupplierProvider _supplierProvider = Get.find<SupplierProvider>();
  final UserProvider _userProvider = Get.find<UserProvider>();
  final WarehouseProvider _warehouseProvider = Get.find<WarehouseProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

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

  // Users for filter
  var users = <User>[].obs;
  var isFetchingUsers = false.obs;

  // Warehouses for filter
  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;
  // Role-gated write access — mirrors StockEntryController
  var writeRoles = <String>['System Manager'].obs;

  @override
  void onInit() {
    super.onInit();
    fetchPurchaseOrders();
    fetchSuppliers();
    fetchUsers();
    fetchWarehouses();
    fetchDocTypePermissions();
  }

  @override
  void onReady() {
    super.onReady();
    // onReady fires after the first frame; safe place for deferred work.
    // Reserved for future use (e.g. deep-link argument handling).
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
      // non-fatal — picker shows empty list
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
        warehouses.value = data.map((e) => e['name'].toString()).toList();
      }
    } catch (e) {
      // non-fatal — picker shows empty list
    } finally {
      isFetchingWarehouses.value = false;
    }
  }

  Future<void> fetchDocTypePermissions() async {
    try {
      final response = await _apiProvider.getDocument('DocType', 'Purchase Order');
      if (response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'];
        final List<dynamic> perms = data['permissions'] ?? [];
        final newRoles = <String>{'System Manager'};
        for (var p in perms) {
          if (p['write'] == 1 && (p['permlevel'] == 0 || p['permlevel'] == null)) {
            newRoles.add(p['role']);
          }
        }
        writeRoles.assignAll(newRoles.toList());
      }
    } catch (e) {
      print('Error fetching permissions: $e');
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
        GlobalDialog.showError(
          title: 'Could not load Purchase Orders',
          message: 'The server returned an unexpected response. '
              'Check your connection and try again.',
          onRetry: () => fetchPurchaseOrders(isLoadMore: isLoadMore, clear: clear),
        );
      }
    } catch (e) {
      GlobalDialog.showError(
        title: 'Could not load Purchase Orders',
        message: e.toString(),
        onRetry: () => fetchPurchaseOrders(isLoadMore: isLoadMore, clear: clear),
      );
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
      } else {
        GlobalDialog.showError(
          title: 'Could not load PO details',
          message: 'Failed to fetch details for $name. '
              'Check your connection and try again.',
          onRetry: () => _fetchAndCachePoDetails(name),
        );
      }
    } catch (e) {
      GlobalDialog.showError(
        title: 'Could not load PO details',
        message: e.toString(),
        onRetry: () => _fetchAndCachePoDetails(name),
      );
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

  void openCreateDialog() {
    Get.toNamed(AppRoutes.PURCHASE_ORDER_FORM, arguments: {'name': '', 'mode': 'new'});
  }
}