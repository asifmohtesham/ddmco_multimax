import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/bom_model.dart';
import 'package:multimax/app/data/providers/bom_provider.dart';

class BomController extends GetxController {
  final BomProvider _provider = Get.find<BomProvider>();

  // ── List state ──────────────────────────────────────────────────────────────
  var boms = <BOM>[].obs;
  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = false.obs;

  // ── Search & filter ─────────────────────────────────────────────────────────
  final searchQuery = ''.obs;
  final activeFilters = <String, dynamic>{}.obs;

  /// Optional title override injected via [Get.arguments] from the Dashboard
  /// quick-access shortcut (e.g. 'Active BOMs'). Falls back to null so
  /// BomScreen renders its default title when navigated from the drawer.
  String? pageTitle;

  Timer? _debounce;

  static const int _pageSize = 20;
  int _start = 0;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    _applyRouteArguments();
    fetchBOMs(clear: true);
  }

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }

  // ── Route argument injection ─────────────────────────────────────────────────
  //
  // The Dashboard BOM quick-action calls:
  //   Get.toNamed(AppRoutes.BOM, arguments: {
  //     'filters':   {'is_active': 1},
  //     'pageTitle': 'Active BOMs',
  //   });
  //
  // Any other caller that passes no arguments (drawer, back-navigation) gets
  // the default unfiltered list — no breaking change.

  void _applyRouteArguments() {
    final args = Get.arguments;
    if (args is! Map) return;

    // Pre-seed activeFilters
    final rawFilters = args['filters'];
    if (rawFilters is Map<String, dynamic>) {
      activeFilters.addAll(rawFilters);
    }

    // Optional screen title
    final title = args['pageTitle'];
    if (title is String && title.isNotEmpty) {
      pageTitle = title;
    }
  }

  // ── Search ───────────────────────────────────────────────────────────────────

  void onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      searchQuery.value = value;
      fetchBOMs(clear: true);
    });
  }

  // ── Filter helpers ───────────────────────────────────────────────────────────

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetchBOMs(clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    searchQuery.value = '';
    fetchBOMs(clear: true);
  }

  // ── Fetch ────────────────────────────────────────────────────────────────────

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
      final response = await _provider.getBOMs(
        filters: _buildFilterMap(),
        limit: _pageSize,
        limitStart: _start,
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

  // ── Filter map builder ───────────────────────────────────────────────────────

  Map<String, dynamic> _buildFilterMap() {
    final f = <String, dynamic>{};
    if (searchQuery.value.isNotEmpty) {
      f['name'] = ['like', '%${searchQuery.value}%'];
    }
    f.addAll(activeFilters);
    return f;
  }

  // ── KPI Getters ──────────────────────────────────────────────────────────────

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
