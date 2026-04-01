import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/job_card_model.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';

class JobCardController extends GetxController {
  final JobCardProvider _provider = Get.find<JobCardProvider>();

  // ── List state ───────────────────────────────────────────────
  var jobCards = <JobCard>[].obs;
  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = false.obs;

  // ── Search & filter ──────────────────────────────────────────
  final searchQuery = ''.obs;
  final activeFilters = <String, dynamic>{}.obs;

  /// Optional title override injected via [Get.arguments] from the Dashboard
  /// quick-access shortcut (e.g. 'Open Job Cards'). Falls back to null so
  /// JobCardScreen renders its default title when navigated from the drawer.
  String? pageTitle;

  Timer? _debounce;

  static const int _pageSize = 20;
  int _start = 0;

  // ── Lifecycle ─────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    _applyRouteArguments();
    fetchJobCards(clear: true);
  }

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }

  // ── Route argument injection ──────────────────────────────────────────

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

  // ── Search ────────────────────────────────────────────────────────────

  void onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      searchQuery.value = value;
      fetchJobCards(clear: true);
    });
  }

  // ── Filter helpers ────────────────────────────────────────────────

  /// Sets [key] to [value], or removes it when [value] is null, then re-fetches.
  void setFilter(String key, String? value) {
    if (value == null) {
      activeFilters.remove(key);
    } else {
      activeFilters[key] = value;
    }
    fetchJobCards(clear: true);
  }

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetchJobCards(clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    searchQuery.value = '';
    fetchJobCards(clear: true);
  }

  // ── Fetch ─────────────────────────────────────────────────────────────

  Future<void> fetchJobCards({
    bool clear = false,
    bool isLoadMore = false,
  }) async {
    if (isLoadMore) {
      if (isFetchingMore.value || !hasMore.value) return;
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      if (clear) {
        _start = 0;
        jobCards.clear();
      }
    }

    try {
      final (:filters, :orFilters) = _buildSearchFilters();
      final response = await _provider.getJobCards(
        filters: filters,
        orFilters: orFilters,
        limit: _pageSize,
        limitStart: _start,
      );
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final fetched = data.map((j) => JobCard.fromJson(j)).toList();
        jobCards.addAll(fetched);
        _start += fetched.length;
        hasMore.value = fetched.length == _pageSize;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('JobCardController.fetch error: $e');
    } finally {
      isLoading.value = false;
      isFetchingMore.value = false;
    }
  }

  // ── Filter / OR-filter builder ───────────────────────────────────────────
  //
  // activeFilters  → AND filters (status, etc.)
  // searchQuery    → OR filters across all card-visible fields:
  //                    name, operation, workstation, status
  //
  ({Map<String, dynamic> filters, Map<String, dynamic>? orFilters})
      _buildSearchFilters() {
    final f = <String, dynamic>{};
    for (final entry in activeFilters.entries) {
      final val = entry.value;
      // Already-encoded operator lists pass through; plain values get '='.
      f[entry.key] = val is List ? val : ['=', val];
    }

    Map<String, dynamic>? or;
    if (searchQuery.value.isNotEmpty) {
      final q = '%${searchQuery.value}%';
      or = {
        'name':        ['like', q],
        'operation':   ['like', q],
        'workstation': ['like', q],
        'status':      ['like', q],
      };
    }

    return (filters: f.isEmpty ? {} : f, orFilters: or);
  }

  // ── KPIs ───────────────────────────────────────────────────────────

  int get totalCards => jobCards.length;

  /// Open + Work In Progress (actionable cards).
  int get openCards => jobCards
      .where((c) =>
          c.status == JobCard.statusOpen ||
          c.status == JobCard.statusWorkInProgress)
      .length;

  /// Cards whose ERPNext status is 'Completed' (docstatus may still be 0).
  int get completedCards =>
      jobCards.where((c) => c.status == JobCard.statusCompleted).length;

  /// Cards that have been submitted to ERPNext (docstatus == 1).
  int get submittedCards =>
      jobCards.where((c) => c.docstatus == 1).length;

  double get totalPlannedQty =>
      jobCards.fold(0.0, (sum, c) => sum + c.forQuantity);
  double get totalCompletedQty =>
      jobCards.fold(0.0, (sum, c) => sum + c.totalCompletedQty);

  Map<String, int> get operationBreakdown {
    final Map<String, int> stats = {};
    for (var card in jobCards) {
      stats[card.operation] = (stats[card.operation] ?? 0) + 1;
    }
    return stats;
  }
}
