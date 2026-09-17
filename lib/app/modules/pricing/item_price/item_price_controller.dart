import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/item_price_model.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';

class ItemPriceController extends GetxController {
  final ItemPriceProvider _provider = Get.find<ItemPriceProvider>();

  final scrollController = ScrollController();

  final prices = <ItemPrice>[].obs;
  final isLoading = true.obs;
  final isFetchingMore = false.obs;
  final hasMore = true.obs;

  final priceLists = <PriceListInfo>[].obs;

  /// Row counts keyed by price list name; '' = all lists.
  final listCounts = <String, int>{}.obs;

  /// '' = all lists.
  final selectedPriceList = ''.obs;

  /// Filter-sheet state for DocTypeListHeader: 'validity' → Active|Upcoming|
  /// Expired; 'scoped' / 'batch' / 'zero' → true.
  final activeFilters = <String, dynamic>{}.obs;
  final searchQuery = ''.obs;

  static const int _limit = 20;
  int _page = 0;
  Timer? _debounce;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
  }

  @override
  void onReady() {
    super.onReady();
    loadPriceLists();
    fetchPrices();
  }

  @override
  void onClose() {
    _debounce?.cancel();
    scrollController.dispose();
    super.onClose();
  }

  bool get hasActiveFilters =>
      activeFilters.isNotEmpty || searchQuery.value.isNotEmpty;

  /// Server total for the selected list when nothing narrows it; otherwise
  /// the loaded rows (with "more" affordance).
  int get displayCount {
    final key = selectedPriceList.value;
    if (!hasActiveFilters && listCounts.containsKey(key)) return listCounts[key]!;
    return prices.length;
  }

  bool get countHasMore {
    if (!hasActiveFilters && listCounts.containsKey(selectedPriceList.value)) {
      return false;
    }
    return hasMore.value;
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final p = scrollController.position;
    if (p.pixels >= p.maxScrollExtent * 0.9 &&
        hasMore.value &&
        !isFetchingMore.value &&
        !isLoading.value) {
      fetchPrices(isLoadMore: true);
    }
  }

  FrappeQuery _query() {
    final v = activeFilters['validity'] as String?;
    return buildItemPriceQuery(
      priceList: selectedPriceList.value,
      search: searchQuery.value,
      validity: v == null ? null : ValidityState.values.byName(v.toLowerCase()),
      scoped: activeFilters['scoped'] == true,
      hasBatch: activeFilters['batch'] == true,
      zeroRate: activeFilters['zero'] == true,
      today: DateTime.now(),
    );
  }

  Future<void> loadPriceLists() async {
    try {
      final res = await _provider.getPriceLists();
      priceLists.assignAll([
        for (final e in (res.data['data'] as List?) ?? const [])
          PriceListInfo.fromJson(Map<String, dynamic>.from(e as Map)),
      ]);
      final counts = await Future.wait([
        _provider.count(const []),
        for (final l in priceLists)
          _provider.count([
            ['Item Price', 'price_list', '=', l.name]
          ]),
      ]);
      listCounts.assignAll({
        '': counts.first,
        for (var i = 0; i < priceLists.length; i++)
          priceLists[i].name: counts[i + 1],
      });
    } catch (_) {
      // Chips still work without counts.
    }
  }

  Future<void> fetchPrices({bool isLoadMore = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      _page = 0;
      hasMore.value = true;
    }
    try {
      final q = _query();
      final res = await _provider.getItemPrices(
        limit: _limit,
        limitStart: _page * _limit,
        filters: q.filters,
        orFilters: q.orFilters,
      );
      final rows = [
        for (final e in (res.data['data'] as List?) ?? const [])
          ItemPrice.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
      hasMore.value = rows.length == _limit;
      if (isLoadMore) {
        prices.addAll(rows);
      } else {
        prices.assignAll(rows);
      }
      _page++;
    } catch (_) {
      GlobalSnackbar.error(message: 'Failed to load item prices');
    } finally {
      isLoading.value = false;
      isFetchingMore.value = false;
    }
  }

  void selectPriceList(String name) {
    if (selectedPriceList.value == name) return;
    selectedPriceList.value = name;
    fetchPrices();
  }

  void onSearchChanged(String query) {
    searchQuery.value = query;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), fetchPrices);
  }

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.assignAll(filters);
    fetchPrices();
  }

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetchPrices();
  }

  void clearFilters() {
    activeFilters.clear();
    searchQuery.value = '';
    fetchPrices();
  }

  Future<void> openPrice(ItemPrice? price) async {
    await Get.toNamed(
      AppRoutes.ITEM_PRICE_FORM,
      arguments: {'name': price?.name ?? '', 'mode': price == null ? 'new' : 'edit'},
    );
    if (price == null) {
      loadPriceLists();
      fetchPrices();
    } else {
      loadPriceLists();
      await refreshPrice(price.name);
    }
  }

  /// Re-reads one row after the form; a 404 means it was deleted.
  Future<void> refreshPrice(String name) async {
    try {
      final res = await _provider.getItemPrice(name);
      final data = res.data is Map ? res.data['data'] : null;
      final i = prices.indexWhere((p) => p.name == name);
      if (i != -1 && data is Map) {
        prices[i] = ItemPrice.fromJson(Map<String, dynamic>.from(data));
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        prices.removeWhere((p) => p.name == name);
        loadPriceLists();
      }
    } catch (_) {}
  }
}
