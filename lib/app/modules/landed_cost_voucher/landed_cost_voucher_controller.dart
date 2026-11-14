import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/data/providers/landed_cost_voucher_provider.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class LandedCostVoucherController extends GetxController {
  final LandedCostVoucherProvider _provider =
      Get.find<LandedCostVoucherProvider>();

  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;
  var vouchers = <LandedCostVoucher>[].obs;
  final int _limit = 20;
  int _currentPage = 0;

  var sortField = 'creation'.obs;
  var sortOrder = 'desc'.obs;
  final activeFilters = <String, dynamic>{}.obs;

  final scrollController = ScrollController();

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args is Map && args['filters'] is Map) {
      activeFilters.value = Map<String, dynamic>.from(args['filters'] as Map);
    }
    scrollController.addListener(_onScroll);
    fetchLandedCostVouchers();
  }

  @override
  void onClose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    super.onClose();
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    if (_isBottom && hasMore.value && !isFetchingMore.value) {
      fetchLandedCostVouchers(isLoadMore: true);
    }
  }

  bool get _isBottom {
    if (!scrollController.hasClients) return false;
    return scrollController.offset >=
        scrollController.position.maxScrollExtent * 0.9;
  }

  void setSort(String field, String order) {
    sortField.value = field;
    sortOrder.value = order;
    fetchLandedCostVouchers(isLoadMore: false, clear: true);
  }

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchLandedCostVouchers(isLoadMore: false, clear: true);
  }

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetchLandedCostVouchers(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    fetchLandedCostVouchers(isLoadMore: false, clear: true);
  }

  void openCreateForm() => _openForm({'name': '', 'mode': 'new'});

  void openVoucher(String name) => _openForm({'name': name, 'mode': 'edit'});

  /// Refresh on return: the form may have created, saved or submitted.
  Future<void> _openForm(Map<String, String> args) async {
    await Get.toNamed(AppRoutes.LANDED_COST_VOUCHER_FORM, arguments: args);
    fetchLandedCostVouchers(clear: true);
  }

  Future<void> fetchLandedCostVouchers({
    bool isLoadMore = false,
    bool clear = false,
  }) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      if (clear) {
        vouchers.clear();
        _currentPage = 0;
        hasMore.value = true;
      }
    }

    try {
      final orderBy = '${sortField.value} ${sortOrder.value}';
      final response = await _provider.getLandedCostVouchers(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: activeFilters,
        orderBy: orderBy,
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newVouchers = data
            .map((json) => LandedCostVoucher.fromJson(json))
            .toList();

        if (newVouchers.length < _limit) hasMore.value = false;

        if (isLoadMore) {
          vouchers.addAll(newVouchers);
        } else {
          vouchers.value = newVouchers;
        }
        _currentPage++;
      } else {
        AppNotification.error('Failed to fetch landed cost vouchers');
      }
    } catch (e) {
      AppNotification.error(e.toString());
    } finally {
      if (isLoadMore) {
        isFetchingMore.value = false;
      } else {
        isLoading.value = false;
      }
    }
  }
}
