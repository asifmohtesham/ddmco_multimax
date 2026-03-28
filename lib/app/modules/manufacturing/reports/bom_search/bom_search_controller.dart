import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';

class BomSearchController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  // ── Filter controllers (order matches web BOM Search filter pane) ──────────
  //
  // Section 1 – BOM header
  //   item        : finished good item code
  //   bom         : BOM No
  //
  // Section 2 – Search in sub-assemblies (Item Code 1-5)
  //   item1..item5 : component item codes
  
  final itemController  = TextEditingController();
  final bomController   = TextEditingController();
  final item1Controller = TextEditingController();
  final item2Controller = TextEditingController();
  final item3Controller = TextEditingController();
  final item4Controller = TextEditingController();
  final item5Controller = TextEditingController();

  /// Flat map for passing to [showReportFilterSheet] and [activeFilterCount].
  late final Map<String, TextEditingController> filterControllers;

  // ── State ────────────────────────────────────────────────────────────────────

  final isLoading  = false.obs;
  final reportData = <Map<String, dynamic>>[].obs;

  /// Reactive map of key → display-value for active filter chips.
  final activeFilters = <String, String>{}.obs;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    filterControllers = {
      'item'  : itemController,
      'bom'   : bomController,
      'item1' : item1Controller,
      'item2' : item2Controller,
      'item3' : item3Controller,
      'item4' : item4Controller,
      'item5' : item5Controller,
    };
  }

  @override
  void onClose() {
    for (final c in filterControllers.values) {
      c.dispose();
    }
    super.onClose();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  int get activeFilterCount =>
      filterControllers.values.where((c) => c.text.trim().isNotEmpty).length;

  void clearFilters() {
    for (final c in filterControllers.values) {
      c.clear();
    }
    activeFilters.clear();
    reportData.clear();
  }

  void clearFilter(String key) {
    filterControllers[key]?.clear();
    activeFilters.remove(key);
  }

  Future<void> runReport() async {
    // Rebuild active filter chip map from current controller values.
    _rebuildActiveFilters();

    isLoading.value = true;
    reportData.clear();

    try {
      final response = await _api.searchBom(
        item:  itemController.text.trim(),
        bom:   bomController.text.trim(),
        item1: item1Controller.text.trim(),
        item2: item2Controller.text.trim(),
        item3: item3Controller.text.trim(),
        item4: item4Controller.text.trim(),
        item5: item5Controller.text.trim(),
      );

      if (response.statusCode == 200) {
        final message = response.data['message'] as Map<String, dynamic>?;
        if (message != null) {
          final rawColumns = message['columns'] as List<dynamic>? ?? [];
          final rawRows    = message['result']  as List<dynamic>? ?? [];

          String fieldname(dynamic col) {
            if (col is Map) return (col['fieldname'] as String? ?? '').toLowerCase();
            return col.toString().split(':').first.toLowerCase();
          }

          final colKeys = rawColumns.map(fieldname).toList();

          final rows = <Map<String, dynamic>>[];
          for (final row in rawRows) {
            if (row is! List) continue;
            final map = <String, dynamic>{};
            for (var i = 0; i < colKeys.length && i < row.length; i++) {
              map[colKeys[i]] = row[i];
            }
            rows.add(map);
          }
          reportData.assignAll(rows);
        }
      }
    } catch (e) {
      GlobalSnackbar.error(
        title:   'BOM Search Error',
        message: 'Failed to run BOM Search: $e',
      );
    } finally {
      isLoading.value = false;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static const _labels = {
    'item'  : 'Item',
    'bom'   : 'BOM No',
    'item1' : 'Item Code 1',
    'item2' : 'Item Code 2',
    'item3' : 'Item Code 3',
    'item4' : 'Item Code 4',
    'item5' : 'Item Code 5',
  };

  void _rebuildActiveFilters() {
    activeFilters.clear();
    filterControllers.forEach((key, ctrl) {
      final v = ctrl.text.trim();
      if (v.isNotEmpty) {
        activeFilters[key] = '${_labels[key] ?? key}: $v';
      }
    });
  }
}
