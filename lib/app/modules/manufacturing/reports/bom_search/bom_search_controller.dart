import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';

class BomSearchController extends GetxController {
  final ApiProvider      _api  = Get.find<ApiProvider>();
  final DataWedgeService _dw   = Get.find<DataWedgeService>();
  final ScanService      _scan = Get.find<ScanService>();

  // ── Filter controllers ────────────────────────────────────────────────────

  final itemController  = TextEditingController();
  final bomController   = TextEditingController();
  final item1Controller = TextEditingController();
  final item2Controller = TextEditingController();
  final item3Controller = TextEditingController();
  final item4Controller = TextEditingController();
  final item5Controller = TextEditingController();

  late final Map<String, TextEditingController> filterControllers;

  // ── Focus nodes (one per scannable item-code slot) ──────────────────────

  final item1Focus = FocusNode();
  final item2Focus = FocusNode();
  final item3Focus = FocusNode();
  final item4Focus = FocusNode();
  final item5Focus = FocusNode();

  /// The filter key whose field currently has focus in the sheet.
  /// Defaults to 'item1' so the first scan always lands there even if
  /// the user has not tapped a field yet.
  String _focusedKey = 'item1';

  // ── Ordered list used for focus-advance logic ─────────────────────────

  late final List<String> _scanKeys;

  // ── State ──────────────────────────────────────────────────────────────

  final isLoading     = false.obs;
  final isResolving   = false.obs;
  final reportData    = <Map<String, dynamic>>[].obs;
  final activeFilters = <String, String>{}.obs;

  // ── Lifecycle ───────────────────────────────────────────────────────

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

    _scanKeys = ['item1', 'item2', 'item3', 'item4', 'item5'];

    // Wire focus nodes → update _focusedKey whenever a field gains focus.
    final focusMap = {
      'item1': item1Focus,
      'item2': item2Focus,
      'item3': item3Focus,
      'item4': item4Focus,
      'item5': item5Focus,
    };
    focusMap.forEach((key, node) {
      node.addListener(() {
        if (node.hasFocus) _focusedKey = key;
      });
    });

    // Subscribe to DataWedge scan stream.
    ever(_dw.scannedCode, _handleScan);
  }

  @override
  void onClose() {
    for (final c in filterControllers.values) c.dispose();
    item1Focus.dispose();
    item2Focus.dispose();
    item3Focus.dispose();
    item4Focus.dispose();
    item5Focus.dispose();
    super.onClose();
  }

  // ── Scan handler ────────────────────────────────────────────────────

  /// Called by the [ever] worker on every non-empty scan from DataWedge.
  ///
  /// Delegates to [ScanService.processScan] so that:
  /// - A raw EAN-8 is resolved to its 7-digit Item Code.
  /// - An EAN-8 with batch suffix (e.g. `12345670-ABC`) resolves the Item Code
  ///   from the EAN-8 prefix.
  /// - A plain Batch No resolves to its parent Item Code.
  ///
  /// On failure the raw scanned code is written as a fallback so the user
  /// can still correct it manually, and a warning snackbar is shown.
  void _handleScan(String code) {
    if (code.isEmpty) return;
    // Capture the slot that was active at the moment the scan fired,
    // so async resolution always writes to the correct field even if
    // the user taps a different field while the API call is in-flight.
    final targetKey = _focusedKey;
    _resolveAndWrite(code, targetKey);
  }

  Future<void> _resolveAndWrite(String code, String targetKey) async {
    isResolving.value = true;
    try {
      final result = await _scan.processScan(code);

      String resolvedCode;
      if (result.isSuccess && result.itemData != null) {
        resolvedCode = result.itemData!.itemCode;
      } else {
        // Fallback: write the raw scan so the user can see what came in.
        resolvedCode = code;
        GlobalSnackbar.warning(
          title:   'Item Not Resolved',
          message: result.message ?? 'Could not resolve item for: $code',
        );
      }

      filterControllers[targetKey]?.text = resolvedCode;

      // Advance focus to the next empty slot (wrap around if all filled).
      final currentIndex = _scanKeys.indexOf(targetKey);
      for (var i = 1; i <= _scanKeys.length; i++) {
        final nextKey = _scanKeys[(currentIndex + i) % _scanKeys.length];
        if (filterControllers[nextKey]?.text.trim().isEmpty ?? true) {
          _focusedKey = nextKey;
          break;
        }
      }
    } finally {
      isResolving.value = false;
    }
  }

  // ── Public API ─────────────────────────────────────────────────────

  int get activeFilterCount =>
      filterControllers.values.where((c) => c.text.trim().isNotEmpty).length;

  void clearFilters() {
    for (final c in filterControllers.values) c.clear();
    activeFilters.clear();
    reportData.clear();
    _focusedKey = 'item1';
  }

  void clearFilter(String key) {
    filterControllers[key]?.clear();
    activeFilters.remove(key);
  }

  Future<void> runReport() async {
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
          final rows    = <Map<String, dynamic>>[];

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

  // ── Helpers ───────────────────────────────────────────────────────────

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
      if (v.isNotEmpty) activeFilters[key] = '${_labels[key] ?? key}: $v';
    });
  }
}
