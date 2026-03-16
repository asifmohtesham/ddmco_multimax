import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/bom_model.dart';
import 'package:multimax/app/data/providers/bom_provider.dart';

class BomController extends GetxController {
  final BomProvider _provider = Get.find<BomProvider>();

  // ── List state ─────────────────────────────────────────────────────────────
  var boms = <BOM>[].obs;
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
    fetchBOMs(clear: true);
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
      fetchBOMs(clear: true);
    });
  }

  // ── Filter helpers ─────────────────────────────────────────────────────────

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetchBOMs(clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    searchQuery.value = '';
    fetchBOMs(clear: true);
  }

  // ── Fetch ──────────────────────────────────────────────────────────────────

  Future<void> fetchBOMs({
    bool clear = false,
    bool isLoadMore = false,
  }) async {
    if (isLoadMore) {
      if (isFetchingMore.value || !hasMore.value) return;
      isFetchingMore.value = true;
    } else {
      isLoading.value = !clear ? true : boms.isEmpty;
      if (clear) {
        _start = 0;
        boms.clear();
      }
    }

    try {
      final filters = _buildFilters();
      final response = await _provider.getBOMs(
        filters: filters,
        start: _start,
        limit: _pageSize,
      );
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final fetched = data.map((j) => BOM.fromJson(j)).toList();
        boms.addAll(fetched);
        _start += fetched.length;
        hasMore.value = fetched.length == _pageSize;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('BomController.fetch error: $e');
    } finally {
      isLoading.value = false;
      isFetchingMore.value = false;
    }
  }

  // ── Filter builder ─────────────────────────────────────────────────────────

  List<List<dynamic>> _buildFilters() {
    final f = <List<dynamic>>[];
    if (searchQuery.value.isNotEmpty) {
      f.add(['BOM', 'name', 'like', '%${searchQuery.value}%']);
    }
    activeFilters.forEach((key, value) {
      if (value is List) {
        f.add(['BOM', key, value[0], value[1]]);
      } else {
        f.add(['BOM', key, '=', value]);
      }
    });
    return f;
  }

  // ── KPI Getters ─────────────────────────────────────────────────────────────

  int get totalBoms => boms.length;

  int get activeBomsCount => boms.where((b) => b.isActive == 1).length;

  double get activeRate => totalBoms > 0 ? activeBomsCount / totalBoms : 0.0;

  double get averageCost {
    if (totalBoms == 0) return 0.0;
    final total = boms.fold(0.0, (sum, b) => sum + b.totalCost);
    return total / totalBoms;
  }

  List<BOM> get topCostBoms {
    final sorted = List<BOM>.from(boms);
    sorted.sort((a, b) => b.totalCost.compareTo(a.totalCost));
    return sorted.take(5).toList();
  }
}
