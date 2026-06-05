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

  // ── Ordered list used for earliest-empty scan routing ────────────────

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
  /// Writes the derived item code to the earliest empty item-code slot
  /// immediately (no network round-trip).  A background call to
  /// [ScanService.processScan] then silently refines the value if the API
  /// returns a more precise item code.
  void _handleScan(String code) {
    if (code.isEmpty) return;

    final targetKey = _earliestEmptyScanKey();
    if (targetKey == null) return; // All five slots are filled.

    final immediateCode = _deriveItemCodeFromRaw(code);
    filterControllers[targetKey]?.text = immediateCode;

    _refineInBackground(code, targetKey, immediateCode);
  }

  /// Returns the key of the first scan slot ([item1]…[item5]) whose text
  /// field is empty, or [null] when all slots are filled.
  String? _earliestEmptyScanKey() {
    for (final key in _scanKeys) {
      if (filterControllers[key]?.text.trim().isEmpty ?? true) return key;
    }
    return null;
  }

  /// Calls [ScanService.processScan] and updates [targetKey]'s field only when
  /// the resolved code is more precise than [alreadyWritten].  No snackbar is
  /// shown on failure — the immediately-written code is already in the field
  /// and is sufficient for the BOM Search filter.
  Future<void> _refineInBackground(
      String code, String targetKey, String alreadyWritten) async {
    isResolving.value = true;
    try {
      final result = await _scan.processScan(code);
      if (result.isSuccess && result.itemData != null) {
        final resolvedCode = result.itemData!.itemCode;
        if (resolvedCode != alreadyWritten) {
          filterControllers[targetKey]?.text = resolvedCode;
        }
      }
    } finally {
      isResolving.value = false;
    }
  }

  /// Derives a 7-character item code from a raw scanned barcode when the
  /// normal [ScanService.processScan] API lookup has failed.
  ///
  /// Rules (mirror ScanService._isValidEan8 logic):
  /// - Pure 8-digit EAN-8  →  first 7 digits  (strips check digit)
  /// - Hyphenated EAN-8+batch  e.g. `12345670-ABC`  →  first 7 digits of prefix
  /// - Anything else  →  returned unchanged as-is
  String _deriveItemCodeFromRaw(String code) {
    final clean = code.trim();

    // Hyphenated: {EAN8}-{BatchID}
    if (clean.contains('-')) {
      final prefix = clean.split('-').first;
      if (_looksLikeEan8(prefix)) return prefix.substring(0, 7);
    }

    // Pure EAN-8
    if (_looksLikeEan8(clean)) return clean.substring(0, 7);

    // Not EAN-8 — return as-is so the user can see and correct it.
    return clean;
  }

  /// Returns true when [code] is an 8-digit numeric string.
  /// (Does NOT verify the check digit — that is intentional: even a barcode
  /// whose check digit failed validation still encodes the item code in the
  /// first 7 digits and is more useful in the filter than the raw 8 chars.)
  bool _looksLikeEan8(String code) =>
      code.length == 8 && RegExp(r'^\d{8}$').hasMatch(code);

  // ── Public API ─────────────────────────────────────────────────────

  int get activeFilterCount =>
      filterControllers.values.where((c) => c.text.trim().isNotEmpty).length;

  void clearFilters() {
    for (final c in filterControllers.values) c.clear();
    activeFilters.clear();
    reportData.clear();
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
          final rawRows = message['result'] as List<dynamic>? ?? [];
          reportData.assignAll(rawRows.whereType<Map<String, dynamic>>());
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
