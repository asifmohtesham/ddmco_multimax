import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/todo_model.dart';
import 'package:multimax/app/data/providers/todo_provider.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';

class ToDoController extends GetxController {
  final ToDoProvider _provider = Get.find<ToDoProvider>();

  /// Exposed so filter/appbar widgets can call provider helpers directly.
  ToDoProvider get todoProvider => _provider;

  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;
  var todos = <ToDo>[].obs;
  var filteredTodos = <ToDo>[].obs;
  final int _limit = 20;
  int _currentPage = 0;

  var expandedTodoName = ''.obs;
  var isLoadingDetails = false.obs;

  /// Name of the ToDo currently being closed/reopened, or `null` when idle.
  /// Scoped per-document (not a single shared flag) so closing one card's
  /// ToDo doesn't disable every other card's Close button.
  var closingTodoName = RxnString();
  final _detailedTodosCache = <String, ToDo>{}.obs;

  final activeFilters = <String, dynamic>{}.obs;
  final searchQuery = ''.obs;
  var sortField = 'modified'.obs;
  var sortOrder = 'desc'.obs;

  @override
  void onInit() {
    super.onInit();
    fetchTodos();
  }

  ToDo? get detailedTodo => _detailedTodosCache[expandedTodoName.value];

  // ── Filter / Sort API ─────────────────────────────────────────────────────

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = Map.from(filters);
    fetchTodos(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    sortField.value = 'modified';
    sortOrder.value = 'desc';
    fetchTodos(isLoadMore: false, clear: true);
  }

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetchTodos(isLoadMore: false, clear: true);
  }

  void setSort(String field, String order) {
    sortField.value = field;
    sortOrder.value = order;
    fetchTodos(isLoadMore: false, clear: true);
  }

  // ── Local search ────────────────────────────────────────────────────────

  void onSearchChanged(String query) {
    searchQuery.value = query;
    _applyLocalSearch();
  }

  void _applyLocalSearch() {
    if (searchQuery.value.isEmpty) {
      filteredTodos.assignAll(todos);
    } else {
      final q = searchQuery.value.toLowerCase();
      filteredTodos.assignAll(todos.where((todo) =>
          todo.name.toLowerCase().contains(q) ||
          todo.description.toLowerCase().contains(q) ||
          todo.priority.toLowerCase().contains(q) ||
          todo.status.toLowerCase().contains(q)));
    }
  }

  // ── Fetch ───────────────────────────────────────────────────────────────────

  Future<void> fetchTodos({bool isLoadMore = false, bool clear = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      if (clear) {
        todos.clear();
        filteredTodos.clear();
        _currentPage = 0;
        hasMore.value = true;
      }
    }

    try {
      final response = await _provider.getTodos(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: Map<String, dynamic>.from(activeFilters),
        orderBy: '${sortField.value} ${sortOrder.value}',
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newTodos = data.map((json) => ToDo.fromJson(json)).toList();

        if (newTodos.length < _limit) hasMore.value = false;

        if (isLoadMore) {
          todos.addAll(newTodos);
        } else {
          todos.value = newTodos;
        }

        _applyLocalSearch();
        _currentPage++;
      } else {
        AppNotification.error('Failed to fetch ToDos');
      }
    } catch (e) {
      AppNotification.error(e.toString());
    } finally {
      if (isLoadMore) {
        isFetchingMore.value = false;
      } else {
        isLoading.value = false;
      }
    }
  }

  // ── Detail expand ───────────────────────────────────────────────────────────

  Future<void> _fetchAndCacheTodoDetails(String name) async {
    if (_detailedTodosCache.containsKey(name)) return;
    isLoadingDetails.value = true;
    try {
      final response = await _provider.getTodo(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        _detailedTodosCache[name] = ToDo.fromJson(response.data['data']);
      } else {
        AppNotification.error('Failed to fetch ToDo details');
      }
    } catch (e) {
      AppNotification.error(e.toString());
    } finally {
      isLoadingDetails.value = false;
    }
  }

  void toggleExpand(String name) {
    if (expandedTodoName.value == name) {
      expandedTodoName.value = '';
    } else {
      expandedTodoName.value = name;
      _fetchAndCacheTodoDetails(name);
    }
  }

  // ── Refresh ──────────────────────────────────────────────────────────────

  /// Re-fetches a single ToDo and patches both the detail cache and the
  /// matching summary row — used after closing/reopening and after
  /// returning from the form, so the list reflects changes without a full
  /// reload.
  ///
  /// Unlike [_fetchAndCacheTodoDetails] this always re-fetches (bypassing
  /// its cache-hit guard) and only overwrites the cache once the new data
  /// has arrived, so a transient failure leaves the previously-shown
  /// detail intact instead of blanking it.
  /// A 404 means the document was deleted — the row is evicted instead.
  Future<void> refreshTodoDetail(String name) async {
    if (name.isEmpty) return;
    try {
      final response = await _provider.getTodo(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final updated = ToDo.fromJson(response.data['data']);
        _detailedTodosCache[name] = updated;
        final idx = todos.indexWhere((t) => t.name == name);
        if (idx != -1) {
          todos[idx] = updated;
          _applyLocalSearch();
        }
      } else if (response.statusCode == 404) {
        _evictTodo(name);
      } else {
        AppNotification.error('Failed to refresh ToDo');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _evictTodo(name);
      } else {
        AppNotification.error(e.toString());
      }
    } catch (e) {
      AppNotification.error(e.toString());
    }
  }

  /// Removes a ToDo the server no longer has (deleted on the form screen)
  /// from the list, the detail cache, and the expansion state — silently,
  /// since a 404 after a delete is expected, not an error.
  void _evictTodo(String name) {
    _detailedTodosCache.remove(name);
    todos.removeWhere((t) => t.name == name);
    _applyLocalSearch();
    if (expandedTodoName.value == name) expandedTodoName.value = '';
  }

  // ── Close quick action ──────────────────────────────────────────────────

  Future<void> closeTodo(String name, {String? modified}) async {
    if (closingTodoName.value != null) return;
    final confirmed = await GlobalDialog.confirm(
      title: 'Close ToDo?',
      message: 'Mark this task as closed.',
      confirmText: 'Close',
      icon: Icons.check_circle_outline,
    );
    if (confirmed != true) return;
    await setTodoStatus(name, close: true, modified: modified);
  }

  /// Core close/reopen network + cache-update logic, split out from
  /// [closeTodo] so it can be exercised without the confirmation dialog
  /// (the dialog requires a live widget tree).
  Future<void> setTodoStatus(
    String name, {
    required bool close,
    String? modified,
  }) async {
    closingTodoName.value = name;
    try {
      final response = close
          ? await _provider.closeTodo(name, modified: modified)
          : await _provider.reopenTodo(name, modified: modified);
      if (response.statusCode == 200) {
        AppNotification.success(close ? 'ToDo Closed' : 'ToDo Reopened');
        await refreshTodoDetail(name);
      } else {
        AppNotification.error(
            close ? 'Failed to close ToDo' : 'Failed to reopen ToDo');
      }
    } catch (e) {
      AppNotification.error(e.toString());
    } finally {
      closingTodoName.value = null;
    }
  }
}
