import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/bom_search_result.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/data/providers/bom_provider.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

/// Controller for the BOM Search report screen.
///
/// Filter model:
///   subAssemblyControllers[0] → Item Code 1 (required — gates [canRun])
///   subAssemblyControllers[1–4] → Item Code 2–5 (optional sub-assembly filters)
///
/// Scan behaviour (hardware key → DataWedgeService):
///   1. ScanService.processScan resolves barcode → Item Code.
///   2. First empty slot (0–4) receives the resolved Item Code.
///   3. runReport() fires automatically when canRun is true
///      (i.e. slot-0 / Item Code 1 is non-empty).
///
/// BOM No filter is intentionally absent (removed per product decision).
class BomSearchController extends GetxController {
  final BomProvider      _provider    = Get.find<BomProvider>();
  final DataWedgeService _dataWedge   = Get.find<DataWedgeService>();
  final ScanService      _scanService = Get.find<ScanService>();

  // ── Item Code 1–5 TECs ─────────────────────────────────────────────────────────────

  /// Five Item Code controllers.
  ///   Index 0 → Item Code 1 (required, drives [canRun]).
  ///   Index 1–4 → Item Code 2–5 (optional sub-assembly filters).
  final List<TextEditingController> subAssemblyControllers =
      List.generate(5, (_) => TextEditingController());

  // ── Reactive state ───────────────────────────────────────────────────────────────

  final RxBool isLoading  = false.obs;
  final RxBool isScanning = false.obs;
  final RxBool canRun     = false.obs;

  /// Number of Item Code slots that are currently filled (1–5).
  /// Used to badge the filter icon on the main screen.
  final RxInt activeCount = 0.obs;

  final RxList<BomSearchResult> results = <BomSearchResult>[].obs;

  // ── Internals ──────────────────────────────────────────────────────────────────

  Worker? _scanWorker;

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    for (final c in subAssemblyControllers) {
      c.addListener(_onFieldsChanged);
    }
    _scanWorker = ever(_dataWedge.scannedCode, (String code) {
      if (code.isNotEmpty) _handleScan(code);
    });
  }

  @override
  void onClose() {
    _scanWorker?.dispose();
    for (final c in subAssemblyControllers) {
      c
        ..removeListener(_onFieldsChanged)
        ..dispose();
    }
    super.onClose();
  }

  // ── Field change listener ───────────────────────────────────────────────────

  void _onFieldsChanged() {
    // canRun is gated exclusively on Item Code 1 (slot 0) being non-empty.
    canRun.value = subAssemblyControllers[0].text.trim().isNotEmpty;
    // activeCount counts all filled slots for the badge.
    activeCount.value = subAssemblyControllers
        .where((c) => c.text.trim().isNotEmpty)
        .length;
  }

  // ── Scan handler ────────────────────────────────────────────────────────────────

  /// Resolves [barcode] → Item Code via [ScanService], deposits it into the
  /// first empty sub-assembly slot (Item Code 1 → 5), then auto-runs the
  /// report when [canRun] is true.
  Future<void> _handleScan(String barcode) async {
    if (isScanning.value) return;
    isScanning.value = true;
    try {
      final result = await _scanService.processScan(barcode);

      // Accept item or batch scan types — both carry a resolved itemCode.
      String? resolved;
      if (result.type == ScanType.item || result.type == ScanType.batch) {
        resolved = result.itemData?.itemCode ?? result.itemCode;
      } else if (result.isSuccess && result.itemData != null) {
        resolved = result.itemData!.itemCode;
      }

      if (resolved == null || resolved.isEmpty) {
        GlobalSnackbar.error(
            message: result.message ?? 'Item not found for scanned barcode');
        return;
      }

      // Find the first empty slot.
      final emptyCtrl = subAssemblyControllers
          .firstWhereOrNull((c) => c.text.trim().isEmpty);

      if (emptyCtrl == null) {
        GlobalSnackbar.warning(
          message: 'All 5 Item Code fields are filled. '
              'Clear one before scanning again.',
        );
        return;
      }

      emptyCtrl.text = resolved;
      // _onFieldsChanged fires via the TEC listener, but call explicitly
      // to ensure canRun / activeCount are updated synchronously before
      // the runReport() guard below reads canRun.value.
      _onFieldsChanged();

      if (canRun.value) await runReport();
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan error: $e');
    } finally {
      isScanning.value = false;
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────────

  /// Runs the BOM Search report.
  ///
  /// [canRun] (and therefore this method) is gated on Item Code 1 being
  /// non-empty. Item Code 1 maps to the report's required `item` filter.
  /// Item Code 2–5 are passed as `sub_assembly_items`.
  Future<void> runReport() async {
    final itemCode1 = subAssemblyControllers[0].text.trim();
    if (itemCode1.isEmpty) {
      GlobalSnackbar.warning(
        title:   'Filter Required',
        message: 'Item Code 1 is required to run the report.',
      );
      return;
    }

    isLoading.value = true;
    results.clear();

    try {
      final subItems = subAssemblyControllers
          .skip(1) // slots 1–4 only
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final response = await _provider.getBomSearch(
        itemCode:         itemCode1,
        subAssemblyItems: subItems.isEmpty ? null : subItems,
      );

      if (response.statusCode == 200) {
        final message = response.data['message'] as Map<String, dynamic>?;
        if (message != null) {
          final rawColumns = message['columns'] as List<dynamic>? ?? [];
          final rawRows    = message['result']  as List<dynamic>? ?? [];

          String fieldname(dynamic col) {
            if (col is Map) {
              return (col['fieldname'] as String? ?? '').toLowerCase();
            }
            return col.toString().toLowerCase();
          }

          final colKeys = rawColumns.map(fieldname).toList();
          final parsed  = <BomSearchResult>[];
          for (final row in rawRows) {
            if (row is! List) continue;
            parsed.add(BomSearchResult.fromColumnar(colKeys, row));
          }
          results.assignAll(parsed);

          if (parsed.isEmpty) {
            GlobalSnackbar.warning(
              title:   'No Results',
              message: 'No BOMs found for the given filters.',
            );
          }
        }
      }
    } catch (e) {
      GlobalSnackbar.error(
        title:   'Report Error',
        message: 'Failed to run BOM Search: $e',
      );
    } finally {
      isLoading.value = false;
    }
  }

  /// Clears sub-assembly slots 2–5 (Item Code 2–5) only.
  /// Item Code 1 is intentionally preserved so the report can be re-run.
  void clearSubAssemblies() {
    for (int i = 1; i < subAssemblyControllers.length; i++) {
      subAssemblyControllers[i].clear();
    }
    // _onFieldsChanged fires via TEC listeners, but call explicitly for
    // the same synchrony reason as in _handleScan.
    _onFieldsChanged();
  }

  /// Clears all 5 Item Code fields and the results list.
  void clearAll() {
    for (final c in subAssemblyControllers) {
      c.clear();
    }
    results.clear();
    _onFieldsChanged();
  }
}
