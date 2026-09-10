import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/home/widgets/scan_bottom_sheets.dart';
import 'package:multimax/app/modules/home/widgets/pos_upload_scan_sheets.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/home/widgets/performance_timeline_card.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/item/form/item_form_screen.dart';
import 'package:multimax/app/modules/item/form/item_tab_controller.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/packing_slip_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/scan_constants.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/models/todo_model.dart';
import 'package:multimax/app/data/providers/todo_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_todo_card.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_strip.dart';
import 'package:multimax/app/data/providers/warehouse_provider.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_preview.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/providers/attendance_provider.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';

enum ActiveScreen { home, purchaseReceipt, stockEntry, deliveryNote, packingSlip, posUpload, todo, item, batch, bom }

class HomeController extends GetxController {
  final AuthenticationController _authController = Get.find<AuthenticationController>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final ItemProvider _itemProvider = Get.find<ItemProvider>();
  final JobCardProvider _jcProvider = Get.find<JobCardProvider>();
  final UserProvider _userProvider = Get.find<UserProvider>();
  final PosUploadProvider _posUploadProvider = Get.find<PosUploadProvider>();
  final StockEntryProvider _stockEntryProvider = Get.find<StockEntryProvider>();
  final DeliveryNoteProvider _deliveryNoteProvider = Get.find<DeliveryNoteProvider>();
  final ScanService _scanService = Get.find<ScanService>();
  final DataWedgeService _dataWedgeService = Get.find<DataWedgeService>();
  final ToDoProvider _todoProvider = Get.find<ToDoProvider>();
  final StorageService _storageService = Get.find<StorageService>();

  /// Resolved lazily so HomeController construction never *requires* a Packing
  /// Slip provider: home_binding registers one for production, and unit tests
  /// that don't register it can still construct the controller. Falls back to a
  /// fresh instance, which resolves ApiProvider from the container like every
  /// other provider.
  PackingSlipProvider get _packingSlipProvider =>
      Get.isRegistered<PackingSlipProvider>()
          ? Get.find<PackingSlipProvider>()
          : Get.put(PackingSlipProvider());

  /// Same lazy pattern as [_packingSlipProvider]: home_binding registers one,
  /// controller unit tests need not.
  AttendanceProvider get _attendanceProvider =>
      Get.isRegistered<AttendanceProvider>()
          ? Get.find<AttendanceProvider>()
          : Get.put(AttendanceProvider());

  /// Worker that routes hardware (DataWedge) scans to [onScan].
  /// Disposed in [onClose].
  Worker? _scanWorker;

  var selectedDrawerIndex = 0.obs;
  var activeScreen = ActiveScreen.home.obs;

  var isLoadingStats = true.obs;
  var isLoadingUsers = true.obs;

  // --- Timeline State ---
  var timelineViewMode = 'Daily'.obs;
  var isLoadingTimeline = true.obs;
  var timelineData = <TimelinePoint>[].obs;

  var selectedDailyDate = DateTime.now().obs;
  var selectedWeeklyRange = DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 28)),
      end: DateTime.now()
  ).obs;

  var userList = <User>[].obs;
  Rx<User?> selectedFilterUser = Rx<User?>(null);

  var activeWorkOrdersCount = 0.obs;
  final int targetWorkOrders = 12;

  var activeJobCardsCount = 0.obs;
  final int targetJobCards = 40;

  /// Count of active (is_active = 1) BOMs fetched on dashboard load.
  var activeBomCount = 0.obs;

  /// Active WIP Job Card for the session employee (null if none).
  final activeWipJcName      = RxnString();
  final activeWipJcOperation = RxnString();

  /// Actionable open ToDos for the selected user — soonest due date first,
  /// capped for the dashboard "Upcoming tasks" section.
  var upcomingTodos = <ToDo>[].obs;

  /// Draft counts for the five transactional DocTypes, keyed by doctype, for
  /// the currently displayed [actionableScope]. Only DocTypes the user can
  /// read appear as keys.
  final actionableCounts = <String, int>{}.obs;

  /// Number of open ToDos for the selected user (personal in both scopes) —
  /// drives the Tasks chip. Derived from the [fetchUpcomingTodos] fetch.
  final openTodoCount = 0.obs;

  /// Mine/Everyone scope for the five document chips. Seeded from storage in
  /// [onInit]; the Tasks chip is unaffected by it.
  final actionableScope = ActionableScope.mine.obs;

  /// True until the first count fetch for the current scope resolves (drives
  /// the strip's loading placeholders). Starts true so the first build shows
  /// placeholders rather than an empty strip.
  final isLoadingActionable = true.obs;

  /// Counts cache keyed by [actionableCacheKey] — `mine::<email>` / `all`.
  final Map<String, Map<String, int>> _actionableCountCache = {};

  /// The doctype whose 3-document preview is shown ('ToDo' = the Tasks chip).
  /// Null when nothing is actionable. Transient — not persisted.
  final selectedActionable = RxnString();

  /// The selected doctype's preview rows (empty for 'ToDo', whose rows render
  /// as DashboardTodoCards from [upcomingTodos]).
  final previewDocs = <ActionableDocRowData>[].obs;

  /// True while the selected doctype's preview fetch is in flight.
  final isLoadingPreview = false.obs;

  /// Preview cache keyed by '<doctype>::<actionableCacheKey(scope, email)>'.
  final Map<String, List<ActionableDocRowData>> _previewCache = {};

  // --- Today's attendance (site-wide; does NOT follow selectedFilterUser) ---
  //
  // Mirrors AttendanceController for today only: master data once, punches +
  // ledger per refresh, status derived by the shared attendance_logic. No poll:
  // pull-to-refresh / header refresh reload it with the rest of the dashboard.
  final isLoadingAttendance = true.obs;
  final attendanceRows = <EmployeeDayStatus>[].obs; // attention-first
  final attendanceShift = Rx<ShiftRules>(ShiftRules.fallback);
  final attendanceHolidays = <String>{}.obs;
  final attendanceLoadedAt = Rxn<DateTime>();
  final attendanceLatestPunch = Rxn<EmployeeCheckin>();
  List<TrackedEmployee> _attendanceEmployees = const [];
  bool _attendanceMasterLoaded = false;

  /// Same fail-closed gate as the drawer entry for the Attendance screen.
  bool get attendanceVisible =>
      Get.find<PermissionService>().hasAccess('Attendance') == true;

  bool get attendanceIsHoliday =>
      attendanceHolidays.contains(kFrappeDate.format(DateTime.now()));

  bool get beforeAttendanceCutoff =>
      DateTime.now().isBefore(attendanceShift.value.cutoffOn(DateTime.now()));

  /// Past the cut-off with zero punches for anyone → the terminal has most
  /// likely not uploaded; before the cut-off an empty day is normal.
  bool get attendanceLooksOffline =>
      !attendanceIsHoliday &&
      !beforeAttendanceCutoff &&
      attendanceRows.isNotEmpty &&
      attendanceRows.every((r) => r.punches.isEmpty);

  AttendanceCounts get attendanceCounts => AttendanceCounts.of(attendanceRows);

  /// The logged-in employee's own row, if they are an active employee.
  EmployeeDayStatus? get myAttendance {
    final id = _authController.currentUser.value?.employeeId;
    if (id == null || id.isEmpty) return null;
    return attendanceRows.firstWhereOrNull((r) => r.employee.name == id);
  }

  Future<void> fetchTodayAttendance() async {
    if (!attendanceVisible) {
      attendanceRows.clear();
      isLoadingAttendance.value = false;
      return;
    }
    try {
      if (!_attendanceMasterLoaded) {
        _attendanceEmployees = await _attendanceProvider.fetchActiveEmployees();
        final shiftName = _attendanceEmployees
            .map((e) => e.defaultShift ?? '')
            .firstWhere((s) => s.isNotEmpty, orElse: () => '')
            .trim();
        try {
          attendanceShift.value = await _attendanceProvider.fetchShiftRules(
              shiftName.isEmpty ? ShiftRules.fallback.name : shiftName);
        } catch (_) {
          attendanceShift.value = ShiftRules.fallback;
        }
        try {
          attendanceHolidays.assignAll(await _attendanceProvider
              .fetchHolidays(attendanceShift.value.holidayList));
        } catch (_) {}
        _attendanceMasterLoaded = true;
      }
      final today = dateOnly(DateTime.now());
      final results = await Future.wait([
        _attendanceProvider.fetchCheckins(today),
        _attendanceProvider.fetchAttendance(today, today),
      ]);
      final checkins = results[0] as List<EmployeeCheckin>;
      final ledger = results[1] as List<AttendanceRecord>;
      if (checkins.isEmpty) {
        try {
          attendanceLatestPunch.value = await _attendanceProvider.fetchLatestCheckin();
        } catch (_) {}
      }
      final byEmp = <String, List<EmployeeCheckin>>{};
      for (final c in checkins) {
        byEmp.putIfAbsent(c.employee, () => []).add(c);
      }
      final ledgerByEmp = {for (final r in ledger) r.employee: r};
      final hol = attendanceIsHoliday;
      final now = DateTime.now();
      final rows = _attendanceEmployees
          .map((e) => deriveDayStatus(
                employee: e,
                day: today,
                now: now,
                shift: attendanceShift.value,
                isHoliday: hol,
                punches: byEmp[e.name] ?? const [],
                ledger: ledgerByEmp[e.name],
              ))
          .toList()
        ..sort(compareDayStatus);
      attendanceRows.assignAll(rows);
      attendanceLoadedAt.value = DateTime.now();
    } catch (e) {
      print("Error fetching today's attendance: $e");
    } finally {
      isLoadingAttendance.value = false;
    }
  }

  void goToAttendance() => Get.toNamed(AppRoutes.ATTENDANCE);

  /// Display names for owner resolution, keyed by email, from the loaded users.
  Map<String, String> get namesByEmail => {
        for (final u in userList)
          if (u.email.isNotEmpty) u.email: u.name,
      };

  /// Quick Create card layout — 1 or 2 columns, persisted across sessions.
  var dashboardColumns = 1.obs;

  /// Whether "Upcoming tasks" leads the dashboard (manager persona with
  /// open ToDos). Seeded from the persisted per-user verdict so the initial
  /// build doesn't reflow when the async ToDo fetch lands; recomputed by
  /// [_recomputeTasksFirst] after each fetch.
  var tasksFirst = false.obs;

  final TextEditingController barcodeController = TextEditingController();
  var isScanning = false.obs;
  var isRackScanning = false.obs;

  // Fulfillment
  var isFetchingFulfillmentList = false.obs;
  var fulfillmentPosUploads = <PosUpload>[].obs;
  var fulfillmentSearchQuery = ''.obs;
  List<PosUpload> _allFulfillmentUploads = [];
  List<String> _fulfillmentPrefixFilters = [];

  List<BottomNavigationBarItem> get homeBottomBarItems => [
    const BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
    const BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Notifications'),
  ];

  List<BottomNavigationBarItem> get currentBottomBarItems => homeBottomBarItems;

  @override
  void onInit() {
    super.onInit();
    dashboardColumns.value = _storageService.getDashboardColumns();
    tasksFirst.value = _storageService.getDashboardTasksFirst(
        _authController.currentUser.value?.email ?? '');
    actionableScope.value =
        actionableScopeFromString(_storageService.getDashboardActionableScope());
    _updateActiveScreenForRoute(Get.currentRoute);
    _initDashboard();

    // ── DataWedge hardware-scan worker ────────────────────────────────────
    _scanWorker = ever(_dataWedgeService.scannedCode, (String code) {
      if (code.isEmpty) return;
      if (Get.currentRoute != AppRoutes.HOME) return;
      onScan(code);
    });
  }

  @override
  void onClose() {
    _scanWorker?.dispose();
    barcodeController.dispose();
    super.onClose();
  }

  void openSessionDefaults() {
    Get.toNamed(AppRoutes.SESSION_DEFAULTS);
  }

  /// Switches the Quick Create grid between the 1- and 2-column layouts and
  /// persists the choice. Any other value clamps to 1 (the default).
  void setDashboardColumns(int columns) {
    final cols = columns == 2 ? 2 : 1;
    if (dashboardColumns.value == cols) return;
    dashboardColumns.value = cols;
    _storageService.saveDashboardColumns(cols);
  }

  /// Pure persona rule for dashboard section ordering: "Upcoming tasks"
  /// leads only when the user holds a manager-ish role AND there are open
  /// ToDos to show. AND, not OR — a manager with an empty list gains
  /// nothing from leading with an empty section, and an operator's layout
  /// must not flip whenever a task lands.
  ///
  /// Manager-ish = any role whose name contains "manager" (case-insensitive)
  /// — covers Stock/Purchase/Manufacturing/System Manager and custom
  /// "* Manager" roles with no maintained list.
  static bool showTasksFirst({
    required List<String> roles,
    required bool hasOpenTodos,
  }) {
    if (!hasOpenTodos) return false;
    return roles.any((r) => r.toLowerCase().contains('manager'));
  }

  Future<void> _initDashboard() async {
    await fetchUsers();
    if (selectedFilterUser.value == null) {
      final myEmail = _authController.currentUser.value?.email;
      if (myEmail != null) {
        selectedFilterUser.value = userList.firstWhereOrNull((u) => u.email == myEmail);
      }
      if (selectedFilterUser.value == null && userList.isNotEmpty) {
        selectedFilterUser.value = userList.first;
      }
    }
    fetchDashboardData();
    fetchPerformanceData();
  }

  Future<void> fetchUsers() async {
    isLoadingUsers.value = true;
    try {
      final currentUser = _authController.currentUser.value;
      final empId = currentUser?.employeeId;
      if (empId != null) {
        final response = await _userProvider.getDirectReports(empId);
        if (response.statusCode == 200 && response.data['data'] != null) {
          final data = response.data['data'] as List;
          final reports = data.map((e) => User(
            id: e['user_id'] ?? '',
            name: e['employee_name'] ?? 'Unknown',
            email: e['user_id'] ?? '',
            roles: [],
            employeeId: e['name'],
          )).toList();
          if (currentUser != null && !reports.any((u) => u.email == currentUser.email)) {
            reports.insert(0, currentUser);
          }
          userList.assignAll(reports);
        }
      } else {
        final response = await _userProvider.getUsers();
        if (response.statusCode == 200 && response.data['data'] != null) {
          final data = response.data['data'] as List;
          userList.assignAll(data.map((e) => User.fromJson(e)).toList());
        }
      }
    } catch (e) {
      print('Error fetching users: $e');
    } finally {
      isLoadingUsers.value = false;
    }
  }

  void onUserFilterChanged(User user) {
    selectedFilterUser.value = user;
    Get.back();
    fetchDashboardData();
    fetchPerformanceData();
  }

  Future<void> fetchDashboardData() async {
    isLoadingStats.value = true;
    try {
      Map<String, dynamic> woFilters = {'status': 'In Process'};
      Map<String, dynamic> jcFilters = {'status': 'Open'};
      final filterEmail = selectedFilterUser.value?.email;
      if (filterEmail != null) {
        woFilters['owner'] = filterEmail;
        jcFilters['owner'] = filterEmail;
      }

      // BOM count is company-wide (is_active only — not user-scoped).
      const Map<String, dynamic> bomFilters = {'is_active': 1, 'docstatus': 1};

      final results = await Future.wait([
        _apiProvider.getDocumentCount('Work Order', filters: woFilters),
        _apiProvider.getDocumentCount('Job Card',   filters: jcFilters),
        _apiProvider.getDocumentCount('BOM',        filters: bomFilters),
      ]);

      activeWorkOrdersCount.value = _extractCount(results[0]);
      activeJobCardsCount.value   = _extractCount(results[1]);
      activeBomCount.value        = _extractCount(results[2]);

      await Future.wait([
        _fetchActiveWipJc(),
        fetchUpcomingTodos(),
        fetchActionableCounts(force: true),
        fetchTodayAttendance(), // swallows its own errors
      ]);
      _applyDefaultSelection();
    } catch (e) {
      print('Error fetching dashboard stats: $e');
    } finally {
      isLoadingStats.value = false;
    }
  }

  /// Fetches open ToDos allocated to — or created by — the selected filter
  /// user (self-created ToDos often have no `allocated_to`). The server
  /// orders by due date ascending, but empty dates sort first there —
  /// [selectUpcomingTodos] reorders them to the end and caps the list.
  Future<void> fetchUpcomingTodos() async {
    try {
      final email = selectedFilterUser.value?.email ??
          _authController.currentUser.value?.email;
      if (email == null || email.isEmpty) {
        upcomingTodos.clear();
        openTodoCount.value = 0;
        _recomputeTasksFirst();
        return;
      }
      final res = await _todoProvider.getTodos(
        limit: 50,
        filters: {'status': 'Open'},
        orFilterTuples: [
          ['ToDo', 'allocated_to', '=', email],
          ['ToDo', 'owner', '=', email],
        ],
        orderBy: 'date asc',
      );
      if (res.statusCode == 200 && res.data['data'] != null) {
        final list = (res.data['data'] as List)
            .map((e) => ToDo.fromJson(e))
            .toList();
        openTodoCount.value = list.length;
        upcomingTodos.assignAll(selectUpcomingTodos(list));
        _recomputeTasksFirst();
      }
    } catch (e) {
      print('Error fetching upcoming todos: $e');
    }
  }

  /// Fetches Draft counts for accessible document DocTypes in the current
  /// [actionableScope]. Serves a cached result when present unless [force].
  /// `mine` counts key by the viewed user's email; `everyone` counts are
  /// user-independent. Only DocTypes the user can read are queried (no 403s).
  Future<void> fetchActionableCounts({bool force = false}) async {
    final scope = actionableScope.value;
    final email = selectedFilterUser.value?.email ??
        _authController.currentUser.value?.email;
    final key = actionableCacheKey(scope, email);

    if (force) _actionableCountCache.clear();

    final cached = _actionableCountCache[key];
    if (cached != null) {
      actionableCounts.assignAll(cached);
      isLoadingActionable.value = false;
      return;
    }

    isLoadingActionable.value = true;
    try {
      final perm = Get.find<PermissionService>();
      final doctypes = <String>[];
      final requests = <Future<Response>>[];
      for (final cfg in kActionableDocConfigs) {
        if (perm.hasAccess(cfg.doctype) != true) continue;
        doctypes.add(cfg.doctype);
        requests.add(_apiProvider.getDocumentCount(
          cfg.doctype,
          filters: actionableFiltersFor(cfg.doctype, scope, email),
        ));
      }
      final responses = await Future.wait(requests);
      final counts = <String, int>{};
      for (var i = 0; i < doctypes.length; i++) {
        counts[doctypes[i]] = _extractCount(responses[i]);
      }
      _actionableCountCache[key] = counts;
      // Guard against a scope flip landing before this fetch returns.
      if (scope == actionableScope.value) actionableCounts.assignAll(counts);
    } catch (e) {
      print('Error fetching actionable counts: $e');
    } finally {
      if (scope == actionableScope.value) isLoadingActionable.value = false;
    }
  }

  /// Selects a chip and loads its preview. 'ToDo' renders from [upcomingTodos]
  /// and needs no fetch.
  void selectActionable(String doctype) {
    if (selectedActionable.value == doctype) return;
    selectedActionable.value = doctype;
    fetchPreviewDocs();
  }

  /// Applies the default chip when nothing is selected or the current selection
  /// no longer has work, then refreshes the preview. Called after counts and
  /// todos land.
  void _applyDefaultSelection() {
    final current = selectedActionable.value;
    final stillHasWork = current != null &&
        (current == 'ToDo'
            ? openTodoCount.value > 0
            : (actionableCounts[current] ?? 0) > 0);
    if (!stillHasWork) {
      selectedActionable.value =
          defaultActionableSelection(actionableCounts, openTodoCount.value);
    }
    fetchPreviewDocs(force: true);
  }

  /// Fetches the selected doctype's first 3 Draft documents, using the SAME
  /// filter as its count and its View All list. Served from cache unless
  /// [force]. Queries ApiProvider directly (PO/PR providers are not registered
  /// in HomeBinding) requesting only the fields a row renders.
  Future<void> fetchPreviewDocs({bool force = false}) async {
    if (force) _previewCache.clear();

    final doctype = selectedActionable.value;
    if (doctype == null || doctype == 'ToDo') {
      previewDocs.clear();
      isLoadingPreview.value = false;
      return;
    }
    final cfg = kActionableDocConfigs.firstWhereOrNull((c) => c.doctype == doctype);
    if (cfg == null) {
      previewDocs.clear();
      isLoadingPreview.value = false;
      return;
    }

    final scope = actionableScope.value;
    final email = selectedFilterUser.value?.email ??
        _authController.currentUser.value?.email;
    final key = '$doctype::${actionableCacheKey(scope, email)}';

    final cached = _previewCache[key];
    if (cached != null) {
      previewDocs.assignAll(cached);
      isLoadingPreview.value = false;
      return;
    }

    previewDocs.clear();
    isLoadingPreview.value = true;
    try {
      final res = await _apiProvider.getDocumentList(
        doctype,
        filters: actionableFiltersFor(doctype, scope, email),
        fields: cfg.previewFields,
        limit: 3,
        orderBy: 'creation desc',
      );
      final rows = <ActionableDocRowData>[];
      if (res.statusCode == 200 && res.data['data'] != null) {
        final names = namesByEmail;
        for (final e in (res.data['data'] as List)) {
          final json = Map<String, dynamic>.from(e as Map);
          rows.add(docRowFor(
            doctype,
            json,
            (owner) => ownerLabelFor(owner, names),
            onTap: () => Get.toNamed(
              cfg.formRoute,
              arguments: {'name': (json['name'] ?? '').toString(), 'mode': 'view'},
            ),
          ));
        }
      }
      _previewCache[key] = rows;
      // Guard against a chip change landing before this fetch returns.
      if (doctype == selectedActionable.value) previewDocs.assignAll(rows);
    } catch (e) {
      print('Error fetching preview docs: $e');
    } finally {
      if (doctype == selectedActionable.value) isLoadingPreview.value = false;
    }
  }

  /// Flips the strip scope, persists it, and loads the new scope's counts
  /// (served from cache when available, so a second flip is instant), then
  /// re-applies the default chip selection — the current selection may have
  /// zero work under the new scope, and a chip with zero count is muted/
  /// non-interactive, so it must not remain selected.
  Future<void> setActionableScope(ActionableScope scope) async {
    if (actionableScope.value == scope) return;
    actionableScope.value = scope;
    _storageService.saveDashboardActionableScope(actionableScopeToString(scope));
    await fetchActionableCounts();
    // Guard against a scope flip landing before this fetch returns — mirrors
    // the fetchActionableCounts/fetchPreviewDocs guards above.
    if (scope != actionableScope.value) return;
    _applyDefaultSelection();
  }

  /// Opens [doctype]'s list pre-filtered to Draft (+ owner under Mine), via the
  /// list controller's onReady `filters` hook (Task 4).
  void openActionableList(String doctype) {
    final cfg =
        kActionableDocConfigs.firstWhereOrNull((c) => c.doctype == doctype);
    if (cfg == null) return;
    final email = selectedFilterUser.value?.email ??
        _authController.currentUser.value?.email;
    Get.toNamed(cfg.listRoute, arguments: {
      'filters': actionableFiltersFor(doctype, actionableScope.value, email),
    });
  }

  /// Recomputes the section-order verdict from the logged-in user's roles
  /// and the just-fetched ToDo list, then persists it per user so the NEXT
  /// session's initial build starts from this verdict. On a failed fetch
  /// the previous verdict is deliberately kept (no recompute call).
  ///
  /// [tasksFirst.value] always reflects whatever is currently on screen,
  /// including while viewing a direct report's dashboard via the
  /// user-switcher (`selectedFilterUser`). Persistence, however, is
  /// skipped in that case — it only happens when viewing self — so a
  /// manager's own seed is never polluted by a viewed report's ToDo count.
  void _recomputeTasksFirst() {
    final user = _authController.currentUser.value;
    final v = showTasksFirst(
      roles: user?.roles ?? const [],
      hasOpenTodos: upcomingTodos.isNotEmpty,
    );
    tasksFirst.value = v;
    final email = user?.email;
    final isViewingSelf = selectedFilterUser.value == null ||
        selectedFilterUser.value?.email == email;
    if (email != null && email.isNotEmpty && isViewingSelf) {
      _storageService.saveDashboardTasksFirst(email, v);
    }
  }

  Future<void> _fetchActiveWipJc() async {
    final empId = _authController.currentUser.value?.employeeId;
    if (empId == null || empId.isEmpty) return;
    try {
      final res = await _jcProvider.getJobCards(
        filters: {
          'status': 'Work In Progress',
          '__child__Job Card Time Log': ['Job Card Time Log', 'employee', '=', empId],
        },
        limit: 1,
      );
      if (res.statusCode == 200) {
        final list = (res.data['data'] as List?) ?? [];
        activeWipJcName.value      = list.isNotEmpty ? list.first['name']?.toString() : null;
        activeWipJcOperation.value = list.isNotEmpty ? list.first['operation']?.toString() : null;
      }
    } catch (_) {}
  }

  // --- Timeline Logic ---
  void toggleTimelineView(String mode) {
    if (timelineViewMode.value == mode) return;
    timelineViewMode.value = mode;
    fetchPerformanceData();
  }

  void onDailyDateChanged(DateTime date) {
    selectedDailyDate.value = date;
    if (timelineViewMode.value != 'Weekly') fetchPerformanceData();
  }

  void onWeeklyRangeChanged(DateTimeRange range) {
    selectedWeeklyRange.value = range;
    if (timelineViewMode.value == 'Weekly') fetchPerformanceData();
  }

  Future<void> fetchPerformanceData() async {
    isLoadingTimeline.value = true;
    try {
      final email = selectedFilterUser.value?.email ?? _authController.currentUser.value?.email;
      if (email == null) return;

      DateTime startDate;
      DateTime endDate;
      Map<String, TimelinePoint> buckets = {};

      if (timelineViewMode.value == 'Weekly') {
        startDate = selectedWeeklyRange.value.start;
        endDate = selectedWeeklyRange.value.end;
        DateTime current = startDate;
        while (current.isBefore(endDate) || current.isAtSameMomentAs(endDate)) {
          final key = '${current.year}-${current.month}-W${_getWeekOfMonth(current)}';
          final label = '${DateFormat('MMM').format(current)} W${_getWeekOfMonth(current)}';
          if (!buckets.containsKey(key)) {
            buckets[key] = TimelinePoint(label: label, date: current);
          }
          current = current.add(const Duration(days: 7));
        }
      } else if (timelineViewMode.value == 'Hourly') {
        startDate = selectedDailyDate.value;
        endDate = startDate.add(const Duration(hours: 23, minutes: 59));
        for (int i = 0; i < 24; i++) {
          final key = i.toString();
          final label = '${i.toString().padLeft(2, '0')}:00';
          buckets[key] = TimelinePoint(label: label, date: startDate);
        }
      } else {
        endDate = selectedDailyDate.value;
        startDate = endDate.subtract(const Duration(days: 6));
        for (int i = 0; i < 7; i++) {
          final date = endDate.subtract(Duration(days: (6 - i)));
          final key = DateFormat('yyyy-MM-dd').format(date);
          final label = DateFormat('E').format(date);
          buckets[key] = TimelinePoint(label: label, date: date);
        }
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(startDate);
      final filters = {'owner': email, 'docstatus': ['<', 2]};

      if (timelineViewMode.value == 'Hourly') {
        filters['creation'] = ['between', [
          DateFormat('yyyy-MM-dd 00:00:00').format(startDate),
          DateFormat('yyyy-MM-dd 23:59:59').format(startDate)
        ]];
      } else {
        filters['creation'] = ['>=', dateStr];
      }

      final results = await Future.wait([
        _apiProvider.getDocumentList('Delivery Note', filters: filters, fields: ['creation', 'total_qty', 'customer'], limit: 100),
        _apiProvider.getDocumentList('Stock Entry', filters: filters, fields: ['creation', 'custom_total_qty'], limit: 100),
        _apiProvider.getDocumentList('Purchase Receipt', filters: filters, fields: ['creation', 'total_qty'], limit: 100),
      ]);

      final dnList = _extractList(results[0]);
      final seList = _extractList(results[1]);
      final prList = _extractList(results[2]);

      void fillBucket(List<dynamic> list, String type) {
        for (var item in list) {
          final date = DateTime.parse(item['creation']);
          if (timelineViewMode.value != 'Hourly' && date.isAfter(endDate.add(const Duration(days: 1)))) continue;

          String key;
          if (timelineViewMode.value == 'Weekly') {
            key = '${date.year}-${date.month}-W${_getWeekOfMonth(date)}';
          } else if (timelineViewMode.value == 'Hourly') {
            key = date.hour.toString();
          } else {
            key = DateFormat('yyyy-MM-dd').format(date);
          }

          if (buckets.containsKey(key)) {
            final existing = buckets[key]!;
            double qty = 0.0;
            if (type == 'DN') qty = _safeParseDouble(item['total_qty']);
            else if (type == 'SE') qty = _safeParseDouble(item['custom_total_qty']);
            else if (type == 'PR') qty = _safeParseDouble(item['total_qty']);

            int custCount = (type == 'DN' && item['customer'] != null) ? 1 : 0;
            buckets[key] = TimelinePoint(
              label: existing.label,
              date: existing.date,
              deliveryQty: existing.deliveryQty + (type == 'DN' ? qty : 0),
              stockQty: existing.stockQty + (type == 'SE' ? qty : 0),
              receiptQty: existing.receiptQty + (type == 'PR' ? qty : 0),
              customerCount: existing.customerCount + custCount,
            );
          }
        }
      }

      fillBucket(dnList, 'DN');
      fillBucket(seList, 'SE');
      fillBucket(prList, 'PR');

      timelineData.assignAll(buckets.values.toList());
    } catch (e) {
      print('Error fetching timeline: $e');
    } finally {
      isLoadingTimeline.value = false;
    }
  }

  // --- Scan & Item Sheet Logic ---
  Future<void> onScan(String code) async {
    if (isScanning.value) return;
    if (code.isEmpty) return;

    isScanning.value = true;
    try {
      // POS Upload document labels (e.g. ML-2026-02011) are scanned on the
      // Dashboard to jump straight to fulfillment work. Recognise them before
      // ScanService, which would otherwise misread the hyphenated name as a
      // rack asset-code and fail.
      final trimmed = code.trim();
      if (ScanConstants.isPosUploadDocName(trimmed)) {
        await _handlePosUploadScan(trimmed);
        return;
      }

      final result = await _scanService.processScan(code);

      if (result.type == ScanType.rack && result.rackId != null) {
        await _handleRackScan(result.rackId!);
      }
      else if (result.isSuccess && (result.type == ScanType.item || result.type == ScanType.batch) && result.itemData != null) {
        _openItemDetailSheet(result.itemData!.itemCode, batchNo: result.batchNo);
      }
      else if (result.type == ScanType.variant_of) {
        barcodeController.clear();
        Get.toNamed(AppRoutes.ITEM, arguments: {
          'filters': {
            'variant_of': ['like', '%${result.rawCode}%']
          },
          'pageTitle': 'Variant: ${result.rawCode}'
        });
      }
      else if (result.type == ScanType.multiple && result.candidates != null) {
        barcodeController.clear();
        Get.bottomSheet(
          MultiItemSelectionSheet(
            items: result.candidates!,
            onItemSelected: (item) => _openItemDetailSheet(item.itemCode),
          ),
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
        );
      } else {
        GlobalSnackbar.error(title: 'Not Found', message: result.message ?? 'Item not found');
      }
    } catch (e) {
      GlobalSnackbar.error(title: 'Scan Error', message: '$e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  void _openItemDetailSheet(String itemCode, {String? batchNo}) {
    Get.put(ItemTabController());
    Get.put(ItemFormController())..loadItem(itemCode, batchNo: batchNo);
    // The modal path bypasses ItemFormBinding; the Re-order tab's warehouse
    // pickers need this.
    if (!Get.isRegistered<WarehouseProvider>()) {
      Get.put(WarehouseProvider());
    }
    barcodeController.clear();

    Get.bottomSheet(
      FractionallySizedBox(
        heightFactor: 0.9,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: const ItemFormScreen(),
        ),
      ),
      isScrollControlled: true,
      // Drag-dismiss calls Navigator.pop directly, which PopScope cannot
      // intercept, so unsaved re-order rules could vanish with a swipe.
      // enableDrag is fixed at open time and cannot track dirty state, so it
      // is off; the Close button (guarded by _confirmDiscard) is the exit.
      enableDrag: false,
    ).then((_) {
      Get.delete<ItemTabController>(force: true);
      Get.delete<ItemFormController>(force: true);
    });
  }

  Future<void> _handleRackScan(String rackCode) async {
    isRackScanning.value = true;
    barcodeController.clear();
    try {
      final parts = rackCode.split('-');
      if (parts.length < 3) throw Exception('Invalid Rack Format');
      final String warehouse = '${parts[1]}-${parts[2]} - ${parts[0]}';

      final response = await _itemProvider.getWarehouseStock(warehouse);

      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> data = response.data['message']['result'];

        final rackItems = data.where((row) {
          final rowRack = row['rack']?.toString() ?? '';
          return rowRack == rackCode;
        }).toList();

        if (rackItems.isEmpty) {
          GlobalSnackbar.info(title: 'Empty Rack', message: 'No items found in rack $rackCode');
        } else {
          Get.bottomSheet(
            RackContentsSheet(rackId: rackCode, items: rackItems),
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
          );
        }
      } else {
        GlobalSnackbar.error(message: 'Failed to fetch stock for warehouse $warehouse');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Invalid Rack QR or Network Error');
    } finally {
      isRackScanning.value = false;
    }
  }

  // --- Fulfillment Logic ---
  Future<void> fetchFulfillmentPosUploads() async {
    isFetchingFulfillmentList.value = true;
    try {
      final response = await _posUploadProvider.getPosUploads(
          limit: 100, filters: {'status': ['in', ['Pending', 'In Progress']]}, orderBy: 'modified desc'
      );
      if(response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'];
        _allFulfillmentUploads = (data as List).map((e)=>PosUpload.fromJson(e)).toList();
        filterFulfillmentList(fulfillmentSearchQuery.value);
      }
    } catch(e){
      GlobalSnackbar.error(message: 'Error fetching fulfillment list');
    } finally {
      isFetchingFulfillmentList.value = false;
    }
  }

  void setFulfillmentPrefixFilter(List<String> prefixes) {
    _fulfillmentPrefixFilters = prefixes;
    fulfillmentSearchQuery.value = '';
    if (_allFulfillmentUploads.isNotEmpty) {
      filterFulfillmentList('');
    }
  }

  void filterFulfillmentList(String query) {
    fulfillmentSearchQuery.value = query;
    List<PosUpload> filtered = _allFulfillmentUploads;

    if (_fulfillmentPrefixFilters.isNotEmpty) {
      filtered = filtered.where((doc) {
        return _fulfillmentPrefixFilters.any((prefix) => doc.name.startsWith(prefix));
      }).toList();
    }

    if (query.isNotEmpty) {
      filtered = filtered.where((d) =>
      d.name.toLowerCase().contains(query.toLowerCase()) ||
          d.customer.toLowerCase().contains(query.toLowerCase())
      ).toList();
    }

    fulfillmentPosUploads.assignAll(filtered);
  }

  Future<void> handleFulfillmentSelection(PosUpload posUpload) async {
    Get.back();

    GlobalSnackbar.info(message: 'Processing ${posUpload.name}...');
    final name = posUpload.name.toUpperCase();
    if (name.startsWith('KX') || name.startsWith('MX')) {
      await _openLinkedStockEntry(posUpload);
    } else {
      await _openLinkedDeliveryNote(posUpload);
    }
  }

  // ── POS Upload scan → linked document ────────────────────────────────────
  // A POS Upload document label scanned on the Dashboard jumps to its
  // fulfillment work. MX/KX uploads link to a Stock Entry (opened directly);
  // ML/KA uploads link to a Delivery Note whose cartons are packed via Packing
  // Slips, so the operator is asked which of the two to open.

  Future<void> _handlePosUploadScan(String name) async {
    final PosUpload? upload = await _fetchPosUploadByName(name);
    if (upload == null) {
      GlobalSnackbar.error(
          title: 'Not Found', message: 'POS Upload "$name" was not found.');
      return;
    }

    if (ScanConstants.isStockEntryFamilyUpload(name)) {
      GlobalSnackbar.info(message: 'Opening Stock Entry for ${upload.name}…');
      await _openLinkedStockEntry(upload);
      return;
    }

    // Delivery-Note-family (ML/KA): let the operator choose DN vs Packing Slip.
    Get.bottomSheet(
      PosUploadScanTargetSheet(
        posUpload: upload,
        onDeliveryNote: () {
          Get.back();
          _openLinkedDeliveryNote(upload);
        },
        onPackingSlip: () {
          Get.back();
          _openLinkedPackingSlip(upload);
        },
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  Future<PosUpload?> _fetchPosUploadByName(String name) async {
    try {
      final res = await _posUploadProvider.getPosUpload(name);
      if (res.statusCode == 200 && res.data['data'] != null) {
        return PosUpload.fromJson(res.data['data']);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _openLinkedStockEntry(PosUpload posUpload) async {
    try {
      final res = await _stockEntryProvider.getStockEntries(
          limit: 1, filters: {'custom_reference_no': posUpload.name});
      if (res.statusCode == 200 &&
          res.data['data'] != null &&
          (res.data['data'] as List).isNotEmpty) {
        Get.toNamed(AppRoutes.STOCK_ENTRY_FORM,
            arguments: {'name': res.data['data'][0]['name'], 'mode': 'edit'});
      } else {
        Get.toNamed(AppRoutes.STOCK_ENTRY_FORM, arguments: {
          'name': '',
          'mode': 'new',
          'stockEntryType': 'Material Issue',
          'customReferenceNo': posUpload.name
        });
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Error processing Stock Entry');
    }
  }

  Future<void> _openLinkedDeliveryNote(PosUpload posUpload) async {
    try {
      final res = await _deliveryNoteProvider.getDeliveryNotes(
          limit: 1, filters: {'po_no': posUpload.name});
      if (res.statusCode == 200 &&
          res.data['data'] != null &&
          (res.data['data'] as List).isNotEmpty) {
        Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM,
            arguments: {'name': res.data['data'][0]['name'], 'mode': 'edit'});
      } else {
        Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM, arguments: {
          'name': '',
          'mode': 'new',
          'posUploadCustomer': posUpload.customer,
          'posUploadName': posUpload.name
        });
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Error processing Delivery Note');
    }
  }

  /// Opens the Packing Slip for a scanned ML/KA upload. A Packing Slip hangs
  /// off the Delivery Note (not the upload), so the DN is resolved first: with
  /// no DN the upload can have no slip (per product decision, we just say so);
  /// with none yet a new case is started; with one it opens directly; with
  /// several the operator picks the case.
  Future<void> _openLinkedPackingSlip(PosUpload posUpload) async {
    try {
      final dnRes = await _deliveryNoteProvider.getDeliveryNotes(
          limit: 1, filters: {'po_no': posUpload.name});
      final dnList = (dnRes.data['data'] as List?) ?? const [];
      if (dnRes.statusCode != 200 || dnList.isEmpty) {
        GlobalSnackbar.error(
            title: 'No Delivery Note',
            message:
                'No Delivery Note exists for ${posUpload.name} yet, so it has no Packing Slip.');
        return;
      }
      final dnName = dnList.first['name'].toString();

      final psRes = await _packingSlipProvider.getPackingSlips(
          limit: 0,
          filters: {'delivery_note': dnName},
          orderBy: 'from_case_no asc');
      if (psRes.statusCode != 200) {
        GlobalSnackbar.error(message: 'Failed to load Packing Slips');
        return;
      }
      final psList = ((psRes.data['data'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

      if (psList.isEmpty) {
        _openNewPackingSlip(dnName, posUpload.name, 1);
      } else if (psList.length == 1) {
        Get.toNamed(AppRoutes.PACKING_SLIP_FORM, arguments: {
          'name': psList.first['name'].toString(),
          'mode': 'edit'
        });
      } else {
        final nextCase = psList
                .map((e) => (e['to_case_no'] as num?)?.toInt() ?? 0)
                .fold<int>(0, (a, b) => a > b ? a : b) +
            1;
        Get.bottomSheet(
          PackingSlipPickerSheet(
            deliveryNote: dnName,
            nextCaseNo: nextCase,
            packingSlips: psList,
            onSelect: (psName) {
              Get.back();
              Get.toNamed(AppRoutes.PACKING_SLIP_FORM,
                  arguments: {'name': psName, 'mode': 'edit'});
            },
            onNewCase: () {
              Get.back();
              _openNewPackingSlip(dnName, posUpload.name, nextCase);
            },
          ),
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
        );
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Error opening Packing Slip');
    }
  }

  void _openNewPackingSlip(String dnName, String poNo, int nextCaseNo) {
    Get.toNamed(AppRoutes.PACKING_SLIP_FORM, arguments: {
      'name': '',
      'mode': 'new',
      'deliveryNote': dnName,
      'customPoNo': poNo,
      'nextCaseNo': nextCaseNo,
    });
  }

  // Helpers
  int _getWeekOfMonth(DateTime date) {
    int week = ((date.day - 1) / 7).floor() + 1;
    return week > 4 ? 4 : week;
  }
  double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
  List<dynamic> _extractList(Response response) {
    if (response.statusCode == 200 && response.data['data'] != null) {
      return response.data['data'] as List;
    }
    return [];
  }
  int _extractCount(dynamic response) {
    if (response is Response &&
        response.statusCode == 200 &&
        response.data?['message'] is int) {
      return response.data['message'] as int;
    }
    return 0;
  }

  void onBottomBarItemTapped(int index) { if (index == 0) fetchDashboardData(); }
  void updateActiveScreen(String route) { _updateActiveScreenForRoute(route); }

  void _updateActiveScreenForRoute(String route) {
    switch (route) {
      case AppRoutes.HOME:             activeScreen.value = ActiveScreen.home;            selectedDrawerIndex.value = 0;  break;
      case AppRoutes.STOCK_ENTRY:      activeScreen.value = ActiveScreen.stockEntry;      selectedDrawerIndex.value = 1;  break;
      case AppRoutes.DELIVERY_NOTE:    activeScreen.value = ActiveScreen.deliveryNote;    selectedDrawerIndex.value = 2;  break;
      case AppRoutes.PACKING_SLIP:     activeScreen.value = ActiveScreen.packingSlip;     selectedDrawerIndex.value = 3;  break;
      case AppRoutes.PURCHASE_RECEIPT: activeScreen.value = ActiveScreen.purchaseReceipt; selectedDrawerIndex.value = 4;  break;
      case AppRoutes.POS_UPLOAD:       activeScreen.value = ActiveScreen.posUpload;       selectedDrawerIndex.value = 5;  break;
      case AppRoutes.TODO:             activeScreen.value = ActiveScreen.todo;            selectedDrawerIndex.value = 6;  break;
      case AppRoutes.ITEM:             activeScreen.value = ActiveScreen.item;            selectedDrawerIndex.value = 7;  break;
      case AppRoutes.WORK_ORDER:       activeScreen.value = ActiveScreen.home;            selectedDrawerIndex.value = 8;  break;
      case AppRoutes.JOB_CARD:         activeScreen.value = ActiveScreen.home;            selectedDrawerIndex.value = 9;  break;
      case AppRoutes.BATCH:            activeScreen.value = ActiveScreen.batch;           selectedDrawerIndex.value = 10; break;
      case AppRoutes.BOM:              activeScreen.value = ActiveScreen.bom;             selectedDrawerIndex.value = 11; break;
    }
  }

  void changeDrawerPage(int index, String route) {
    selectedDrawerIndex.value = index;
    if (Get.currentRoute != route) {
      Get.toNamed(route);
      _updateActiveScreenForRoute(route);
    }
  }

  void goToHome()            => changeDrawerPage(0,  AppRoutes.HOME);
  void goToStockEntry()      => changeDrawerPage(1,  AppRoutes.STOCK_ENTRY);
  void goToDeliveryNote()    => changeDrawerPage(2,  AppRoutes.DELIVERY_NOTE);
  void goToPackingSlip()     => changeDrawerPage(3,  AppRoutes.PACKING_SLIP);
  void goToPurchaseReceipt() => changeDrawerPage(4,  AppRoutes.PURCHASE_RECEIPT);
  void goToPosUpload()       => changeDrawerPage(5,  AppRoutes.POS_UPLOAD);
  void goToToDo()            => changeDrawerPage(6,  AppRoutes.TODO);
  void goToItem()            => changeDrawerPage(7,  AppRoutes.ITEM);
  void goToWorkOrder()       => changeDrawerPage(8,  AppRoutes.WORK_ORDER);
  void goToJobCard()         => changeDrawerPage(9,  AppRoutes.JOB_CARD);
  void goToBatch()           => changeDrawerPage(10, AppRoutes.BATCH);
  void goToBOM()             => changeDrawerPage(11, AppRoutes.BOM);
}
