import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class BatchWiseBalanceController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // ── Filter field controllers ────────────────────────────────────────────────

  final TextEditingController fromDateController  = TextEditingController();
  final TextEditingController toDateController    = TextEditingController();
  final TextEditingController itemCodeController  = TextEditingController();
  final TextEditingController batchNoController   = TextEditingController();
  final TextEditingController warehouseController = TextEditingController();

  // ── State ────────────────────────────────────────────────────────────────────────

  final RxBool isLoading = false.obs;
  final RxList<Map<String, dynamic>> reportData = <Map<String, dynamic>>[].obs;

  // ── Lifecycle ──────────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    // Pre-fill date range: today as both from and to.
    final today = _formatDate(DateTime.now());
    fromDateController.text = today;
    toDateController.text   = today;
  }

  @override
  void onClose() {
    fromDateController.dispose();
    toDateController.dispose();
    itemCodeController.dispose();
    batchNoController.dispose();
    warehouseController.dispose();
    super.onClose();
  }

  // ── Public API ────────────────────────────────────────────────────────────────

  /// Runs the Batch-Wise Balance History report with current filter values.
  Future<void> runReport() async {
    final itemCode = itemCodeController.text.trim();
    final batchNo  = batchNoController.text.trim();

    if (itemCode.isEmpty || batchNo.isEmpty) {
      GlobalSnackbar.warning(
        title:   'Filters Required',
        message: 'Please enter both Item Code and Batch No to run the report.',
      );
      return;
    }

    isLoading.value = true;
    reportData.clear();

    try {
      final warehouse = warehouseController.text.trim();
      final response  = await _apiProvider.getBatchWiseBalance(
        itemCode,
        batchNo,
        warehouse: warehouse.isEmpty ? null : warehouse,
      );

      if (response.statusCode == 200) {
        final message = response.data['message'] as Map<String, dynamic>?;
        if (message != null) {
          // Frappe query_report shape:
          //   message.columns  → List of column definitions
          //   message.result   → List<List<dynamic>> rows
          final rawColumns = message['columns'] as List<dynamic>? ?? [];
          final rawRows    = message['result']  as List<dynamic>? ?? [];

          // Resolve fieldname from column definition (Map or plain String).
          String fieldname(dynamic col) {
            if (col is Map) return (col['fieldname'] as String? ?? '').toLowerCase();
            return col.toString().toLowerCase();
          }

          // Also resolve the human-readable label for display.
          String label(dynamic col) {
            if (col is Map) return (col['label'] as String? ?? col['fieldname'] as String? ?? '');
            return col.toString();
          }

          final colKeys    = rawColumns.map(fieldname).toList();
          final colLabels  = rawColumns.map(label).toList();

          // Convert each row array to a named Map for the list-view.
          final List<Map<String, dynamic>> rows = [];
          for (final row in rawRows) {
            if (row is! List) continue;
            final Map<String, dynamic> map = {};
            for (int i = 0; i < colKeys.length && i < row.length; i++) {
              map[colKeys[i]] = row[i];
            }
            // Attach label map for display convenience.
            map['_labels'] = colLabels;
            rows.add(map);
          }
          reportData.assignAll(rows);
        }
      }
    } catch (e) {
      GlobalSnackbar.error(
        title:   'Report Error',
        message: 'Failed to fetch batch-wise balance: $e',
      );
    } finally {
      isLoading.value = false;
    }
  }

  /// Opens a [DatePickerDialog] and writes the selected date into [controller].
  Future<void> selectDate(
    BuildContext context,
    TextEditingController controller,
  ) async {
    final now    = DateTime.now();
    final picked = await showDatePicker(
      context:     context,
      initialDate: now,
      firstDate:   DateTime(now.year - 5),
      lastDate:    DateTime(now.year + 1),
    );
    if (picked != null) {
      controller.text = _formatDate(picked);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
