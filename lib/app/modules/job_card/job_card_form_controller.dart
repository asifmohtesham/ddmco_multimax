import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/job_card_model.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';

class JobCardFormController extends GetxController {
  final JobCardProvider _provider = Get.find<JobCardProvider>();

  // ── Route args ─────────────────────────────────────────────────────────────────────
  late String name;

  // ── Session employee ──────────────────────────────────────────────────────────────
  /// ERPNext Employee document name linked to the logged-in Frappe user.
  /// Populated once in [onInit] from [StorageService]. Null when the
  /// user account has no linked Employee record.
  String? _sessionEmployeeId;

  // ── Document state ────────────────────────────────────────────────────────────────
  final isLoading        = true.obs;
  final isAddingTimeLog  = false.obs;
  final isUpdatingStatus = false.obs;

  final jobCard = Rx<JobCard?>(null);

  // ── Time log form controllers ──────────────────────────────────────────────────
  final startTimeController    = TextEditingController();
  final completeTimeController = TextEditingController();
  final completedQtyController = TextEditingController();

  // ── Validation state ────────────────────────────────────────────────────────────
  final isStartTimeValid    = false.obs;
  final isCompleteTimeValid = false.obs;
  final isQtyValid          = false.obs;

  // ── Lifecycle ────────────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    name = Get.arguments?['name'] ?? '';

    // Resolve the session employee once at start-up so every time log
    // submission automatically carries the logged-in user's employee record.
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

  // ── Computed guards ──────────────────────────────────────────────────────────────

  /// True when all three time log fields are valid and no submission
  /// is currently in-flight.
  bool get canAddTimeLog =>
      isStartTimeValid.value &&
      isCompleteTimeValid.value &&
      isQtyValid.value &&
      !isAddingTimeLog.value;

  /// True when the Job Card is editable (docstatus 0) and not cancelled.
  bool get canUpdateStatus {
    final jc = jobCard.value;
    if (jc == null || jc.isSubmitted || jc.isCancelled) return false;
    return !isUpdatingStatus.value;
  }

  // ── Fetch document ───────────────────────────────────────────────────────────────

  Future<void> fetchDocument() => _fetchDocument();

  Future<void> _fetchDocument() async {
    isLoading.value = true;
    try {
      final res = await _provider.getJobCard(name);
      if (res.statusCode == 200 && res.data['data'] != null) {
        jobCard.value = JobCard.fromJson(res.data['data']);
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load Job Card');
    } finally {
      isLoading.value = false;
    }
  }

  // ── Prefill ─────────────────────────────────────────────────────────────────────

  void _prefillStartTime() {
    startTimeController.text =
        DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    isStartTimeValid.value = true;
  }

  // ── Validation ──────────────────────────────────────────────────────────────────

  void _validateTimeLogForm() {
    isStartTimeValid.value    = startTimeController.text.isNotEmpty;
    isCompleteTimeValid.value = completeTimeController.text.isNotEmpty;
    final qty = double.tryParse(completedQtyController.text) ?? 0;
    isQtyValid.value = qty > 0;
  }

  // ── Date + time picker ───────────────────────────────────────────────────────────

  /// Date + time picker, same pattern as [WorkOrderFormController.pickDate].
  /// [ctrl] is one of [startTimeController] or [completeTimeController].
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

  // ── Add time log (manual entry) ─────────────────────────────────────────────────

  /// Submit a manual time log entry using the form field values.
  ///
  /// The session user’s linked Employee record is automatically injected
  /// into the [employees] list so every time log carries an employee.
  /// If the logged-in account has no linked Employee, submission proceeds
  /// with an empty list and a warning snackbar is shown to alert the user.
  ///
  /// On success refreshes the document and resets the qty field.
  /// Start time is re-filled with “now” ready for the next entry.
  Future<void> addTimeLog() async {
    if (!canAddTimeLog) return;

    final qty = double.tryParse(completedQtyController.text) ?? 0;

    // Build the employees payload from the session user.
    final List<Map<String, String>> employees = _sessionEmployeeId != null
        ? [{'employee': _sessionEmployeeId!}]
        : [];

    // Warn if no employee is linked — the time log will still be submitted
    // so the user is not blocked, but the record will lack an employee entry.
    if (employees.isEmpty) {
      GlobalSnackbar.warning(
        message:
            'No Employee record linked to your account. '
            'Time log recorded without an employee.',
      );
    }

    isAddingTimeLog.value = true;
    try {
      final res = await _provider.addTimeLog(
        jobCardId:    name,
        startTime:    startTimeController.text,
        completeTime: completeTimeController.text,
        completedQty: qty,
        employees:    employees,
        status:       'Complete',
      );

      if (res.statusCode == 200) {
        await _fetchDocument();
        // Reset for next entry
        completedQtyController.clear();
        completeTimeController.clear();
        _prefillStartTime();
        _validateTimeLogForm();
        GlobalSnackbar.success(message: 'Time log added');
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

  // ── Update status ────────────────────────────────────────────────────────────────

  /// Transition the Job Card to [newStatus].
  ///
  /// Shows a confirmation dialog for destructive transitions
  /// (currently: moving to `Completed`).
  ///
  /// Transitions supported:
  ///   `Open` → `Work In Progress`
  ///   `Work In Progress` → `Open`  (pause)
  ///   `Work In Progress` → `Completed`
  Future<void> updateStatus(String newStatus) async {
    if (!canUpdateStatus) return;

    // Confirm before marking complete
    if (newStatus == JobCard.statusCompleted) {
      final confirmed = await GlobalDialog.confirm(
        title: 'Complete Job Card',
        message: 'Mark this Job Card as Completed? '
            'This cannot be undone without ERPNext admin access.',
        confirmText: 'Complete',
      );
      if (confirmed != true) return;
    }

    isUpdatingStatus.value = true;
    try {
      final res = await _provider.updateJobCardStatus(name, newStatus);
      if (res.statusCode == 200) {
        await _fetchDocument();
        GlobalSnackbar.success(message: 'Status updated to $newStatus');
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

  // ── Helpers ──────────────────────────────────────────────────────────────────────

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
