import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/todo_model.dart';
import 'package:ddmco_multimax/app/data/providers/todo_provider.dart';

class ToDoController extends GetxController {
  final ToDoProvider _provider = Get.find<ToDoProvider>();

  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;
  var todos = <ToDo>[].obs;
  var filteredTodos = <ToDo>[].obs; // For client-side searching
  final int _limit = 20;
  int _currentPage = 0;

  var expandedTodoName = ''.obs;
  var isLoadingDetails = false.obs;
  final _detailedTodosCache = <String, ToDo>{}.obs;

  final activeFilters = <String, dynamic>{}.obs;
  final searchQuery = ''.obs;

  @override
  void onInit() {
    super.onInit();
    fetchTodos();
  }

  ToDo? get detailedTodo => _detailedTodosCache[expandedTodoName.value];

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchTodos(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    fetchTodos(isLoadMore: false, clear: true);
  }

  void onSearchChanged(String query) {
    searchQuery.value = query;
    _applyLocalSearch();
  }

  void _applyLocalSearch() {
    if (searchQuery.value.isEmpty) {
      filteredTodos.assignAll(todos);
    } else {
      filteredTodos.assignAll(todos.where((todo) =>
          todo.name.toLowerCase().contains(searchQuery.value.toLowerCase()) ||
          todo.description.toLowerCase().contains(searchQuery.value.toLowerCase())));
    }
  }

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
        filters: activeFilters,
      );
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newTodos = data.map((json) => ToDo.fromJson(json)).toList();

        if (newTodos.length < _limit) {
          hasMore.value = false;
        }

        if (isLoadMore) {
          todos.addAll(newTodos);
        } else {
          todos.value = newTodos;
        }
        
        _applyLocalSearch(); // Re-apply search on new data
        _currentPage++;
      } else {
        Get.snackbar('Error', 'Failed to fetch ToDos');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      if (isLoadMore) {
        isFetchingMore.value = false;
      } else {
        isLoading.value = false;
      }
    }
  }

  Future<void> _fetchAndCacheTodoDetails(String name) async {
    if (_detailedTodosCache.containsKey(name)) {
      return;
    }

    isLoadingDetails.value = true;
    try {
      final response = await _provider.getTodo(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final todo = ToDo.fromJson(response.data['data']);
        _detailedTodosCache[name] = todo;
      } else {
        Get.snackbar('Error', 'Failed to fetch ToDo details');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
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
