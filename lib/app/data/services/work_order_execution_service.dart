import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/work_order_model.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';

/// Result returned by [WorkOrderExecutionService.execute].
sealed class ExecuteResult {
  const ExecuteResult();
}

class ExecuteSuccess extends ExecuteResult {
  final String stockEntryName;
  const ExecuteSuccess(this.stockEntryName);
}

class ExecuteAlreadyTransferred extends ExecuteResult {
  const ExecuteAlreadyTransferred();
}

class ExecuteNoTransferRequired extends ExecuteResult {
  const ExecuteNoTransferRequired();
}

class ExecuteFailure extends ExecuteResult {
  final String message;
  const ExecuteFailure(this.message);
}

/// Orchestrates the multi-step "Execute Work Order" workflow.
///
/// Responsibilities:
///   1. Ensure an open Job Card exists for the Work Order.
///   2. Fetch the Job Card and verify it has items (transfer required).
///   3. Generate a Stock Entry draft via the Job Card's make_stock_entry API.
///   4. Save the draft Stock Entry (insert it).
///   5. Submit the saved Stock Entry.
///
/// This class has NO knowledge of UI, Rx state, or form controllers.
class WorkOrderExecutionService {
  final WorkOrderProvider _provider;

  WorkOrderExecutionService({WorkOrderProvider? provider})
      : _provider = provider ?? Get.find<WorkOrderProvider>();

  Future<ExecuteResult> execute(WorkOrder wo) async {
    try {
      // ── Step 1: Ensure open Job Card ──────────────────────────────────
      final jobCardName = await _ensureJobCard(wo);
      if (jobCardName == null) {
        return const ExecuteFailure(
          'Could not create or fetch a Job Card for this Work Order.',
        );
      }

      // ── Step 2: Verify Job Card has items ─────────────────────────────
      final jcItems = await _fetchJobCardItems(jobCardName);
      if (jcItems == null) {
        return const ExecuteFailure('Failed to fetch Job Card details.');
      }
      if (jcItems.isEmpty) {
        // transfer_material_against = "Work Order" — no JC-based transfer needed.
        return const ExecuteNoTransferRequired();
      }

      // ── Step 3: Build Stock Entry draft via server ────────────────────
      final seDraft = await _buildStockEntryDraft(jobCardName);
      if (seDraft == null) {
        return const ExecuteFailure(
          'Failed to generate Stock Entry from Job Card.',
        );
      }

      final seItems = (seDraft['items'] as List?) ?? [];
      if (seItems.isEmpty) {
        return const ExecuteAlreadyTransferred();
      }

      // ── Step 4: Save (insert) the Stock Entry draft ───────────────────
      final seName = await _saveStockEntry(seDraft);
      if (seName == null) {
        return const ExecuteFailure('Failed to save Stock Entry.');
      }

      // ── Step 5: Submit the Stock Entry ────────────────────────────────
      final submitted = await _submitStockEntry(seName);
      if (!submitted) {
        return ExecuteFailure(
          'Stock Entry $seName saved but submit failed. Submit manually.',
        );
      }

      return ExecuteSuccess(seName);
    } on DioException catch (e) {
      return ExecuteFailure(_extractDioMessage(e));
    } catch (e) {
      return ExecuteFailure('Unexpected error: $e');
    }
  }

  // ── Private steps ──────────────────────────────────────────────────────

  Future<String?> _ensureJobCard(WorkOrder wo) async {
    // Check for an existing open Job Card first.
    String? name = await _provider.fetchOpenJobCardName(wo.name);
    if (name != null) return name;

    // None found — create via make_job_card.
    if (wo.operations.isEmpty) return null;

    final payload = wo.operations
        .where((op) => !op.isCompleted && op.pendingQty(wo.qty) > 0)
        .map((op) => op.toJobCardPayload(qty: op.pendingQty(wo.qty)))
        .toList();

    if (payload.isEmpty) return null;

    final res = await _provider.makeJobCard(
      workOrderName: wo.name,
      operations: payload,
    );
    if (res.statusCode != 200) return null;

    // Fetch the freshly created card.
    return _provider.fetchOpenJobCardName(wo.name);
  }

  Future<List?> _fetchJobCardItems(String jobCardName) async {
    final res = await _provider.getJobCard(jobCardName);
    if (res.statusCode != 200 || res.data['data'] == null) return null;
    return (res.data['data']['items'] as List?) ?? [];
  }

  Future<Map<String, dynamic>?> _buildStockEntryDraft(
      String jobCardName) async {
    final res = await _provider.makeStockEntryFromJobCard(jobCardName);
    if (res.statusCode != 200 || res.data['message'] == null) return null;
    return res.data['message'] as Map<String, dynamic>;
  }

  Future<String?> _saveStockEntry(Map<String, dynamic> draft) async {
    final res = await _provider.createStockEntry(draft);
    if (res.statusCode != 200 || res.data['data']?['name'] == null) return null;
    return res.data['data']['name'] as String;
  }

  Future<bool> _submitStockEntry(String name) async {
    final res = await _provider.submitStockEntry(name);
    return res.statusCode == 200;
  }

  String _extractDioMessage(DioException e) {
    try {
      final data = e.response?.data;
      if (data is Map) {
        final exc = data['exception'] as String? ?? '';
        if (exc.isNotEmpty) {
          final idx = exc.indexOf(':');
          return idx != -1 ? exc.substring(idx + 1).trim() : exc.trim();
        }
        return (data['message'] as String? ?? '').trim();
      }
    } catch (_) {}
    return 'Request failed (${e.response?.statusCode})';
  }
}