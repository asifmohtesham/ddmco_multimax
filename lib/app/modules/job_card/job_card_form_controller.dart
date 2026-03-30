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

  // ── Route args ────────────────────────────────────────────────────────────
  late String name;

  // ── Session employee ──────────────────────────────────────────────────────
  /// ERPNext Employee document name linked to the logged-in Frappe user.
  /// Null when the user account has no linked Employee record.
  String? _sessionEmployeeId;

  /// True when the logged-in user has a linked ERPNext Employee record.
  bool get hasLinkedEmployee =>
      _sessionEmployeeId != null && _sessionEmployeeId!.isNotEmpty;

  /// Employee list payload ready for make_time_log.
  List<Map<String, String>> get _employees => hasLinkedEmployee
      ? [{'employee': _sessionEmployeeId!}]
      : [];

  // ── Document state ────────────────────────────────────────────────────────
  final isLoading        = true.obs;
  final isAddingTimeLog  = false.obs;
  final isUpdatingStatus = false.obs;

  final jobCard = Rx<JobCard?>(null);

  // ── Time log form controllers ─────────────────────────────────────────────
  final startTimeController    = TextEditingController();
  final completeTimeController = TextEditingController();
  final completedQtyController = TextEditingController();

  // ── Validation state ──────────────────────────────────────────────────────
  final isStartTimeValid    = false.obs;
  final isCompleteTimeValid = false.obs;
  final isQtyValid          = false.obs;

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
      !isAddingTimeLog.value;

  bool get canUpdateStatus {
    final jc = jobCard.value;
    if (jc == null || jc.isCancelled) return false;
    return !isUpdatingStatus.value;
  }

  // ── Fetch document ────────────────────────────────────────────────────────

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
    isQtyValid.value = qty > 0;
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

  // ── Add time log (manual entry) ───────────────────────────────────────────

  Future<void> addTimeLog() async {
    if (!canAddTimeLog) return;

    final qty = double.tryParse(completedQtyController.text) ?? 0;

    if (_employees.isEmpty) {
      GlobalSnackbar.warning(
        message: 'No Employee record linked to your account. '
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

  // ── Update status (Start / Pause / Complete) ──────────────────────────────

  /// Transition the Job Card status.
  ///
  /// [newStatus] is the Flutter-side label matching [JobCard] constants:
  ///   `JobCard.statusWorkInProgress` → Start   (maps to ERPNext 'Work In Progress')
  ///   `JobCard.statusOpen`           → Pause   (maps to ERPNext 'Resume Job')
  ///   `JobCard.statusCompleted`      → Complete(maps to ERPNext 'Complete')
  ///
  /// All three transitions go through `make_time_log` because ERPNext
  /// silently ignores a plain REST PUT/PATCH to the `status` field.
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

    // Map Flutter status → ERPNext make_time_log status string.
    // 'Resume Job' is ERPNext's (counter-intuitive) token for Pause:
    // it tells the server to end the current running timer.
    final String erpNextStatus = switch (newStatus) {
      JobCard.statusWorkInProgress => 'Work In Progress',
      JobCard.statusOpen           => 'Resume Job',
      JobCard.statusCompleted      => 'Complete',
      _                            => newStatus,
    };

    final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    // For Complete we send both start and complete times so ERPNext can
    // compute time_in_mins for the auto-created time log row.
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

  // ── Helpers ───────────────────────────────────────────────────────────────

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
