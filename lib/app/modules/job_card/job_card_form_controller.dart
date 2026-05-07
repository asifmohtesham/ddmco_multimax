import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/mixins/dio_error_mixin.dart';
import 'package:multimax/app/data/models/job_card_employee_model.dart';
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

// ── Employee chips ────────────────────────────────────────────────────────
  /// All Active employees fetched once on form open; drives the picker sheet.
  final availableEmployees = <Map<String, dynamic>>[].obs;

  /// True while a toggle-employee PATCH is in-flight.
  final isSavingEmployees = false.obs;

  /// Fetches Active employees from ERP and stores in [availableEmployees].
  /// Safe to call multiple times — skips if the list is already populated.
  Future<void> loadAvailableEmployees() async {
    if (availableEmployees.isNotEmpty) return;
    try {
      final res = await _provider.getActiveEmployees();
      if (res.statusCode == 200 && res.data['data'] != null) {
        availableEmployees.assignAll(
          (res.data['data'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        );
      }
    } catch (_) {
      // Non-fatal — sheet will show empty list with a retry option.
    }
  }

  /// Adds [employeeId] to the Job Card's employee table when not already
  /// present, or removes it when already assigned. One PATCH per tap.
  ///
  /// Payload shape: [{'employee': 'HR-EMP-XXXXX'}, ...]
  /// ERP Table MultiSelect requires the full list on every PATCH.
  Future<void> toggleEmployee(String employeeId, String employeeName) async {
    final jc = jobCard.value;
    if (jc == null || !jc.isEditable || isSavingEmployees.value) return;

    // Build current employee ID list.
    final current = jc.employees.map((e) => e.employee).toList();

    // Toggle: remove if present, add if absent.
    final List<String> updated;
    if (current.contains(employeeId)) {
      updated = current.where((e) => e != employeeId).toList();
    } else {
      updated = [...current, employeeId];
    }

    // Serialise to ERP child-table format.
    final payload = updated.map((e) => <String, dynamic>{'employee': e}).toList();

    isSavingEmployees.value = true;
    try {
      final res = await _provider.updateJobCardHeaderField(
        jobCardName: name,
        data: {'employee': payload},
      );
      if (res.statusCode == 200) {
        await _fetchDocument();
      } else {
        GlobalSnackbar.error(message: 'Failed to update employees');
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(
        message: extractDioError(e, 'Employee update failed'),
      );
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isSavingEmployees.value = false;
    }
  }

  // ── Document state ────────────────────────────────────────────────────────
  final isLoading         = true.obs;
  final isAddingTimeLog   = false.obs;
  final isUpdatingStatus  = false.obs;
  final isEditingTimeLog  = false.obs;

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
  final headerWorkstation  = ''.obs;
  final headerEmployee     = ''.obs;
  /// Display name of the primary assigned employee (falls back to ID when
  /// employeeName is absent). Used by the AppBar subtitle.
  final headerEmployeeName = ''.obs;
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
    loadAvailableEmployees().then((_) {
      // Re-enrich after the employee list arrives in case _fetchDocument()
      // completed first and _enrichEmployeeNames() was a no-op.
      _enrichEmployeeNames();
    });
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
    headerWorkstation.value  = jc.workstation ?? '';
    headerEmployee.value     = jc.employees.isNotEmpty
        ? jc.employees.first.employee
        : '';
    headerEmployeeName.value = jc.primaryEmployeeDisplay ?? '';
    headerWipWarehouse.value = jc.wipWarehouse ?? '';

    // Enrich employee names from availableEmployees cache.
    // ERPNext does not reliably return employee_name on child table rows
    // via the standard document GET. Resolve names locally from the
    // already-loaded availableEmployees list (fetched once on onInit).
    _enrichEmployeeNames();
  }

  /// Resolves [JobCardEmployee.employeeName] for each assigned employee
  /// using the [availableEmployees] cache. Rebuilds the employees list on
  /// [jobCard] with names filled in, then triggers a reactive update.
  ///
  /// No-op when [availableEmployees] is empty (not yet loaded) or when
  /// all employees already have names.
  void _enrichEmployeeNames() {
    final jc = jobCard.value;
    if (jc == null || availableEmployees.isEmpty) return;

    // Build a quick lookup: employee ID → employee_name.
    final nameMap = <String, String>{
      for (final e in availableEmployees)
        (e['name'] ?? '').toString(): (e['employee_name'] ?? '').toString(),
    };

    final enriched = jc.employees.map((e) {
      if ((e.employeeName ?? '').isNotEmpty) return e; // already has name
      final resolved = nameMap[e.employee] ?? '';
      return resolved.isNotEmpty
          ? JobCardEmployee(employee: e.employee, employeeName: resolved)
          : e;
    }).toList();

    // Only rebuild if at least one name was resolved.
    if (enriched.any((e) => (e.employeeName ?? '').isNotEmpty)) {
      jobCard.value = JobCard(
        name:               jc.name,
        company:            jc.company,
        workOrder:          jc.workOrder,
        operation:          jc.operation,
        operationId:        jc.operationId,
        workstation:        jc.workstation,
        workstationType:    jc.workstationType,
        forQuantity:        jc.forQuantity,
        totalCompletedQty:  jc.totalCompletedQty,
        processLossQty:     jc.processLossQty,
        transferredQty:     jc.transferredQty,
        status:             jc.status,
        wipWarehouse:       jc.wipWarehouse,
        employees:          enriched,
        postingDate:        jc.postingDate,
        expectedStartDate:  jc.expectedStartDate,
        expectedEndDate:    jc.expectedEndDate,
        actualStartDate:    jc.actualStartDate,
        actualEndDate:      jc.actualEndDate,
        sequenceId:         jc.sequenceId,
        hourRate:           jc.hourRate,
        totalTimeInMins:    jc.totalTimeInMins,
        batchNo:            jc.batchNo,
        serialNo:           jc.serialNo,
        bomNo:              jc.bomNo,
        remarks:            jc.remarks,
        project:            jc.project,
        productionItem:     jc.productionItem,
        itemName:           jc.itemName,
        isCorrectiveJobCard: jc.isCorrectiveJobCard,
        docstatus:          jc.docstatus,
        timeLogs:           jc.timeLogs,
      );
    }
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
        // After _fetchDocument() re-seeds headerEmployeeName via _seedHeaderFields(),
        // so no manual update needed here — _seedHeaderFields() already ran.
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

  /// Queries ERP for any Job Card currently `Work In Progress` assigned to
  /// the session employee. Returns the conflicting [Map] (keys: `name`,
  /// `operation`) or `null` when none is running.
  ///
  /// Uses the existing [JobCardProvider.getJobCards] with two filters:
  ///   - status == 'Work In Progress'
  ///   - employee == sessionEmployeeId  (child-table field filter)
  ///
  /// The result excludes the current Job Card so a card cannot block itself
  /// (edge case: re-resuming after a network glitch where status is stale).
  Future<Map<String, dynamic>?> _checkForRunningJobCard() async {
    final empId = _sessionEmployeeId ?? '';
    if (empId.isEmpty) return null;

    try {
      final res = await _provider.getJobCards(
        limit: 2,
        filters: {
          'status':   'Work In Progress',
          'employee': empId,
        },
      );

      if (res.statusCode != 200) return null;

      final rows = (res.data['data'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => (e['name'] ?? '') != name) // exclude self
          .toList();

      return rows.isNotEmpty ? rows.first : null;
    } catch (_) {
      // Non-fatal: if the check fails, allow the action to proceed.
      // A failed check must never silently block work.
      return null;
    }
  }

  // ── Update status ─────────────────────────────────────────────────────────

  Future<void> updateStatus(String newStatus) async {
    // Complete has its own dedicated path: closes the open time log first,
    // then updates the status. Delegate immediately.
    if (newStatus == JobCard.statusCompleted) {
      await _completeJobCard();
      return;
    }

    if (!canUpdateStatus) return;

    // ── Conflict check (Start / Resume only) ─────────────────────────────
    // If another Job Card is already Work In Progress for this employee,
    // block the action and show the hard-block sheet.
    if (newStatus == JobCard.statusWorkInProgress) {
      isUpdatingStatus.value = true;
      final conflict = await _checkForRunningJobCard();
      isUpdatingStatus.value = false;

      if (conflict != null) {
        GlobalDialog.showRunningJobCardBlock(
          conflictingName:      (conflict['name']      ?? '').toString(),
          conflictingOperation: (conflict['operation'] ?? '').toString(),
        );
        return;
      }
    }

    HapticFeedback.lightImpact();

    final String erpNextStatus = switch (newStatus) {
      JobCard.statusWorkInProgress => 'Work In Progress',
      _                            => newStatus,
    };

    final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    isUpdatingStatus.value = true;
    try {
      final res = await _provider.updateJobCardStatus(
        jobCardId:    name,
        status:       erpNextStatus,
        startTime:    now,
        completeTime: null,          // Start/Resume never sends completeTime
        employees:    _buildEmployeesPayload(),
      );

      if (res.statusCode == 200) {
        await _fetchDocument();
        _syncTimer();
        final label = switch (newStatus) {
          JobCard.statusWorkInProgress => 'Started',
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

  // ── Submit ────────────────────────────────────────────────────────────────

  /// Manually submit the Job Card after user confirmation.
  ///
  /// Submitting locks the document (docstatus → 1), updates the parent Work
  /// Order Operation, and prevents further edits. A confirmation dialog is
  /// always shown so the user cannot accidentally trigger this action.
  Future<void> submitJobCard() async {
    if (!canSubmit) return;

    // Stronger haptic for the final commit action
    HapticFeedback.mediumImpact();

    final confirmed = await GlobalDialog.confirm(
      title:       'Submit Job Card',
      message:     'Submit this Job Card? The record will be locked and '
                   'the Work Order will be updated. This cannot be undone.',
      confirmText: 'Submit',
    );
    if (confirmed != true) return;

    isSubmitting.value = true;
    try {
      final res = await _provider.submitJobCard(name);
      if (res.statusCode == 200) {
        await _fetchDocument();
        GlobalSnackbar.success(message: 'Job Card submitted successfully');
      } else {
        GlobalSnackbar.error(message: 'Job Card submission failed');
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(
          message: _extractErrorMessage(e, 'Submission failed'));
    } catch (e) {
      GlobalSnackbar.error(message: 'Submission error: $e');
    } finally {
      isSubmitting.value = false;
    }
  }

  // ── Auto-submit helper (internal) ─────────────────────────────────────────

  /// Silently submits the Job Card when qty is fully met — no confirmation
  /// dialog because the trigger (add/complete) already served as implicit
  /// intent. Used internally by [addTimeLog] and [updateStatus].
  Future<void> _autoSubmitIfComplete() async {
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
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final navBarHeight = MediaQuery.of(context).viewPadding.bottom;
    final padding   = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: isKeyboardOpen ? 0 : navBarHeight,
        ),
        child: SingleChildScrollView(
          physics: const CarouselScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
        ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Pause Qty Sheet
// Collects completed_qty before pausing so the time log row is fully recorded.
// ─────────────────────────────────────────────────────────────────────────────

class _PauseQtySheet extends StatefulWidget {
  final JobCardFormController controller;
  const _PauseQtySheet({required this.controller});

  @override
  State<_PauseQtySheet> createState() => _PauseQtySheetState();
}

class _PauseQtySheetState extends State<_PauseQtySheet> {
  String? _error;
  double  _remaining = 0;
  bool    _forQtySet = false;

  @override
  void initState() {
    super.initState();
    _sync();
    ever(widget.controller.pauseQtyError, (_) => _sync());
    ever(widget.controller.jobCard,       (_) => _sync());
  }

  void _sync() {
    if (!mounted) return;
    setState(() {
      _error     = widget.controller.pauseQtyError.value;
      _remaining = widget.controller.remainingQty;
      _forQtySet = (widget.controller.jobCard.value?.forQuantity ?? 0) > 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs           = Theme.of(context).colorScheme;
    final textTheme    = Theme.of(context).textTheme;
    final enabled      = widget.controller.canConfirmPause;
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final navBarHeight   = MediaQuery.of(context).viewPadding.bottom;

    return SafeArea(
      bottom: false,                        // we control bottom manually
      child: Padding(
        // Only add nav bar clearance when keyboard is CLOSED.
        // Flutter already lifts the sheet above the keyboard automatically.
        padding: EdgeInsets.only(
          bottom: isKeyboardOpen ? 0 : navBarHeight,
        ),
        child: SingleChildScrollView(
          // physics ensures it scrolls only when content actually overflows
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Drag handle ─────────────────────────────────────────
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 4),

                // ── Title ───────────────────────────────────────────────
                Row(
                  children: [
                    Icon(Icons.pause_circle_outline,
                        size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Text('Pause Job Card',
                        style: textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Enter qty completed in this session (0 if none).',
                  style: textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),

                // ── Qty field ───────────────────────────────────────────
                TextField(
                  controller: widget.controller.pauseQtyController,
                  autofocus: true,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  onSubmitted: enabled
                      ? (_) => Get.back(
                    result: double.parse(
                        widget.controller.pauseQtyController.text),
                  )
                      : null,
                  onChanged: widget.controller.validatePauseQty,
                  decoration: InputDecoration(
                    labelText:     'Completed Qty',
                    border:        const OutlineInputBorder(),
                    prefixIcon:    const Icon(Icons.numbers_outlined),
                    errorText:     _error,
                    errorMaxLines: 2,
                    helperText:    _error == null && _forQtySet
                        ? 'Remaining: ${widget.controller._fmtQty(_remaining)}'
                        : null,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Pause button — always visible ───────────────────────
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: enabled
                        ? () => Get.back(
                      result: double.parse(
                          widget.controller.pauseQtyController.text),
                    )
                        : null,
                    icon: const Icon(Icons.pause_rounded),
                    label: const Text('Pause',
                        style: TextStyle(fontSize: 15)),
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
