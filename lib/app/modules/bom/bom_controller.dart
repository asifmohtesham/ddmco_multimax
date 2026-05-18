import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/bom_model.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/data/providers/bom_provider.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/shared/barcode_listener_mixin.dart';

class BomController extends GetxController with BarcodeListenerMixin {
  final BomProvider _provider = Get.find<BomProvider>();
  final ScanService _scanService = Get.find<ScanService>();

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

  // ── BOM Search filter scan slots ────────────────────────────────────────────
  //
  // Keys must match exactly what is passed to showReportFilterSheet() as
  // ReportFilterField.key values.  Order defines the fill sequence when no
  // field is focused.

  /// Ordered list of item-code slot keys used in the BOM Search Filters sheet.
  static const scanSlotKeys = [
    'item_code_1',
    'item_code_2',
    'item_code_3',
    'item_code_4',
    'item_code_5',
  ];

  /// Text controllers for each BOM Search filter slot.
  /// Initialised in [onInit], disposed in [onClose].
  late final Map<String, TextEditingController> filterControllers;

  /// Focus nodes for each BOM Search filter slot.
  /// Passed to [ReportFilterField.focusNode] so the sheet can track which
  /// field is currently active.
  late final Map<String, FocusNode> filterFocusNodes;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();

    // Initialise TECs and FocusNodes for all scan slots.
    filterControllers = {
      for (final key in scanSlotKeys) key: TextEditingController(),
      'is_active': TextEditingController(),    // ← NEW: backs the Active chip
      'docstatus':  TextEditingController(),   // ← NEW: backs the Submitted chip
    };
    filterFocusNodes = {
      for (final key in scanSlotKeys) key: FocusNode(),
    };

    _applyRouteArguments();
    fetchBOMs(clear: true);
  }

  @override
  void onClose() {
    _debounce?.cancel();
    disposeBarcodeListener(); // ← Safety net: dispose worker if still active.
    for (final c in filterControllers.values) c.dispose();
    for (final n in filterFocusNodes.values)  n.dispose();
    super.onClose();
  }

  // ── BarcodeListenerMixin contract ────────────────────────────────────────────

  /// Routes a hardware scan to the correct filter slot:
  ///   1. If a filter field has focus → fill that field (focused-field priority).
  ///   2. Else → fill the first empty slot in [scanSlotKeys] order.
  ///   3. Duplicate item codes across slots → reject with a snackbar alert.
  @override
  Future<void> handleScan(String raw) async {
    final result = await _scanService.processScan(raw);

    if (result.type != ScanType.item || result.itemCode == null) {
      GlobalSnackbar.error(
        title: 'Scan Failed',
        message: result.message ?? 'Barcode not recognised as an item code.',
      );
      return;
    }

    final resolvedCode = result.itemCode!;

    // ── Duplicate guard ───────────────────────────────────────────────────────
    final alreadySet = filterControllers.entries
        .where((e) => e.value.text.trim() == resolvedCode)
        .map((e) => e.key)
        .toList();

    if (alreadySet.isNotEmpty) {
      GlobalSnackbar.warning(
        title: 'Duplicate Item',
        message: '"$resolvedCode" is already set in slot '
            '${alreadySet.first.replaceAll('_', ' ').toUpperCase()}.',
      );
      return;
    }

    // ── Focused-field priority ────────────────────────────────────────────────
    final focusedKey = scanSlotKeys.firstWhereOrNull(
          (k) => filterFocusNodes[k]?.hasFocus ?? false,
    );

    if (focusedKey != null) {
      filterControllers[focusedKey]!.text = resolvedCode;
      return;
    }

    // ── First-empty-slot fallback ─────────────────────────────────────────────
    final emptyKey = scanSlotKeys.firstWhereOrNull(
          (k) => filterControllers[k]!.text.trim().isEmpty,
    );

    if (emptyKey != null) {
      filterControllers[emptyKey]!.text = resolvedCode;
      return;
    }

    // All slots are filled.
    GlobalSnackbar.warning(
      title: 'All Slots Filled',
      message: 'All item code fields already have a value. '
          'Clear one before scanning again.',
    );
  }

  // ── Convenience: clear all filter TECs ────────────────────────────────────────
  void clearFilterControllers() {
    for (final c in filterControllers.values) c.clear();
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
