import 'package:get/get.dart';
import 'package:multimax/app/data/models/todo_model.dart';
import 'package:multimax/app/data/providers/todo_provider.dart';
import 'package:multimax/app/core/utils/app_notification.dart';

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
}
