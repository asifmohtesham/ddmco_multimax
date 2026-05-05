import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/job_card_model.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';

class JobCardController extends GetxController {
  final JobCardProvider _provider = Get.find<JobCardProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final UserProvider _userProvider = Get.find<UserProvider>();

  // Assigned To (maps to _assign like '%user%')
  final assignedUserId    = ''.obs;
  final assignedUserLabel = ''.obs;

  // Created By (maps to owner = user)
  final createdByUserId    = ''.obs;
  final createdByUserLabel = ''.obs;

  // ── List state ───────────────────────────────────────────────
  var jobCards = <JobCard>[].obs;
  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = false.obs;

  // ── Search & filter ──────────────────────────────────────────
  final searchQuery = ''.obs;
  final activeFilters = <String, dynamic>{}.obs;

  // ── User cache for DocType List pickers ──────────────────────
  var users = <User>[].obs;
  var isFetchingUsers = false.obs;

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
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Preload user list for DocType List pickers
    await fetchUsers();

    // Apply default Assigned To only if caller did not provide one
    if (!activeFilters.containsKey('_assign')) {
      await _ensureDefaultAssignedToFilter();
    }

    // Initial list fetch
    await fetchJobCards(clear: true);
  }

  Future<void> _ensureDefaultAssignedToFilter() async {
    try {
      final response = await _apiProvider.getLoggedUser();
      if (response.statusCode == 200 && response.data['message'] is String) {
        final userId = response.data['message'] as String;
        if (userId.isNotEmpty) {
          // Store as "like" operator array so _buildSearchFilters() passes through
          activeFilters['_assign'] = ['like', '%$userId%'];
          assignedUserId.value     = userId;
          assignedUserLabel.value  = userId; // can be replaced with full name after fetchUsers
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('JobCardController._ensureDefaultAssignedToFilter error: $e');
      }
    }
  }

  void setAssignedToFilter(String? userId, String? label) {
    if (userId == null || userId.isEmpty) {
      assignedUserId.value    = '';
      assignedUserLabel.value = '';
      activeFilters.remove('_assign');
    } else {
      assignedUserId.value    = userId;
      assignedUserLabel.value = label ?? userId;
      // Store full operator tuple so _buildSearchFilters() passes it through
      activeFilters['_assign'] = ['like', '%$userId%'];
    }
    fetchJobCards(clear: true);
  }

  void setCreatedByFilter(String? userId, String? label) {
    if (userId == null || userId.isEmpty) {
      createdByUserId.value    = '';
      createdByUserLabel.value = '';
      activeFilters.remove('owner');
    } else {
      createdByUserId.value    = userId;
      createdByUserLabel.value = label ?? userId;
      // Simple equality – owner = user
      activeFilters['owner'] = userId;
    }
    fetchJobCards(clear: true);
  }

  Future<void> fetchUsers() async {
    if (users.isNotEmpty) return;
    isFetchingUsers.value = true;
    try {
      final response = await _userProvider.getUsers();
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        users.value = data.map((json) => User.fromJson(json)).toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('JobCardController.fetchUsers error: $e');
    } finally {
      isFetchingUsers.value = false;
    }
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
