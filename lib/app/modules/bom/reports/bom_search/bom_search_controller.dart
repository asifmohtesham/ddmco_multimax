import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/bom_search_result.dart';
import 'package:multimax/app/data/providers/bom_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class BomSearchController extends GetxController {
  final BomProvider _provider = Get.find<BomProvider>();

  // ── Filter field controllers ──────────────────────────────────────────────────

  final TextEditingController itemCodeController = TextEditingController();
  final TextEditingController bomNameController  = TextEditingController();

  // ── State ──────────────────────────────────────────────────────────────────

  final RxBool isLoading = false.obs;
  final RxBool canRun    = false.obs;
  final RxList<BomSearchResult> results = <BomSearchResult>[].obs;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    // Mirror itemCode text into canRun so the Run button reacts reactively.
    itemCodeController.addListener(_onItemCodeChanged);
  }

  @override
  void onClose() {
    itemCodeController.removeListener(_onItemCodeChanged);
    itemCodeController.dispose();
    bomNameController.dispose();
    super.onClose();
  }

  void _onItemCodeChanged() {
    canRun.value = itemCodeController.text.trim().isNotEmpty;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Runs the BOM Search report with current filter values.
  /// Blocked if [itemCode] is empty — guard enforced both here and
  /// in the UI via [canRun].
  Future<void> runReport() async {
    final itemCode = itemCodeController.text.trim();
    if (itemCode.isEmpty) {
      GlobalSnackbar.warning(
        title:   'Filter Required',
        message: 'Please enter an Item Code to search.',
      );
      return;
    }

    isLoading.value = true;
    results.clear();

    try {
      final bomName  = bomNameController.text.trim();
      final response = await _provider.getBomSearch(
        itemCode: itemCode,
        bomName:  bomName.isEmpty ? null : bomName,
      );

      if (response.statusCode == 200) {
        final message = response.data['message'] as Map<String, dynamic>?;
        if (message != null) {
          // Frappe query_report columnar shape:
          //   message.columns → List of column definitions (Map or String)
          //   message.result  → List<List<dynamic>> rows
          final rawColumns = message['columns'] as List<dynamic>? ?? [];
          final rawRows    = message['result']  as List<dynamic>? ?? [];

          // Resolve lowercase fieldname from a column definition.
          String _fieldname(dynamic col) {
            if (col is Map) {
              return (col['fieldname'] as String? ?? '').toLowerCase();
            }
            return col.toString().toLowerCase();
          }

          final colKeys = rawColumns.map(_fieldname).toList();

          final parsed = <BomSearchResult>[];
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

  /// Clears results and resets both filter fields.
  void clearAll() {
    itemCodeController.clear();
    bomNameController.clear();
    results.clear();
    // canRun resets automatically via the itemCode listener.
  }
}
