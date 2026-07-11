import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/enums/save_result.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/models/todo_model.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/todo_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/services/global_search_service.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/user_picker_sheet.dart';

/// GetX controller for the **ToDo form** screen.
///
/// Operates in three modes read from `Get.arguments['mode']`:
/// - `'new'`  — blank editable form.
/// - `'edit'` — fetches the existing [ToDo] and allows changes.
/// - `'view'` — fetches the existing [ToDo] read-only (no save/close actions).
///
/// ToDo is a non-submittable Frappe DocType (no `docstatus`), so unlike most
/// forms in this app [isEditable] is derived from [mode] alone.
class ToDoFormController extends GetxController with OptimisticLockingMixin {
  final ToDoProvider _provider = Get.find<ToDoProvider>();
  final UserProvider _userProvider = Get.find<UserProvider>();
  final GlobalSearchService _searchService =
      Get.isRegistered<GlobalSearchService>()
          ? Get.find<GlobalSearchService>()
          : Get.put(GlobalSearchService());

  static const List<String> statusOptions = ['Open', 'Closed', 'Cancelled'];
  static const List<String> priorityOptions = [
    'Low',
    'Medium',
    'High',
    'Urgent',
  ];

  /// ToDo document name (ERPNext `name` field). Empty string in new mode.
  String name = (Get.arguments is Map ? Get.arguments['name'] : null) ?? '';

  /// Form mode: `'new'`, `'edit'`, or `'view'`.
  String mode =
      (Get.arguments is Map ? Get.arguments['mode'] : null) ?? 'view';

  /// `true` during any API fetch (initial load or reload).
  var isLoading = true.obs;

  /// `true` while [saveDocument] is in flight.
  var isSaving = false.obs;

  /// `true` while [toggleCloseReopen] is in flight.
  var isClosing = false.obs;

  /// `true` when the form has unsaved changes. Always `true` in new mode.
  var isDirty = false.obs;

  /// Drives the animated Save button state.
  var saveResult = SaveResult.idle.obs;

  /// Reactive reference to the current [ToDo] model.
  var todo = Rx<ToDo?>(null);

  // ── Form controllers ─────────────────────────────────────────────────
  final descriptionController = TextEditingController();

  final status = 'Open'.obs;
  final priority = 'Medium'.obs;
  final date = ''.obs;
  final referenceType = ''.obs;
  final referenceName = ''.obs;
  final allocatedTo = ''.obs;
  final allocatedToDisplay = ''.obs;

  // ── Allocated-to picker state ───────────────────────────────────────────
  var users = <User>[].obs;
  var isFetchingUsers = false.obs;

  // ── Reference-name picker state ─────────────────────────────────────────
  var referenceSearchResults = <GlobalSearchItem>[].obs;
  var isSearchingReference = false.obs;

  /// `true` when [mode] is not `'view'`. ToDo has no `docstatus`, so
  /// editability is derived from the form mode alone.
  bool get isEditable => mode != 'view';

  /// Whether the quick Close/Reopen header action should render — only for
  /// an already-saved, editable, non-cancelled ToDo. Explicitly `mode ==
  /// 'edit'` (not just `!= 'new'`) so it stays hidden in 'view' mode, which
  /// is documented above as read-only.
  bool get canShowCloseAction =>
      mode == 'edit' && name.isNotEmpty && status.value != 'Cancelled';

  /// Reference-type options the current user may read, sourced from the
  /// shared doctype→route registry so a ToDo can point at anything the
  /// Dashboard global search can also reach.
  List<GlobalSearchTarget> get referenceTypeOptions {
    final permissionService = Get.find<PermissionService>();
    return GlobalSearchService.filterPermittedTargets(
      kGlobalSearchTargets,
      (doctype) => permissionService.hasAccess(doctype),
    );
  }

  /// JSON snapshot of the editable fields immediately after a successful
  /// fetch — [_checkForChanges] diffs against this so reverting a field to
  /// its original value clears [isDirty] again, instead of latching dirty
  /// forever on the first edit. Mirrors the pattern used by the DN/PO/PS
  /// form controllers.
  String _originalJson = '';

  @override
  void onInit() {
    super.onInit();
    descriptionController.addListener(_checkForChanges);

    if (mode == 'new') {
      _initNewTodo();
    } else {
      fetchDocument();
    }
  }

  @override
  void onClose() {
    descriptionController.dispose();
    super.onClose();
  }

  Map<String, dynamic> _currentFormSnapshot() => {
        'description': descriptionController.text,
        'status': status.value,
        'priority': priority.value,
        'date': date.value,
        'reference_type': referenceType.value,
        'reference_name': referenceName.value,
        'allocated_to': allocatedTo.value,
      };

  void _checkForChanges() {
    if (!isEditable) return;
    if (mode == 'new') {
      isDirty.value = true;
      return;
    }
    isDirty.value = jsonEncode(_currentFormSnapshot()) != _originalJson;
  }

  // ── Document init / fetch ────────────────────────────────────────────

  void _initNewTodo() {
    status.value = 'Open';
    priority.value = 'Medium';
    descriptionController.clear();
    date.value = '';
    referenceType.value = '';
    referenceName.value = '';
    allocatedTo.value = '';
    allocatedToDisplay.value = '';

    todo.value = ToDo(
      name: 'New ToDo',
      status: 'Open',
      description: '',
      modified: '',
      priority: 'Medium',
      date: '',
    );

    _originalJson = '';
    isLoading.value = false;
    isDirty.value = true;
  }

  Future<void> fetchDocument() async {
    isLoading.value = true;
    try {
      final response = await _provider.getTodo(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final t = ToDo.fromJson(response.data['data']);
        todo.value = t;

        descriptionController.text = t.description;
        date.value = t.date;
        status.value = t.status;
        priority.value = t.priority;
        referenceType.value = t.referenceType;
        referenceName.value = t.referenceName;
        allocatedTo.value = t.allocatedTo;
        allocatedToDisplay.value = t.allocatedTo;

        _originalJson = jsonEncode(_currentFormSnapshot());
        isDirty.value = false;
      } else {
        GlobalSnackbar.error(message: 'Failed to fetch ToDo');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  @override
  Future<void> reloadDocument() async {
    await fetchDocument();
    GlobalSnackbar.success(message: 'Document reloaded successfully');
  }

  // ── Dirty / navigation ───────────────────────────────────────────────

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  // ── Field interactions ───────────────────────────────────────────────

  Future<void> pickDate() async {
    if (!isEditable) return;
    final DateTime? picked = await showDatePicker(
      context: Get.context!,
      initialDate: DateTime.tryParse(date.value) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      date.value = DateFormat('yyyy-MM-dd').format(picked);
      _checkForChanges();
    }
  }

  void clearDate() {
    if (!isEditable) return;
    date.value = '';
    _checkForChanges();
  }

  void setStatus(String value) {
    if (!isEditable || value == status.value) return;
    status.value = value;
    _checkForChanges();
  }

  void setPriority(String value) {
    if (!isEditable || value == priority.value) return;
    priority.value = value;
    _checkForChanges();
  }

  void setReferenceType(String doctype) {
    if (!isEditable) return;
    if (doctype != referenceType.value) {
      referenceType.value = doctype;
      referenceName.value = '';
      referenceSearchResults.clear();
      _checkForChanges();
    }
  }

  void setReferenceName(String docName) {
    if (!isEditable) return;
    referenceName.value = docName;
    _checkForChanges();
  }

  void clearReference() {
    if (!isEditable) return;
    referenceType.value = '';
    referenceName.value = '';
    referenceSearchResults.clear();
    _checkForChanges();
  }

  void setAllocatedTo(String userId, String displayName) {
    if (!isEditable) return;
    allocatedTo.value = userId;
    allocatedToDisplay.value = displayName;
    _checkForChanges();
  }

  void clearAllocatedTo() {
    if (!isEditable) return;
    allocatedTo.value = '';
    allocatedToDisplay.value = '';
    _checkForChanges();
  }

  // ── Reference-name search ────────────────────────────────────────────

  Future<void> searchReferenceDocs(String query) async {
    if (referenceType.value.isEmpty) return;
    isSearchingReference.value = true;
    try {
      final results = await _searchService.search(referenceType.value, query);
      referenceSearchResults.assignAll(results);
    } finally {
      isSearchingReference.value = false;
    }
  }

  // ── Allocated-to picker ──────────────────────────────────────────────

  Future<void> fetchUsers() async {
    if (users.isNotEmpty) return;
    isFetchingUsers.value = true;
    try {
      final response = await _userProvider.getUsers();
      if (response.statusCode == 200 && response.data['data'] != null) {
        users.assignAll(
          (response.data['data'] as List).map((e) => User.fromJson(e)),
        );
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to fetch users: $e');
    } finally {
      isFetchingUsers.value = false;
    }
  }

  Future<void> showAllocatedToPicker() async {
    if (!isEditable) return;
    if (users.isEmpty) await fetchUsers();
    Get.bottomSheet(
      UserPickerSheet(
        users: users,
        isLoading: isFetchingUsers.value,
        title: 'Assign To',
        onSelected: setAllocatedTo,
      ),
      isScrollControlled: true,
    );
  }

  // ── Save ──────────────────────────────────────────────────────────────

  Future<void> saveDocument() async {
    if (isSaving.value) return;
    if (checkStaleAndBlock()) return;

    isSaving.value = true;

    final data = <String, dynamic>{
      'description': descriptionController.text,
      'status': status.value,
      'priority': priority.value,
      'date': date.value.isEmpty ? null : date.value,
      'reference_type':
          referenceType.value.isEmpty ? null : referenceType.value,
      'reference_name':
          referenceName.value.isEmpty ? null : referenceName.value,
      'allocated_to': allocatedTo.value.isEmpty ? null : allocatedTo.value,
    };
    if (mode != 'new') {
      data['modified'] = todo.value?.modified;
    }

    try {
      if (mode == 'new') {
        final response = await _provider.createTodo(data);
        if (response.statusCode == 200 && response.data['data'] != null) {
          name = response.data['data']['name'];
          mode = 'edit';
          await fetchDocument();
          saveResult.value = SaveResult.success;
          GlobalSnackbar.success(message: 'ToDo Created');
        } else {
          saveResult.value = SaveResult.error;
          GlobalSnackbar.error(message: 'Failed to create ToDo');
        }
      } else {
        final response = await _provider.updateTodo(name, data);
        if (response.statusCode == 200) {
          await fetchDocument();
          saveResult.value = SaveResult.success;
          GlobalSnackbar.success(message: 'ToDo Updated');
        } else {
          saveResult.value = SaveResult.error;
          GlobalSnackbar.error(message: 'Failed to update ToDo');
        }
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;

      saveResult.value = SaveResult.error;
      String errorMessage = 'Save failed';
      if (e.response?.data is Map) {
        if (e.response!.data['exception'] != null) {
          errorMessage =
              e.response!.data['exception'].toString().split(':').last.trim();
        } else if (e.response!.data['_server_messages'] != null) {
          errorMessage = 'Validation Error: Check form details';
        }
      }
      GlobalSnackbar.error(message: errorMessage);
    } catch (e) {
      saveResult.value = SaveResult.error;
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  // ── Close / Reopen quick action ──────────────────────────────────────

  Future<void> toggleCloseReopen() async {
    if (isClosing.value) return;
    if (!canShowCloseAction) return;
    if (checkStaleAndBlock()) return;

    final isClosingAction = status.value != 'Closed';
    final confirmed = await GlobalDialog.confirm(
      title: isClosingAction ? 'Close ToDo?' : 'Reopen ToDo?',
      message: isClosingAction
          ? 'Mark this task as closed.'
          : 'Reopen this task and set its status back to Open.',
      confirmText: isClosingAction ? 'Close' : 'Reopen',
      icon: isClosingAction ? Icons.check_circle_outline : Icons.replay,
    );
    if (confirmed != true) return;

    isClosing.value = true;
    try {
      final modified = todo.value?.modified;
      final response = isClosingAction
          ? await _provider.closeTodo(name, modified: modified)
          : await _provider.reopenTodo(name, modified: modified);
      if (response.statusCode == 200) {
        GlobalSnackbar.success(
          message: isClosingAction ? 'ToDo Closed' : 'ToDo Reopened',
        );
        await fetchDocument();
      } else {
        GlobalSnackbar.error(message: 'Failed to update ToDo status');
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      GlobalSnackbar.error(message: 'Failed to update ToDo status: ${e.message}');
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to update ToDo status: $e');
    } finally {
      isClosing.value = false;
    }
  }
}
