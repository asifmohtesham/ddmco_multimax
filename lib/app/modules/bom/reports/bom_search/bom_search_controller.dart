import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/bom_search_result.dart';
import 'package:multimax/app/data/providers/bom_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class BomSearchController extends GetxController {
  final BomProvider _provider = Get.find<BomProvider>();

  // ── Sub-assembly text controllers (up to 5 slots) ─────────────────────────
  final List<TextEditingController> subAssemblyControllers =
      List.generate(5, (_) => TextEditingController());

  // ── Rx state ────────────────────────────────────────────────────────────────
  final results   = <BomSearchResult>[].obs;
  final isLoading = false.obs;

  /// Number of filled Item Code slots (drives chip strip + badge).
  final activeCount = 0.obs;

  /// True when Item Code 1 (slot 0) is non-empty — minimum to run the report.
  final canRun = false.obs;

  @override
  void onInit() {
    super.onInit();
    for (final c in subAssemblyControllers) {
      c.addListener(_syncCounts);
    }
  }

  @override
  void onClose() {
    for (final c in subAssemblyControllers) {
      c.dispose();
    }
    super.onClose();
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  void _syncCounts() {
    activeCount.value =
        subAssemblyControllers.where((c) => c.text.trim().isNotEmpty).length;
    canRun.value = subAssemblyControllers[0].text.trim().isNotEmpty;
  }

  // ── Filter / clear ────────────────────────────────────────────────────────

  void clearAll() {
    for (final c in subAssemblyControllers) {
      c.clear();
    }
    results.clear();
  }

  // ── Run report ───────────────────────────────────────────────────────────────

  Future<void> runReport() async {
    final itemCodes = subAssemblyControllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (itemCodes.isEmpty) return;

    isLoading.value = true;
    results.clear();

    try {
      final response = await _provider.bomSearch(itemCodes: itemCodes);
      if (response.statusCode == 200 && response.data['message'] != null) {
        final raw = response.data['message'] as List<dynamic>;
        results.assignAll(raw.map((e) => BomSearchResult.fromJson(
            e as Map<String, dynamic>)));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('BomSearchController.runReport error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  /// Navigate to the BOM Document Form for [bomName].
  /// Guard: silently returns when [bomName] is blank.
  void navigateToBom(String bomName) {
    if (bomName.trim().isEmpty) return;
    Get.toNamed(
      AppRoutes.BOM_FORM,
      arguments: {'name': bomName.trim()},
    );
  }
}
