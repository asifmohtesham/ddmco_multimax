import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/todo/todo_controller.dart';
import 'package:multimax/app/modules/todo/widgets/todo_list_app_bar.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/core/utils/app_notification.dart';

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
    if (controller.searchQuery.value.isEmpty &&
        _isBottom &&
        controller.hasMore.value &&
        !controller.isFetchingMore.value) {
      controller.fetchTodos(isLoadMore: true);
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    return _scrollController.offset >=
        (_scrollController.position.maxScrollExtent * 0.9);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          await controller.fetchTodos(clear: true);
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Header: AppBar + SearchBar + filter chips ───────────────────
            const ToDoListAppBar(),

            // ── List content ────────────────────────────────────────
            Obx(() {
              if (controller.isLoading.value &&
                  controller.todos.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (controller.filteredTodos.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 64, color: colorScheme.outlineVariant),
                          const SizedBox(height: 16),
                          Text(
                            'No ToDos Found',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Pull to refresh or create a new one.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.tonalIcon(
                            onPressed: () =>
                                controller.fetchTodos(clear: true),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reload'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final bool showLoader = controller.searchQuery.value.isEmpty &&
                  controller.hasMore.value;

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= controller.filteredTodos.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final todo = controller.filteredTodos[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12.0, vertical: 4.0),
                      child: ToDoCard(todo: todo),
                    );
                  },
                  childCount:
                      controller.filteredTodos.length + (showLoader ? 1 : 0),
                ),
              );
            }),

            // Bottom padding for FAB
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Get.toNamed(
          AppRoutes.TODO_FORM,
          arguments: {'name': '', 'mode': 'new'},
        ),
        icon: const Icon(Icons.add),
        label: const Text('Create'),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ToDoCard
// ---------------------------------------------------------------------------

class ToDoCard extends StatelessWidget {
  final dynamic todo;
  final ToDoController controller = Get.find();

  ToDoCard({super.key, required this.todo});

  // Priority colour
  static Color _priorityColor(String priority, ColorScheme cs) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return Colors.red.shade600;
      case 'high':
        return Colors.orange.shade600;
      case 'low':
        return cs.outline;
      default: // medium
        return cs.primary;
    }
  }

  static IconData _priorityIcon(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return Icons.priority_high;
      case 'high':
        return Icons.keyboard_double_arrow_up;
      case 'low':
        return Icons.keyboard_double_arrow_down;
      default:
        return Icons.drag_handle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final priorityColor = _priorityColor(todo.priority, colorScheme);

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Obx(() {
        final isExpanded =
            controller.expandedTodoName.value == todo.name;

        return Column(
          children: [
            // ── Summary row ───────────────────────────────────────────
            InkWell(
              onTap: () => controller.toggleExpand(todo.name),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Priority indicator dot
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0, right: 12.0),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: priorityColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Description first line or name fallback
                          todo.description.isNotEmpty
                              ? Html(
                                  data: todo.description.split('\n')[0],
                                  style: {
                                    'body': Style(
                                      margin: Margins.zero,
                                      padding: HtmlPaddings.zero,
                                      fontSize: FontSize(
                                          theme.textTheme.bodyMedium
                                              ?.fontSize ??
                                              14),
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                  },
                                )
                              : Text(
                                  todo.name,
                                  style:
                                      theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(_priorityIcon(todo.priority),
                                  size: 14, color: priorityColor),
                              const SizedBox(width: 4),
                              Text(
                                todo.priority,
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: priorityColor),
                              ),
                              if (todo.date.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                Icon(Icons.calendar_today_outlined,
                                    size: 13,
                                    color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  todo.date,
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(
                                          color:
                                              colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        StatusPill(status: todo.status),
                        const SizedBox(height: 4),
                        AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          child: Icon(Icons.expand_more,
                              color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Expanded detail ─────────────────────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              child: !isExpanded
                  ? const SizedBox.shrink()
                  : Obx(() {
                      final detailed = controller.detailedTodo;
                      if (controller.isLoadingDetails.value &&
                          detailed?.name != todo.name) {
                        return const LinearProgressIndicator();
                      }
                      if (detailed == null ||
                          detailed.name != todo.name) {
                        return const SizedBox.shrink();
                      }
                      return Container(
                        decoration: BoxDecoration(
                          border: Border(
                              top: BorderSide(
                                  color: colorScheme.outlineVariant
                                      .withValues(alpha: 0.5))),
                          color: colorScheme.surfaceContainerHigh,
                        ),
                        padding: const EdgeInsets.fromLTRB(
                            16.0, 12.0, 16.0, 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (detailed.description.isNotEmpty)
                              Html(
                                data: detailed.description,
                                style: {
                                  'body': Style(
                                    margin: Margins.zero,
                                    padding: HtmlPaddings.zero,
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: FontSize(
                                        theme.textTheme.bodySmall
                                            ?.fontSize ??
                                            12),
                                  ),
                                },
                              ),
                            const SizedBox(height: 4),
                            Text(
                              'Modified: ${detailed.modified}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.outline),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (detailed.status == 'Open') ...[
                                  OutlinedButton(
                                    // TODO: implement close ToDo action
                                    onPressed: () => AppNotification.info(
                                        'Close ToDo coming soon'),
                                    child: const Text('Close'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.tonal(
                                    onPressed: () => Get.toNamed(
                                      AppRoutes.TODO_FORM,
                                      arguments: {
                                        'name': detailed.name,
                                        'mode': 'edit',
                                      },
                                    ),
                                    child: const Text('Edit'),
                                  ),
                                ] else
                                  FilledButton.tonal(
                                    onPressed: () => Get.toNamed(
                                      AppRoutes.TODO_FORM,
                                      arguments: {
                                        'name': detailed.name,
                                        'mode': 'view',
                                      },
                                    ),
                                    child: const Text('View'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
            ),
          ],
        );
      }),
    );
  }
}
