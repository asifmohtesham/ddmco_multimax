import 'package:get/get.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class PurchaseOrderController extends GetxController {
  final PurchaseOrderProvider _provider = Get.find<PurchaseOrderProvider>();

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
  var sortField = 'modified'.obs;
  var sortOrder = 'desc'.obs;

  PurchaseOrder? get detailedPo => _detailedPoCache[expandedPoName.value];

  @override
  void onInit() {
    super.onInit();
    fetchPurchaseOrders();
  }

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchPurchaseOrders(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    fetchPurchaseOrders(isLoadMore: false, clear: true);
  }

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
      final response = await _provider.getPurchaseOrders(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: activeFilters,
        orderBy: '${sortField.value} ${sortOrder.value}',
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newOrders = data.map((json) => PurchaseOrder.fromJson(json)).toList();

        if (newOrders.length < _limit) {
          hasMore.value = false;
        }

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