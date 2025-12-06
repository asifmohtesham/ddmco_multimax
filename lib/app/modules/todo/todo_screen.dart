import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/todo/todo_controller.dart';
import 'package:intl/intl.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/status_pill.dart';

class ToDoScreen extends StatefulWidget {
  const ToDoScreen({super.key});

  @override
  State<ToDoScreen> createState() => _ToDoScreenState();
}

class _ToDoScreenState extends State<ToDoScreen> {
  final ToDoController controller = Get.find();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isBottom && controller.hasMore.value && !controller.isFetchingMore.value) {
      controller.fetchTodos(isLoadMore: true);
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  void _showFilterDialog(BuildContext context) {
    final nameController = TextEditingController(text: controller.activeFilters['name']);
    String? selectedStatus = controller.activeFilters['status'];

    Get.dialog(
      AlertDialog(
        title: const Text('Filter ToDos'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name/ID'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedStatus,
              decoration: const InputDecoration(labelText: 'Status'),
              items: ['Open', 'Closed', 'Cancelled']
                  .map((status) => DropdownMenuItem(value: status, child: Text(status)))
                  .toList(),
              onChanged: (value) => selectedStatus = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.clearFilters();
              Get.back();
            },
            child: const Text('Clear'),
          ),
          ElevatedButton(
            onPressed: () {
              final filters = {
                if (nameController.text.isNotEmpty) 'name': nameController.text,
                if (selectedStatus != null) 'status': selectedStatus,
              };
              controller.applyFilters(filters);
              Get.back();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ToDos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: () => _showFilterDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              onChanged: controller.onSearchChanged,
              decoration: const InputDecoration(
                labelText: 'Search ToDos',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value && controller.todos.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (controller.filteredTodos.isEmpty) {
                return const Center(child: Text('No ToDos found.'));
              }

              return Scrollbar(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: controller.filteredTodos.length + (controller.hasMore.value ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= controller.filteredTodos.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final todo = controller.filteredTodos[index];
                    return ToDoCard(todo: todo);
                  },
                ),
              );
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Get.toNamed(AppRoutes.TODO_FORM, arguments: {'name': '', 'mode': 'new'});
          Get.snackbar('TODO', 'Create new ToDo');
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ToDoCard extends StatelessWidget {
  final dynamic todo;
  final ToDoController controller = Get.find();

  ToDoCard({super.key, required this.todo});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      clipBehavior: Clip.antiAlias,
      child: Obx(() {
        final isCurrentlyExpanded = controller.expandedTodoName.value == todo.name;
        return Column(
          children: [
            ListTile(
              title: todo.description.isNotEmpty ? Html(data: todo.description.split('\n')[0]) : Text(todo.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Priority: ${todo.priority}'),
                  const SizedBox(height: 4),
                  StatusPill(status: todo.status),
                ],
              ),
              trailing: AnimatedRotation(
                turns: isCurrentlyExpanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: const Icon(Icons.expand_more),
              ),
              onTap: () => controller.toggleExpand(todo.name),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Container(
                child: !isCurrentlyExpanded
                    ? const SizedBox.shrink()
                    : Obx(() {
                        final detailed = controller.detailedTodo;
                        if (controller.isLoadingDetails.value && detailed?.name != todo.name) {
                          return const LinearProgressIndicator();
                        }

                        if (detailed != null && detailed.name == todo.name) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(height: 1),
                                Padding(
                                  padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                                  child: Text('Modified: ${detailed.modified}'),
                                ),
                                if (detailed.description.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: Html(data: 'Description: ${detailed.description}'),
                                  ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (detailed.status == 'Open') ...[
                                      TextButton(
                                        onPressed: () => Get.snackbar('TODO', 'Close ToDo'),
                                        child: const Text('Close'),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed: () => Get.snackbar('TODO', 'Navigate to form for editing'),
                                        child: const Text('Edit'),
                                      ),
                                    ] else ...[
                                      ElevatedButton(
                                        onPressed: () => Get.snackbar('TODO', 'Navigate to form view in read-only mode'),
                                        child: const Text('View'),
                                      ),
                                    ]
                                  ],
                                ),
                              ],
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      }),
              ),
            ),
          ],
        );
      }),
    );
  }
}
