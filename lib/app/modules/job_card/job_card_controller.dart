import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/job_card_model.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';

class JobCardController extends GetxController {
  final JobCardProvider _provider = Get.find<JobCardProvider>();

  // ── List state ─────────────────────────────────────────────────────────────
  var jobCards = <JobCard>[].obs;
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
    fetchJobCards(clear: true);
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
      fetchJobCards(clear: true);
    });
  }

  // ── Filter helpers ─────────────────────────────────────────────────────────

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetchJobCards(clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    searchQuery.value = '';
    fetchJobCards(clear: true);
  }

  // ── Fetch ──────────────────────────────────────────────────────────────────

  Future<void> fetchJobCards({
    bool clear = false,
    bool isLoadMore = false,
  }) async {
    if (isLoadMore) {
      if (isFetchingMore.value || !hasMore.value) return;
      isFetchingMore.value = true;
    } else {
      isLoading.value = !clear ? true : jobCards.isEmpty;
      if (clear) {
        _start = 0;
        jobCards.clear();
      }
    }

    try {
      final filters = _buildFilters();
      final response = await _provider.getJobCards(
        filters: filters,
        start: _start,
        limit: _pageSize,
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

  // ── Filter builder ─────────────────────────────────────────────────────────

  List<List<dynamic>> _buildFilters() {
    final f = <List<dynamic>>[];
    if (searchQuery.value.isNotEmpty) {
      f.add(['Job Card', 'name', 'like', '%${searchQuery.value}%']);
    }
    activeFilters.forEach((key, value) {
      if (value is List) {
        f.add(['Job Card', key, value[0], value[1]]);
      } else {
        f.add(['Job Card', key, '=', value]);
      }
    });
    return f;
  }

  // ── KPIs ───────────────────────────────────────────────────────────────────

  int get totalCards => jobCards.length;
  int get openCards => jobCards
      .where((c) =>
          c.status == 'Open' || c.status == 'Work In Progress')
      .length;
  int get completedCards =>
      jobCards.where((c) => c.status == 'Completed').length;

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
