import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/work_order_model.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';

class WorkOrderController extends GetxController {
  final WorkOrderProvider _provider = Get.find<WorkOrderProvider>();

  // ── List state ─────────────────────────────────────────────────────────────
  var workOrders = <WorkOrder>[].obs;
  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = false.obs;

  // ── Search & filter ────────────────────────────────────────────────────────
  final searchQuery = ''.obs;
  final activeFilters = <String, dynamic>{}.obs;

  Timer? _debounce;

  static const int _pageSize = 20;
  int _start = 0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    fetchWorkOrders(clear: true);
  }

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  void onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      searchQuery.value = value;
      fetchWorkOrders(clear: true);
    });
  }

  // ── Filter helpers ─────────────────────────────────────────────────────────

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetchWorkOrders(clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    searchQuery.value = '';
    fetchWorkOrders(clear: true);
  }

  // ── Fetch ──────────────────────────────────────────────────────────────────

  Future<void> fetchWorkOrders({
    bool clear = false,
    bool isLoadMore = false,
  }) async {
    if (isLoadMore) {
      if (isFetchingMore.value || !hasMore.value) return;
      isFetchingMore.value = true;
    } else {
      isLoading.value = !clear ? true : workOrders.isEmpty;
      if (clear) {
        _start = 0;
        workOrders.clear();
      }
    }

    try {
      final filters = _buildFilters();
      final response = await _provider.getWorkOrders(
        filters: filters,
        start: _start,
        limit: _pageSize,
      );
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final fetched = data.map((j) => WorkOrder.fromJson(j)).toList();
        workOrders.addAll(fetched);
        _start += fetched.length;
        hasMore.value = fetched.length == _pageSize;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('WorkOrderController.fetch error: $e');
    } finally {
      isLoading.value = false;
      isFetchingMore.value = false;
    }
  }

  // ── Filter builder ─────────────────────────────────────────────────────────

  List<List<dynamic>> _buildFilters() {
    final f = <List<dynamic>>[];
    if (searchQuery.value.isNotEmpty) {
      f.add(['Work Order', 'name', 'like', '%${searchQuery.value}%']);
    }
    activeFilters.forEach((key, value) {
      if (value is List) {
        f.add(['Work Order', key, value[0], value[1]]);
      } else {
        f.add(['Work Order', key, '=', value]);
      }
    });
    return f;
  }

  // ── KPIs ───────────────────────────────────────────────────────────────────

  int get totalCount => workOrders.length;

  int get countDraft => workOrders.where((w) => w.status == 'Draft').length;
  int get countConfirmed =>
      workOrders
          .where((w) =>
              w.status == 'Submitted' || w.status == 'Not Started')
          .length;
  int get countInProgress =>
      workOrders.where((w) => w.status == 'In Process').length;
  int get countCompleted =>
      workOrders.where((w) => w.status == 'Completed').length;

  double get totalPlannedQty =>
      workOrders.fold(0.0, (sum, w) => sum + w.qty);
  double get totalProducedQty =>
      workOrders.fold(0.0, (sum, w) => sum + w.producedQty);

  double get overallProgress {
    if (totalPlannedQty == 0) return 0.0;
    return (totalProducedQty / totalPlannedQty).clamp(0.0, 1.0);
  }
}
