import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/job_card_model.dart';
import 'package:multimax/app/data/models/job_card_time_log_model.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';

class JobCardFormController extends GetxController {
  final JobCardProvider _provider = Get.find<JobCardProvider>();

  // ── Route args ────────────────────────────────────────────────────────────
  late String name;

  // ── Session employee ──────────────────────────────────────────────────────
  String? _sessionEmployeeId;
  bool get hasLinkedEmployee =>
      _sessionEmployeeId != null && _sessionEmployeeId!.isNotEmpty;
  List<Map<String, String>> get _employees => hasLinkedEmployee
      ? [{'employee': _sessionEmployeeId!}]
      : [];

  // ── Document state ────────────────────────────────────────────────────────
  final isLoading        = true.obs;
  final isAddingTimeLog  = false.obs;
  final isUpdatingStatus = false.obs;
  final isEditingTimeLog = false.obs;

  final jobCard = Rx<JobCard?>(null);

  // ── Add time log form controllers ─────────────────────────────────────────
  final startTimeController    = TextEditingController();
  final completeTimeController = TextEditingController();
  final completedQtyController = TextEditingController();

  // ── Validation state ──────────────────────────────────────────────────────
  final isStartTimeValid    = false.obs;
  final isCompleteTimeValid = false.obs;
  final isQtyValid          = false.obs;
  final isQtyOverLimit      = false.obs;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    name = Get.arguments?['name'] ?? '';
    _sessionEmployeeId = Get.find<StorageService>().getUser()?.employeeId;

    startTimeController.addListener(_validateTimeLogForm);
    completeTimeController.addListener(_validateTimeLogForm);
    completedQtyController.addListener(_validateTimeLogForm);

    _prefillStartTime();
    _fetchDocument();
  }

  @override
  void onClose() {
    startTimeController.dispose();
    completeTimeController.dispose();
    completedQtyController.dispose();
    super.onClose();
  }

  // ── Computed guards ───────────────────────────────────────────────────────

  bool get canAddTimeLog =>
      isStartTimeValid.value &&
      isCompleteTimeValid.value &&
      isQtyValid.value &&
      !isQtyOverLimit.value &&
      !isAddingTimeLog.value;

  bool get canUpdateStatus {
    final jc = jobCard.value;
    if (jc == null || jc.isCancelled) return false;
    return !isUpdatingStatus.value;
  }

  /// Qty that can still be logged without exceeding forQuantity.
  double get remainingQty {
    final jc = jobCard.value;
    if (jc == null || jc.forQuantity <= 0) return 0;
    final rem = jc.forQuantity - jc.totalCompletedQty;
    return rem < 0 ? 0 : rem;
  }

  // ── Fetch document ────────────────────────────────────────────────────────

  Future<void> fetchDocument() => _fetchDocument();

  Future<void> _fetchDocument() async {
    isLoading.value = true;
    try {
      final res = await _provider.getJobCard(name);
      if (res.statusCode == 200 && res.data['data'] != null) {
        jobCard.value = JobCard.fromJson(res.data['data']);
        _validateTimeLogForm();
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load Job Card');
    } finally {
      isLoading.value = false;
    }
  }

  // ── Prefill ───────────────────────────────────────────────────────────────

  void _prefillStartTime() {
    startTimeController.text =
        DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    isStartTimeValid.value = true;
  }

  // ── Validation ────────────────────────────────────────────────────────────

  void _validateTimeLogForm() {
    isStartTimeValid.value    = startTimeController.text.isNotEmpty;
    isCompleteTimeValid.value = completeTimeController.text.isNotEmpty;

    final qty = double.tryParse(completedQtyController.text) ?? 0;
    final jc  = jobCard.value;
    isQtyValid.value = qty > 0;

    if (jc != null && jc.forQuantity > 0 && qty > 0) {
      isQtyOverLimit.value =
          (jc.totalCompletedQty + qty) > jc.forQuantity;
    } else {
      isQtyOverLimit.value = false;
    }
  }

  // ── Date + time picker ────────────────────────────────────────────────────

  Future<void> pickDateTime(TextEditingController ctrl) async {
    final now = DateTime.now();
    DateTime initial = now;
    try {
      if (ctrl.text.isNotEmpty) {
        initial = ctrl.text.contains(' ')
            ? DateFormat('yyyy-MM-dd HH:mm:ss').parse(ctrl.text)
            : DateFormat('yyyy-MM-dd').parse(ctrl.text);
      }
    } catch (_) {}

    final pickedDate = await showDatePicker(
      context: Get.context!,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: Get.context!,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );

    final combined = DateTime(
      pickedDate.year, pickedDate.month, pickedDate.day,
      pickedTime?.hour ?? 0, pickedTime?.minute ?? 0,
    );
    ctrl.text = DateFormat('yyyy-MM-dd HH:mm:ss').format(combined);
  }

  // ── Add time log ──────────────────────────────────────────────────────────

  Future<void> addTimeLog() async {
    if (!canAddTimeLog) return;

    final qty = double.tryParse(completedQtyController.text) ?? 0;

    if (_employees.isEmpty) {
      GlobalSnackbar.warning(
        message: 'No Employee record linked. Time log recorded without employee.',
      );
    }

    isAddingTimeLog.value = true;
    try {
      final res = await _provider.addTimeLog(
        jobCardId:    name,
        startTime:    startTimeController.text,
        completeTime: completeTimeController.text,
        completedQty: qty,
        employees:    _employees,
        status:       'Complete',
      );

      if (res.statusCode == 200) {
        await _fetchDocument();
        completedQtyController.clear();
        completeTimeController.clear();
        _prefillStartTime();
        _validateTimeLogForm();
        GlobalSnackbar.success(message: 'Time log added');
        await _submitIfComplete();
      } else {
        GlobalSnackbar.error(message: 'Failed to add time log');
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(
          message: _extractErrorMessage(e, 'Add time log failed'));
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isAddingTimeLog.value = false;
    }
  }

  // ── Edit time log ─────────────────────────────────────────────────────────

  /// Opens the edit bottom sheet for an existing time log row.
  ///
  /// Only callable when the parent Job Card is still in draft (docstatus==0).
  /// The sheet pre-fills [toTime], [completedQty], and [employee] from the
  /// existing row. On save, [updateTimeLog] is called.
  void editTimeLog(JobCardTimeLog log) {
    final jc = jobCard.value;
    if (jc == null || !jc.isEditable) return;
    Get.bottomSheet(
      _EditTimeLogSheet(log: log, controller: this, jobCard: jc),
      isScrollControlled: true,
      backgroundColor: Get.context != null
          ? Theme.of(Get.context!).colorScheme.surface
          : null,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
  }

  /// Persists edits to a time log row via PATCH then refreshes the document.
  ///
  /// [oldQty] is the row's original completedQty before the edit. It is
  /// subtracted from totalCompletedQty before the over-limit check so that
  /// editing a row cannot be falsely rejected because the old qty was already
  /// counted in the parent total.
  Future<void> updateTimeLog({
    required JobCardTimeLog log,
    required String toTime,
    required double completedQty,
    String? employee,
  }) async {
    final jc = jobCard.value;
    if (jc == null || !jc.isEditable) return;

    // Over-limit guard: (totalCompletedQty − old row qty + new qty) ≤ forQty
    if (jc.forQuantity > 0) {
      final projected =
          (jc.totalCompletedQty - log.completedQty) + completedQty;
      if (projected > jc.forQuantity) {
        GlobalSnackbar.error(
          message: 'Qty would exceed Work Order target '
              '(${_fmtQty(jc.forQuantity)}). '
              'Max allowed for this row: '
              '${_fmtQty(jc.forQuantity - (jc.totalCompletedQty - log.completedQty))}',
        );
        return;
      }
    }

    isEditingTimeLog.value = true;
    try {
      final res = await _provider.updateTimeLog(
        timeLogName:  log.name,
        toTime:       toTime,
        completedQty: completedQty,
        employee:     employee,
      );

      if (res.statusCode == 200) {
        // Touch parent so server recalculates total_completed_qty.
        await _provider.touchJobCard(name);
        await _fetchDocument();
        GlobalSnackbar.success(message: 'Time log updated');
        Get.back(); // close the sheet
      } else {
        GlobalSnackbar.error(message: 'Failed to update time log');
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(
          message: _extractErrorMessage(e, 'Update time log failed'));
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isEditingTimeLog.value = false;
    }
  }

  // ── Delete time log ───────────────────────────────────────────────────────

  /// Deletes a time log row after user confirmation, then touches the parent
  /// Job Card so the server recalculates `total_completed_qty`.
  ///
  /// Uses [isEditingTimeLog] as the in-flight guard so that both the edit
  /// and delete icon buttons are disabled while any time-log operation is
  /// running, preventing concurrent mutations.
  Future<void> deleteTimeLog(JobCardTimeLog log) async {
    final jc = jobCard.value;
    if (jc == null || !jc.isEditable) return;

    final confirmed = await GlobalDialog.confirm(
      title:       'Delete Time Log',
      message:     'Remove this time log entry? This cannot be undone.',
      confirmText: 'Delete',
    );
    if (confirmed != true) return;

    isEditingTimeLog.value = true;
    try {
      final res = await _provider.deleteTimeLog(log.name);
      // ERPNext DELETE returns 202 on success.
      if (res.statusCode == 200 || res.statusCode == 202) {
        await _provider.touchJobCard(name);
        await _fetchDocument();
        GlobalSnackbar.success(message: 'Time log deleted');
      } else {
        GlobalSnackbar.error(message: 'Failed to delete time log');
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(
          message: _extractErrorMessage(e, 'Delete time log failed'));
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isEditingTimeLog.value = false;
    }
  }

  // ── Update status ─────────────────────────────────────────────────────────

  Future<void> updateStatus(String newStatus) async {
    if (!canUpdateStatus) return;

    if (newStatus == JobCard.statusCompleted) {
      final confirmed = await GlobalDialog.confirm(
        title: 'Complete Job Card',
        message: 'Mark this Job Card as Completed? '
            'This cannot be undone without ERPNext admin access.',
        confirmText: 'Complete',
      );
      if (confirmed != true) return;
    }

    final String erpNextStatus = switch (newStatus) {
      JobCard.statusWorkInProgress => 'Work In Progress',
      JobCard.statusOpen           => 'Resume Job',
      JobCard.statusCompleted      => 'Complete',
      _                            => newStatus,
    };

    final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final String? completeTime =
        (newStatus == JobCard.statusCompleted) ? now : null;

    isUpdatingStatus.value = true;
    try {
      final res = await _provider.updateJobCardStatus(
        jobCardId:     name,
        erpNextStatus: erpNextStatus,
        startTime:     now,
        completeTime:  completeTime,
        employees:     _employees,
      );

      if (res.statusCode == 200) {
        await _fetchDocument();
        final label = switch (newStatus) {
          JobCard.statusWorkInProgress => 'Started',
          JobCard.statusOpen           => 'Paused',
          JobCard.statusCompleted      => 'Completed',
          _                            => newStatus,
        };
        GlobalSnackbar.success(message: 'Job Card $label');
        if (newStatus == JobCard.statusCompleted) {
          await _submitIfComplete();
        }
      } else {
        GlobalSnackbar.error(message: 'Failed to update status');
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(
          message: _extractErrorMessage(e, 'Status update failed'));
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isUpdatingStatus.value = false;
    }
  }

  // ── Submit helper ─────────────────────────────────────────────────────────

  Future<void> _submitIfComplete() async {
    final jc = jobCard.value;
    if (jc == null) return;
    if (jc.docstatus == 1) return;
    final completed = jc.totalCompletedQty + jc.processLossQty;
    if (jc.forQuantity > 0 && completed < jc.forQuantity) return;

    try {
      final res = await _provider.submitJobCard(name);
      if (res.statusCode == 200) {
        await _fetchDocument();
        GlobalSnackbar.success(message: 'Job Card submitted & Completed');
      } else {
        GlobalSnackbar.error(
            message: 'Time log saved but Job Card submission failed');
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(
          message: _extractErrorMessage(e, 'Job Card submission failed'));
    } catch (e) {
      GlobalSnackbar.error(message: 'Submission error: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmtQty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);

  String _extractErrorMessage(DioException e, String fallback) {
    try {
      if (e.response?.data is Map) {
        final data = e.response!.data as Map;
        final exc = data['exception']?.toString() ?? '';
        if (exc.isNotEmpty) return exc.split(':').last.trim();
        final msg = data['message']?.toString() ?? '';
        if (msg.isNotEmpty) return msg;
      }
    } catch (_) {}
    return fallback;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Time Log Bottom Sheet
//
// Defined here (same file as the controller) so it has direct access to
// JobCardFormController without needing a separate barrel export.
// ─────────────────────────────────────────────────────────────────────────────

class _EditTimeLogSheet extends StatefulWidget {
  final JobCardTimeLog        log;
  final JobCardFormController controller;
  final JobCard               jobCard;

  const _EditTimeLogSheet({
    required this.log,
    required this.controller,
    required this.jobCard,
  });

  @override
  State<_EditTimeLogSheet> createState() => _EditTimeLogSheetState();
}

class _EditTimeLogSheetState extends State<_EditTimeLogSheet> {
  late final TextEditingController _toTimeCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _employeeCtrl;

  String? _qtyError;

  @override
  void initState() {
    super.initState();
    _toTimeCtrl   = TextEditingController(text: widget.log.toTime ?? '');
    _qtyCtrl      = TextEditingController(
        text: widget.log.completedQty > 0
            ? widget.log.completedQty.toString()
            : '');
    _employeeCtrl = TextEditingController(
        text: widget.log.employee ?? '');
  }

  @override
  void dispose() {
    _toTimeCtrl.dispose();
    _qtyCtrl.dispose();
    _employeeCtrl.dispose();
    super.dispose();
  }

  // ── Remaining qty for this row (excluding the old row's contribution) ──
  double get _maxQty {
    final jc = widget.jobCard;
    if (jc.forQuantity <= 0) return double.infinity;
    return jc.forQuantity -
        (jc.totalCompletedQty - widget.log.completedQty);
  }

  void _validateQty(String value) {
    final qty = double.tryParse(value) ?? 0;
    setState(() {
      if (qty <= 0) {
        _qtyError = 'Enter a positive quantity';
      } else if (qty > _maxQty && _maxQty != double.infinity) {
        _qtyError = 'Exceeds WO target. Max for this row: '
            '${widget.controller._fmtQty(_maxQty)}';
      } else {
        _qtyError = null;
      }
    });
  }

  bool get _canSave {
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    return _toTimeCtrl.text.isNotEmpty &&
        qty > 0 &&
        _qtyError == null &&
        !widget.controller.isEditingTimeLog.value;
  }

  Future<void> _pickToTime() async {
    final now = DateTime.now();
    DateTime initial = now;
    try {
      if (_toTimeCtrl.text.isNotEmpty) {
        initial = DateFormat('yyyy-MM-dd HH:mm:ss').parse(_toTimeCtrl.text);
      }
    } catch (_) {}

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );

    final combined = DateTime(
      date.year, date.month, date.day,
      time?.hour ?? 0, time?.minute ?? 0,
    );
    setState(() {
      _toTimeCtrl.text =
          DateFormat('yyyy-MM-dd HH:mm:ss').format(combined);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final padding   = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + padding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Handle ──
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Title ──
          Row(
            children: [
              Icon(Icons.edit_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Edit Time Log',
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'From: ${_truncate(widget.log.fromTime ?? '—')}',
            style: textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),

          // ── To time ──
          _SheetDateTimeField(
            label: 'Complete Time *',
            controller: _toTimeCtrl,
            onTap: _pickToTime,
          ),
          const SizedBox(height: 14),

          // ── Completed qty ──
          TextField(
            controller: _qtyCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onChanged: _validateQty,
            decoration: InputDecoration(
              labelText:   'Completed Qty *',
              border:      const OutlineInputBorder(),
              prefixIcon:  const Icon(Icons.numbers_outlined),
              errorText:   _qtyError,
              errorMaxLines: 2,
              helperText: _qtyError == null && _maxQty != double.infinity
                  ? 'Max for this row: ${widget.controller._fmtQty(_maxQty)}'
                  : null,
            ),
          ),
          const SizedBox(height: 14),

          // ── Employee ──
          TextField(
            controller: _employeeCtrl,
            decoration: const InputDecoration(
              labelText:  'Employee',
              hintText:   'Employee ID (e.g. EMP-0001)',
              border:     OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 20),

          // ── Save button ──
          Obx(() {
            final saving = widget.controller.isEditingTimeLog.value;
            return SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _canSave
                    ? () => widget.controller.updateTimeLog(
                          log:          widget.log,
                          toTime:       _toTimeCtrl.text,
                          completedQty:
                              double.parse(_qtyCtrl.text),
                          employee: _employeeCtrl.text.isNotEmpty
                              ? _employeeCtrl.text.trim()
                              : null,
                        )
                    : null,
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined),
                label: Text(
                  saving ? 'Saving…' : 'Save Changes',
                  style: const TextStyle(fontSize: 15),
                ),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(14)),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _truncate(String dt) =>
      dt.length >= 16 ? dt.substring(0, 16) : dt;
}

/// Reusable read-only date-time field for the edit sheet.
class _SheetDateTimeField extends StatelessWidget {
  final String                label;
  final TextEditingController controller;
  final VoidCallback          onTap;
  const _SheetDateTimeField({
    required this.label,
    required this.controller,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      readOnly:   true,
      onTap:      onTap,
      decoration: InputDecoration(
        labelText:  label,
        border:     const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.schedule_outlined),
        suffixIcon: Icon(Icons.edit_calendar_outlined,
            size: 18, color: cs.primary),
      ),
    );
  }
}
