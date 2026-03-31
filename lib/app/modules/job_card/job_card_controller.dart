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
  //
  // Dashboard Job Card KPI card / quick-action calls:
  //   controller.goToJobCard()  — no args → default list
  // OR explicitly with pre-filter:
  //   Get.toNamed(AppRoutes.JOB_CARD, arguments: {
  //     'filters':   {'status': 'Open'},
  //     'pageTitle': 'Open Job Cards',
  //   });
  //
  // _buildFilterMap must NOT wrap pre-seeded filter values with ['=', value]
  // because dashboard-injected values like {'status': 'Open'} are already
  // plain strings, while setFilter() stores ['=', value] tuples. We handle
  // this by storing injected filters in activeFilters as plain values and
  // letting _buildFilterMap detect the type.

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
      final response = await _provider.getJobCards(
        filters: _buildFilterMap(),
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

  // ── Filter map builder ───────────────────────────────────────────────
  //
  // Handles both filter formats:
  //   • Plain value  (injected from dashboard args): {'status': 'Open'}
  //   • Tuple value  (set via setFilter()):           {'status': 'Open'}  ← setFilter now stores plain too
  //
  // Plain-string filters are passed directly; non-string values (already
  // encoded as API operator tuples) are passed through unchanged.

  Map<String, dynamic> _buildFilterMap() {
    final f = <String, dynamic>{};
    if (searchQuery.value.isNotEmpty) {
      f['name'] = ['like', '%${searchQuery.value}%'];
    }
    for (final entry in activeFilters.entries) {
      final val = entry.value;
      // If it's already an operator list (e.g. ['like', '%x%']), pass through.
      // Otherwise wrap as equality filter for the API layer.
      if (val is List) {
        f[entry.key] = val;
      } else {
        f[entry.key] = ['=', val];
      }
    }
    return f;
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
