import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/enums/save_result.dart';
import 'package:multimax/app/data/models/bom_model.dart';
import 'package:multimax/app/data/providers/bom_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';

class BomFormController extends GetxController {
  final BomProvider _provider = Get.find<BomProvider>();

  // ── Route arg ─────────────────────────────────────────────────────────────────
  late String bomName;

  // ── Rx state ────────────────────────────────────────────────────────────────
  final isLoading  = true.obs;
  final isSaving   = false.obs;
  final isDirty    = false.obs;
  final saveResult = SaveResult.idle.obs;

  final bom = Rx<BOM?>(null);

  // ── Inline-editable toggle state ──────────────────────────────────────────────
  // Mirrors bom.isActive / bom.isDefault, but lives separately so the
  // SaveIconButton can be enabled before the server round-trip completes.
  final isActive  = false.obs;
  final isDefault = false.obs;

  // ── Tab index ────────────────────────────────────────────────────────────────
  final tabIndex = 0.obs;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    bomName = Get.arguments?['name'] as String? ?? '';
    _fetchBom();
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────────

  Future<void> _fetchBom() async {
    isLoading.value = true;
    try {
      final res = await _provider.getBom(bomName);
      if (res.statusCode == 200 && res.data['data'] != null) {
        final fetched = BOM.fromJson(res.data['data'] as Map<String, dynamic>);
        bom.value      = fetched;
        isActive.value  = fetched.isActive  == 1;
        isDefault.value = fetched.isDefault == 1;
        isDirty.value   = false;
        saveResult.value = SaveResult.idle;
      } else {
        GlobalSnackbar.error(message: 'Failed to load BOM');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('BomFormController._fetchBom: $e');
      GlobalSnackbar.error(message: 'Error loading BOM');
    } finally {
      isLoading.value = false;
    }
  }

  // ── Inline toggles ───────────────────────────────────────────────────────────────

  /// Flips is_active locally and marks the doc dirty — same UX as Frappe
  /// "Not Saved" state. The PATCH only fires when the user taps SaveIconButton.
  void toggleActive() {
    isActive.value = !isActive.value;
    isDirty.value  = true;
    saveResult.value = SaveResult.idle;
  }

  /// Flips is_default locally and marks the doc dirty.
  void toggleDefault() {
    isDefault.value = !isDefault.value;
    isDirty.value   = true;
    saveResult.value = SaveResult.idle;
  }

  // ── Save ──────────────────────────────────────────────────────────────────────

  Future<void> save() async {
    if (isSaving.value || !isDirty.value || bom.value == null) return;
    isSaving.value   = true;
    saveResult.value = SaveResult.idle;

    try {
      await _provider.patchBom(bomName, {
        'is_active':  isActive.value  ? 1 : 0,
        'is_default': isDefault.value ? 1 : 0,
        'modified':   bom.value!.modified,
      });
      // Reload to get the server-confirmed state + updated 'modified' timestamp.
      await _fetchBom();
      saveResult.value = SaveResult.success;
      isDirty.value    = false;
    } on DioException catch (e) {
      saveResult.value = SaveResult.error;
      String msg = 'Save failed';
      if (e.response?.data is Map) {
        final ex = e.response!.data['exception']?.toString() ?? '';
        if (ex.isNotEmpty) msg = ex.split(':').last.trim();
      }
      GlobalSnackbar.error(message: msg);
    } catch (e) {
      saveResult.value = SaveResult.error;
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isSaving.value = false;
    }
  }

  // ── Discard guard ────────────────────────────────────────────────────────────────

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  // ── Navigate to Work Order form ───────────────────────────────────────────────

  /// Opens the Work Order form pre-filled from this BOM.
  /// Guard: only callable when bom is loaded (bom.value != null).
  void createWorkOrder() {
    final b = bom.value;
    if (b == null) return;
    Get.toNamed(
      AppRoutes.WORK_ORDER_FORM,
      arguments: {
        'mode': 'new',
        'name': '',
        'prefill': {
          'production_item':  b.item,
          'item_name':        b.itemName ?? '',
          'bom_no':           b.name,
          'qty':              b.quantity,
          'wip_warehouse':    b.defaultSourceWarehouse ?? '',
          'fg_warehouse':     b.defaultTargetWarehouse ?? '',
        },
      },
    );
  }
}
