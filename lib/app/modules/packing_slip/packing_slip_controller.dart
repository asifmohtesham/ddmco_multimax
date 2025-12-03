import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/packing_slip_model.dart';
import 'package:ddmco_multimax/app/data/providers/packing_slip_provider.dart';
import 'package:ddmco_multimax/app/modules/home/home_controller.dart';

class PackingSlipController extends GetxController {
  final PackingSlipProvider _provider = Get.find<PackingSlipProvider>();
  final HomeController _homeController = Get.find<HomeController>();

  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;
  var packingSlips = <PackingSlip>[].obs;
  final int _limit = 20;
  int _currentPage = 0;

  var expandedSlipName = ''.obs;
  
  final activeFilters = <String, dynamic>{}.obs;
  var sortField = 'creation'.obs;
  var sortOrder = 'desc'.obs;

  @override
  void onInit() {
    super.onInit();
    _homeController.activeScreen.value = ActiveScreen.packingSlip;
    // Assuming Packing Slip drawer index is handled elsewhere or I should set it if known.
    // _homeController.selectedDrawerIndex.value = ...; 
    fetchPackingSlips();
  }

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchPackingSlips(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    fetchPackingSlips(isLoadMore: false, clear: true);
  }

  void setSort(String field, String order) {
    sortField.value = field;
    sortOrder.value = order;
    fetchPackingSlips(isLoadMore: false, clear: true);
  }

  Future<void> fetchPackingSlips({bool isLoadMore = false, bool clear = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      if (clear) {
        packingSlips.clear();
        _currentPage = 0;
        hasMore.value = true;
      }
    }

    try {
      final response = await _provider.getPackingSlips(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: activeFilters,
        orderBy: '${sortField.value} ${sortOrder.value}',
      );
      
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newSlips = data.map((json) => PackingSlip.fromJson(json)).toList();

        if (newSlips.length < _limit) {
          hasMore.value = false;
        }

        if (isLoadMore) {
          packingSlips.addAll(newSlips);
        } else {
          packingSlips.value = newSlips;
        }
        _currentPage++;
      } else {
        Get.snackbar('Error', 'Failed to fetch packing slips');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      if (isLoadMore) {
        isFetchingMore.value = false;
      }
      if (isLoading.value) {
        isLoading.value = false;
      }
    }
  }

  void toggleExpand(String name) {
    if (expandedSlipName.value == name) {
      expandedSlipName.value = '';
    } else {
      expandedSlipName.value = name;
    }
  }
}
