import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/data/providers/pricing_rule_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';

class PricingRuleController extends GetxController {
  final PricingRuleProvider _provider = Get.find<PricingRuleProvider>();

  final scrollController = ScrollController();

  final rules = <PricingRule>[].obs;
  final isLoading = true.obs;
  final isFetchingMore = false.obs;
  final hasMore = true.obs;

  /// '' | Active | Upcoming | Expired | Disabled
  final status = ''.obs;

  /// For DocTypeListHeader: {'side': 'Selling' | 'Buying'}.
  final activeFilters = <String, dynamic>{}.obs;
  final searchQuery = ''.obs;

  /// Keyed by status ('' = all). Active is derived (all − others).
  final statusCounts = <String, int>{}.obs;

  static const List<String> statuses = ['Active', 'Upcoming', 'Expired', 'Disabled'];
  static const int _limit = 20;
  int _page = 0;
  Timer? _debounce;

  String get side => (activeFilters['side'] as String?) ?? '';

  bool get hasActiveFilters =>
      status.value.isNotEmpty || side.isNotEmpty || searchQuery.value.isNotEmpty;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
  }

  @override
  void onReady() {
    super.onReady();
    loadCounts();
    fetchRules();
  }

  @override
  void onClose() {
    _debounce?.cancel();
    scrollController.dispose();
    super.onClose();
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final p = scrollController.position;
    if (p.pixels >= p.maxScrollExtent * 0.9 &&
        hasMore.value &&
        !isFetchingMore.value &&
        !isLoading.value) {
      fetchRules(isLoadMore: true);
    }
  }

  Future<void> loadCounts() async {
    const dt = 'Pricing Rule';
    final today = DateTime.now();
    try {
      final c = await Future.wait([
        _provider.count(const []),
        _provider.count([
          [dt, 'disable', '=', 1]
        ]),
        _provider.count([
          [dt, 'disable', '=', 0],
          ...validityQuery(dt, ValidityState.upcoming, today).filters,
        ]),
        _provider.count([
          [dt, 'disable', '=', 0],
          ...validityQuery(dt, ValidityState.expired, today).filters,
        ]),
      ]);
      final all = c[0], disabled = c[1], upcoming = c[2], expired = c[3];
      statusCounts.assignAll({
        '': all,
        'Active': (all - disabled - upcoming - expired).clamp(0, all).toInt(),
        'Upcoming': upcoming,
        'Expired': expired,
        'Disabled': disabled,
      });
    } catch (_) {}
  }

  Future<void> fetchRules({bool isLoadMore = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      _page = 0;
      hasMore.value = true;
    }
    try {
      final q = buildPricingRuleQuery(
        status: status.value,
        side: side,
        search: searchQuery.value,
        today: DateTime.now(),
      );
      final res = await _provider.getRules(
        limit: _limit,
        limitStart: _page * _limit,
        filters: q.filters,
        orFilters: q.orFilters,
      );
      final page = [
        for (final e in (res.data['data'] as List?) ?? const [])
          PricingRule.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
      await _provider.attachTargets(page);
      hasMore.value = page.length == _limit;
      if (isLoadMore) {
        rules.addAll(page);
      } else {
        rules.assignAll(page);
      }
      _page++;
    } catch (_) {
      GlobalSnackbar.error(message: 'Failed to load pricing rules');
    } finally {
      isLoading.value = false;
      isFetchingMore.value = false;
    }
  }

  void selectStatus(String value) {
    if (status.value == value) return;
    status.value = value;
    fetchRules();
  }

  void setSide(String value) {
    if (value.isEmpty) {
      activeFilters.remove('side');
    } else {
      activeFilters['side'] = value;
    }
    fetchRules();
  }

  void onSearchChanged(String query) {
    searchQuery.value = query;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), fetchRules);
  }

  void clearFilters() {
    status.value = '';
    activeFilters.clear();
    searchQuery.value = '';
    fetchRules();
  }

  /// Rules are few; refetch the page and counts after the form closes.
  Future<void> openRule(PricingRule? rule) async {
    await Get.toNamed(
      AppRoutes.PRICING_RULE_FORM,
      arguments: {'name': rule?.name ?? '', 'mode': rule == null ? 'new' : 'edit'},
    );
    loadCounts();
    fetchRules();
  }
}
