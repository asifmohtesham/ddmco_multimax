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

  void _applyRouteArguments() {
    final args = Get.arguments;
    if (args is! Map) return;

    final rawFilters = args['filters'];
    if (rawFilters is Map<String, dynamic>) {
      activeFilters.addAll(rawFilters);
    }

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

  /// Adds or updates a single filter key and re-fetches the list.
  void setFilter(String key, dynamic value) {
    activeFilters[key] = value;
    fetchBOMs(clear: true);
  }

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
      final (:filters, :orFilters) = _buildSearchFilters();
      final response = await _provider.getBOMs(
        filters: filters,
        orFilters: orFilters,
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

  // ── Filter / OR-filter builder ────────────────────────────────────────────────
  //
  // activeFilters  → AND filters (is_active, docstatus, etc.)
  // searchQuery    → OR filters across all card-visible fields:
  //                    name, item (Item Code), item_name
  //
  // Keeping them separate ensures the server correctly applies:
  //   (name LIKE '%q%' OR item LIKE '%q%' OR item_name LIKE '%q%')
  //   AND is_active = 1   ← if that filter is active
  //
  ({Map<String, dynamic> filters, Map<String, dynamic>? orFilters})
      _buildSearchFilters() {
    // AND filters — all activeFilters entries.
    final f = <String, dynamic>{};
    for (final entry in activeFilters.entries) {
      final val = entry.value;
      f[entry.key] = val is List ? val : ['=', val];
    }

    // OR filters — search query matched across all rendered card fields.
    Map<String, dynamic>? or;
    if (searchQuery.value.isNotEmpty) {
      final q = '%${searchQuery.value}%';
      or = {
        'name':      ['like', q],
        'item':      ['like', q],
        'item_name': ['like', q],
      };
    }

    return (filters: f.isEmpty ? {} : f, orFilters: or);
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
