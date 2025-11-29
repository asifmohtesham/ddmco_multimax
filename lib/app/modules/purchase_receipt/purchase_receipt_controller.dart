import 'package:dio/dio.dart' hide Response;
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/purchase_receipt_model.dart';
import 'package:ddmco_multimax/app/data/providers/purchase_receipt_provider.dart';

class PurchaseReceiptController extends GetxController {
  final PurchaseReceiptProvider _provider = Get.find<PurchaseReceiptProvider>();

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

  PurchaseReceipt? get detailedReceipt => _detailedReceiptsCache[expandedReceiptName.value];

  @override
  void onInit() {
    super.onInit();
    fetchPurchaseReceipts();
  }

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
}
