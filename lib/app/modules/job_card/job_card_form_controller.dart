import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/mixins/dio_error_mixin.dart';
import 'package:multimax/app/data/models/job_card_model.dart';
import 'package:multimax/app/data/models/job_card_time_log_model.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_config.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_column.dart';

class JobCardFormController extends GetxController with DioErrorMixin {
  final JobCardProvider _provider = Get.find<JobCardProvider>();

  // ── Route args ────────────────────────────────────────────────────────────
  late String name;

  // ── Session employee ──────────────────────────────────────────────────────
  String? _sessionEmployeeId;
  bool get hasLinkedEmployee =>
      _sessionEmployeeId != null && _sessionEmployeeId!.isNotEmpty;
  // ✅ FIX: Widen to Map<String, dynamic> to match provider signature
  List<Map<String, dynamic>> get _employees => hasLinkedEmployee
      ? [{'employee': _sessionEmployeeId!}]
      : [];

  // ── Document state ────────────────────────────────────────────────────────
  final isLoading        = true.obs;
  final isAddingTimeLog  = false.obs;
  final isUpdatingStatus = false.obs;
  final isEditingTimeLog = false.obs;

  // ── Live timer ─────────────────────────────────────────────────────────────

  /// Formatted elapsed time string, e.g. "01:23:45". Empty when no active log.
  final elapsedDisplay = ''.obs;

  /// The start time of the currently-active (open) time log.
  DateTime? _activeLogStart;

  /// Internal periodic ticker.
  Timer? _ticker;

  /// True while submitJobCard() network call is in-flight.
  final isSubmitting = false.obs;

  final jobCard = Rx<JobCard?>(null);

  // ── Editable header fields ────────────────────────────────────────────────
  /// Current value shown in each inline field.  Seeded from the document on
  /// every fetch; updated optimistically on a successful save.
  final headerWorkstation = ''.obs;
  final headerEmployee    = ''.obs;
  final headerWipWarehouse = ''.obs;

  /// Per-field saving spinners — keeps the three fields independent.
  final isSavingWorkstation  = false.obs;
  final isSavingEmployee     = false.obs;
  final isSavingWipWarehouse = false.obs;

  /// DocTypePicker config for the Employee link field.
  static const employeePickerConfig = DocTypePickerConfig(
    doctype: 'Employee',
    title: 'Select Employee',
    columns: [
      DocTypePickerColumn(
        fieldname: 'name',
        label: 'Employee ID',
        isPrimary: true,
        flex: 2,
      ),
      DocTypePickerColumn(
        fieldname: 'employee_name',
        label: 'Employee Name',
        isSecondary: true,
        flex: 3,
      ),
    ],
    subtitleFields: ['department', 'designation'],
    filters: [
      ['Employee', 'status', '=', 'Active'],
    ],
    searchFields: ['name', 'employee_name'],
    cacheKey: 'job_card_employee_picker',
  );

  // ── Add time log form controllers ─────────────────────────────────────────
  final startTimeController    = TextEditingController();
  final completeTimeController = TextEditingController();
  final completedQtyController = TextEditingController();

  // ── Pause sheet state ─────────────────────────────────────────────────────
  final pauseQtyController = TextEditingController();
  final pauseQtyError      = RxnString();   // null = no error

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
    _ticker?.cancel();
    startTimeController.dispose();
    completeTimeController.dispose();
    completedQtyController.dispose();
    pauseQtyController.dispose();
    super.onClose();
  }

  // ── Computed guards ───────────────────────────────────────────────────────

  bool get canConfirmPause {
    final qty = double.tryParse(pauseQtyController.text);
    return qty != null && qty >= 0 && pauseQtyError.value == null;
  }

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

  /// True when the draft can be submitted by the user:
  ///   - document exists and is still draft (docstatus == 0)
  ///   - not cancelled
  ///   - no other operation in-flight
  bool get canSubmit {
    final jc = jobCard.value;
    if (jc == null) return false;
    if (!jc.isEditable) return false;  // docstatus != 0
    if (jc.isCancelled) return false;
    // Must have been started and have at least one time log recorded.
    if (jc.isOpen) return false;
    return !isSubmitting.value &&
           !isUpdatingStatus.value &&
           !isAddingTimeLog.value &&
           !isEditingTimeLog.value;
  }

  /// True when submit preconditions are partially met but job not yet ready.
  /// Used by the UI to show a contextual hint instead of a plain disabled button.
  bool get showSubmitHint {
    final jc = jobCard.value;
    if (jc == null) return false;
    if (!jc.isEditable) return false;
    if (jc.isCancelled) return false;
    if (jc.docstatus == 1) return false;
    // Hint only needed when canSubmit is blocked by start/time-log preconditions.
    return jc.isOpen || jc.timeLogs.isEmpty;
  }

  /// Qty that can still be logged without exceeding forQuantity.
  double get remainingQty {
    final jc = jobCard.value;
    if (jc == null || jc.forQuantity <= 0) return 0;
    final rem = jc.forQuantity - jc.totalCompletedQty;
    return rem < 0 ? 0 : rem;
  }

  void validatePauseQty(String value) {
    final qty = double.tryParse(value) ?? -1;
    final jc  = jobCard.value;
    if (qty < 0) {
      pauseQtyError.value = 'Enter 0 or a positive quantity';
    } else if (jc != null && jc.forQuantity > 0 && qty > remainingQty) {
      pauseQtyError.value =
      'Exceeds remaining qty (max ${_fmtQty(remainingQty)})';
    } else {
      pauseQtyError.value = null;
    }
  }

  // ── Fetch document ────────────────────────────────────────────────────────

  Future<void> fetchDocument() => _fetchDocument();

  Future<void> _fetchDocument() async {
    isLoading.value = true;
    try {
      final res = await _provider.getJobCard(name);
      if (res.statusCode == 200 && res.data['data'] != null) {
        jobCard.value = JobCard.fromJson(res.data['data']);
        _seedHeaderFields();
        _validateTimeLogForm();
        _syncTimer();
      }
    } catch (e, st) {
      debugPrint('❌ _fetchDocument error: $e\n$st');
      GlobalSnackbar.error(message: 'Failed to load Job Card');
    } finally {
      isLoading.value = false;
    }
  }

  /// Starts or stops the live timer depending on job card state.
  ///
  /// An "open" time log is one where [fromTime] is set but [toTime] is null/empty.
  /// This mirrors ERP's own behaviour: time starts counting when a log row
  /// is created with only a from_time, and stops when to_time is filled in.
  void _syncTimer() {
    _ticker?.cancel();
    _ticker = null;
    _activeLogStart = null;
    elapsedDisplay.value = '';

    final jc = jobCard.value;
    if (jc == null || !jc.isWorkInProgress) return;

    // Find the first open time log (no toTime).
    final openLog = jc.timeLogs.cast<JobCardTimeLog?>().firstWhere(
          (l) => l!.fromTime != null && (l.toTime == null || l.toTime!.isEmpty),
      orElse: () => null,
    );
    if (openLog == null) return;

    try {
      _activeLogStart =
          DateFormat('yyyy-MM-dd HH:mm:ss').parse(openLog.fromTime!);
    } catch (_) {
      return;
    }

    // Tick immediately, then every second.
    _updateElapsed();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _updateElapsed());
  }

  void _updateElapsed() {
    final start = _activeLogStart;
    if (start == null) return;
    final elapsed = DateTime.now().difference(start);
    final h = elapsed.inHours.toString().padLeft(2, '0');
    final m = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    elapsedDisplay.value = '$h:$m:$s';
  }

  /// Seed editable header observables from the freshly loaded document.
  void _seedHeaderFields() {
    final jc = jobCard.value;
    if (jc == null) return;
    headerWorkstation.value  = jc.workstation     ?? '';
    headerEmployee.value     = jc.primaryEmployee ?? '';
    headerWipWarehouse.value = jc.wipWarehouse    ?? '';
  }

  // ── Header field: per-field save ──────────────────────────────────────────

  /// Save a single header field to ERP.
  ///
  /// [fieldKey]  — ERP fieldname: `'workstation'`, `'employee'`,
  ///              or `'wip_warehouse'`.
  /// [value]     — new value to persist (empty string clears the field).
  ///
  /// The matching [isSaving*] flag is set during the network call so the
  /// corresponding UI icon shows a spinner.  On success the matching
  /// [header*] observable is updated optimistically so the UI reflects the
  /// new value immediately without a full document reload.
  Future<void> saveHeaderField(String fieldKey, String value) async {
    final jc = jobCard.value;
    if (jc == null || !jc.isEditable) return;

    final savingFlag = switch (fieldKey) {
      'workstation'   => isSavingWorkstation,
      'employee'      => isSavingEmployee,
      'wip_warehouse' => isSavingWipWarehouse,
      _               => null,
    };
    final valueObs = switch (fieldKey) {
      'workstation'   => headerWorkstation,
      'employee'      => headerEmployee,
      'wip_warehouse' => headerWipWarehouse,
      _               => null,
    };
    if (savingFlag == null || valueObs == null) return;

    // Build the serialised payload.
    // `employee` is a Table MultiSelect on Job Card — Frappe requires a list of
    // child-row dicts: [{"employee": "HR-EMP-XXXXX"}].
    // Every other header field is a plain scalar value.
    final Object serialisedValue = (fieldKey == 'employee' && value.isNotEmpty)
        ? [{'employee': value}]
        : value;

    savingFlag.value = true;
    try {
      final res = await _provider.updateJobCardHeaderField(
        jobCardName: name,
        data: {fieldKey: serialisedValue},
      );
      if (res.statusCode == 200) {
        valueObs.value = value;
        // Re-fetch so the model stays in sync (e.g., workstation display name).
        await _fetchDocument();
        GlobalSnackbar.success(
          message: '${_fieldLabel(fieldKey)} updated',
        );
      } else {
        GlobalSnackbar.error(
          message: 'Failed to update ${_fieldLabel(fieldKey)}',
        );
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(
        message: extractDioError(e, 'Update ${_fieldLabel(fieldKey)} failed'),
      );
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      savingFlag.value = false;
    }
  }

  String _fieldLabel(String fieldKey) => switch (fieldKey) {
    'workstation'   => 'Workstation',
    'employee'      => 'Employee',
    'wip_warehouse' => 'WIP Warehouse',
    _               => fieldKey,
  };

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

  // ── Pause with qty prompt ─────────────────────────────────────────────────

  /// Shows a qty bottom sheet before pausing.
  /// Called by the Pause button instead of updateStatus directly.
  Future<void> pauseJobCard() async {
    if (!canUpdateStatus) return;

    HapticFeedback.lightImpact();

    final qty = await _showPauseQtySheet();
    if (qty == null) return; // user cancelled

    await _doPause(completedQty: qty);
  }

  /// Builds the employees list for make_time_log.
  ///
  /// ERP requires the session user's own Employee record to appear first
  /// in the list, otherwise it throws a PermissionError even for valid sessions.
  ///
  /// Strategy:
  ///   1. Find the logged-in user's employee entry from jc.employees.
  ///   2. Put it first; append all remaining employees after.
  ///   3. If the session employee is not in jc.employees at all,
  ///      prepend it anyway using the stored session employee ID.
  List<Map<String, dynamic>> _buildEmployeesPayload() {
    final jc = jobCard.value;
    if (jc == null) return [];

    final sessionEmpId = _sessionEmployeeId ?? '';
    final all          = jc.employees.map((e) => e.employee).toList();

    final ordered = <String>[
      // Session user's employee always first (ERP ownership check)
      if (sessionEmpId.isNotEmpty && all.contains(sessionEmpId))
        sessionEmpId,
      ...all.where((e) => e != sessionEmpId),
      // Fallback: session employee not in assigned list — still prepend
      if (sessionEmpId.isNotEmpty && !all.contains(sessionEmpId))
        sessionEmpId,
    ];

    return ordered.map((e) => <String, dynamic>{'employee': e}).toList(); // ✅
  }

  Future<double?> _showPauseQtySheet() {
    // Reset state from any previous pause attempt
    pauseQtyController.clear();
    pauseQtyError.value = null;

    return Get.bottomSheet<double>(
      _PauseQtySheet(controller: this),
      isScrollControlled: true,
      backgroundColor: Get.context != null
          ? Theme.of(Get.context!).colorScheme.surface
          : null,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
  }

  // When pausing, use the SAME employees that are on the open time log,
  // not the job card's assigned employee list.
  List<Map<String, dynamic>> _getActiveLogEmployees() {
    final logs = jobCard.value?.timeLogs ?? [];
    // Find the open log (has fromTime, no toTime)
    final JobCardTimeLog? openLog = logs.firstWhereOrNull( (l) => l.fromTime != null && (l.toTime == null || l.toTime!.isEmpty), );
    if (openLog?.employee != null && openLog!.employee!.isNotEmpty) {
      return [{'employee': openLog.employee}];
    }
    // Fallback: use the job card's employee field
    return (jobCard.value?.employees ?? [])
        .map((e) => {'employee': e.employee})
        .toList();
  }

  Future<void> _doPause({required double completedQty}) async {
    final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    isUpdatingStatus.value = true;
    try {
      // Step 1: close the open time log row via make_time_log.
      final res = await _provider.updateJobCardStatus(
        jobCardId:    name,
        status:       'Resume Job',
        startTime:    now,
        completeTime: now,
        completedQty: completedQty,
        employees:    _getActiveLogEmployees(),
      );

      if (res.statusCode != 200) {
        GlobalSnackbar.error(message: 'Failed to pause Job Card');
        return;
      }

      // Step 2: set the Job Card document status to 'On Hold'.
      //
      // make_time_log does NOT update the parent document's status field
      // when called with 'Resume Job' — it only closes the time log row.
      // We must PATCH the status field directly so the UI transitions to
      // "On Hold" and shows Resume instead of Pause.
      final holdRes = await _provider.setJobCardStatus(name, 'On Hold');
      if (holdRes.statusCode != 200) {
        // Non-fatal: time log is already closed. Warn but don't block.
        GlobalSnackbar.warning(
          message: 'Time log paused but status update to On Hold failed.',
        );
      }

      await _fetchDocument();
      _syncTimer();
      GlobalSnackbar.success(message: 'Job Card Paused');
    } on DioException catch (e) {
      GlobalSnackbar.error(message: _extractErrorMessage(e, 'Pause failed'));
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isUpdatingStatus.value = false;
    }
  }

  // ── Complete job card ──────────────────────────────────────────────────────

  /// Handles the Complete button tap:
  ///   1. Shows a confirmation dialog.
  ///   2. Finds the open time log (fromTime set, toTime empty).
  ///   3. Closes it: writes toTime=now and completedQty=remainingQty
  ///      via [updateTimeLog] (reuses the existing PATCH endpoint).
  ///   4. Calls updateJobCardStatus('Complete') to flip the ERP status.
  ///   5. Falls back to a status-only call if no open log is found.
  ///   6. Triggers [_autoSubmitIfComplete] on success.
  Future<void> _completeJobCard() async {
    if (!canUpdateStatus) return;

    HapticFeedback.lightImpact();

    final confirmed = await GlobalDialog.confirm(
      title:       'Complete Job Card',
      message:     'This will close the active time log and mark '
          'the Job Card as Completed. '
          'This cannot be undone without ERP admin access.',
      confirmText: 'Complete',
    );
    if (confirmed != true) return;

    final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final jc  = jobCard.value;

    // ── Step 1: find and close the open time log ─────────────────────────
    final JobCardTimeLog? openLog = jc?.timeLogs.firstWhereOrNull(
          (l) => l.fromTime != null && (l.toTime == null || l.toTime!.isEmpty),
    );

    isUpdatingStatus.value = true;
    try {
      if (openLog != null) {
        // Close the open log with toTime=now, qty=remainingQty.
        // remainingQty is already clamped to ≥0 by the getter.
        final res = await _provider.updateTimeLog(
          timeLogName:  openLog.name,
          toTime:       now,
          completedQty: remainingQty,
          employee:     openLog.employee,
        );
        if (res.statusCode != 200) {
          GlobalSnackbar.error(message: 'Failed to close active time log');
          return;
        }
        // Touch parent so server recalculates total_completed_qty
        // before we send the status update.
        await _provider.touchJobCard(name);
      }

      // ── Step 2: flip ERP status to Complete ──────────────────────────
      final statusRes = await _provider.updateJobCardStatus(
        jobCardId:    name,
        status:       'Complete',
        startTime:    now,
        completeTime: now,
        employees:    _buildEmployeesPayload(),
      );

      if (statusRes.statusCode == 200) {
        await _fetchDocument();
        _syncTimer();
        GlobalSnackbar.success(message: 'Job Card Completed');
        await _autoSubmitIfComplete();
      } else {
        GlobalSnackbar.error(message: 'Failed to update status');
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(
          message: _extractErrorMessage(e, 'Complete failed'));
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isUpdatingStatus.value = false;
    }
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
        await _autoSubmitIfComplete();
      } else {
        GlobalSnackbar.error(message: 'Failed to add time log');
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(
          message: extractDioError(e, 'Add time log failed'));
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
      // ERP DELETE returns 202 on success.
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
    // Complete has its own dedicated path: closes the open time log first,
    // then updates the status. Delegate immediately.
    if (newStatus == JobCard.statusCompleted) {
      await _completeJobCard();
  