import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/todo/todo_controller.dart';
import 'package:multimax/app/modules/todo/widgets/todo_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';

/// DocTypeListAppBar for the **ToDo** DocType.
///
/// Drop into [ToDoScreen]'s [CustomScrollView] slivers list:
/// ```dart
/// CustomScrollView(
///   slivers: [
///     const ToDoListAppBar(),
///     // … list content slivers …
///   ],
/// )
/// ```
class ToDoListAppBar extends StatelessWidget {
  const ToDoListAppBar({super.key});

  static void _openFilterSheet() {
    Get.bottomSheet(
      const ToDoFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  List<Widget> _buildFilterChips(
      BuildContext context, ToDoController ctrl) {
    final chips = <Widget>[];
    final colorScheme = Theme.of(context).colorScheme;
    final af = ctrl.activeFilters;

    Widget chip({
      required IconData icon,
      required String label,
      required VoidCallback onDeleted,
    }) {
      return Chip(
        avatar: Icon(icon, size: 16, color: colorScheme.onSecondaryContainer),
        label: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
        ),
        backgroundColor: colorScheme.secondaryContainer,
        deleteIconColor: colorScheme.onSecondaryContainer,
        onDeleted: onDeleted,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      );
    }

    // Status
    if (af.containsKey('status') &&
        (af['status'] as String?)?.isNotEmpty == true) {
      chips.add(chip(
        icon: Icons.label_outline,
        label: 'Status: ${af['status']}',
        onDeleted: () => ctrl.removeFilter('status'),
      ));
    }

    // Priority
    if (af.containsKey('priority') &&
        (af['priority'] as String?)?.isNotEmpty == true) {
      chips.add(chip(
        icon: Icons.flag_outlined,
        label: 'Priority: ${af['priority']}',
        onDeleted: () => ctrl.removeFilter('priority'),
      ));
    }

    // Due Date Range
    if (af.containsKey('date')) {
      final val = af['date'];
      String display = 'Date Range';
      if (val is List &&
          val.length == 2 &&
          val[1] is List &&
          (val[1] as List).length == 2) {
        display = '${(val[1] as List)[0]} – ${(val[1] as List)[1]}';
      }
      chips.add(chip(
        icon: Icons.calendar_today_outlined,
        label: display,
        onDeleted: () => ctrl.removeFilter('date'),
      ));
    }

    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final ToDoController ctrl = Get.find();

    return DocTypeListHeader(
      title: 'ToDos',

      // Global ERPNext search
      searchDoctype: 'ToDo',
      searchRoute: AppRoutes.TODO_FORM,

      // Local SearchBar
      searchQuery: ctrl.searchQuery,
      searchHint: 'Search description, priority, status…',
      onSearchChanged: ctrl.onSearchChanged,
      onSearchClear: () {
        ctrl.searchQuery.value = '';
        ctrl.onSearchChanged('');
      },

      // Filter badge + sheet
      activeFilters: _ToDoFiltersShim(ctrl),
      onFilterTap: _openFilterSheet,

      // Active filter chips row
      filterChipsBuilder: (ctx) => _buildFilterChips(ctx, ctrl),
      onClearAllFilters: ctrl.clearFilters,
    );
  }
}

// ---------------------------------------------------------------------------
// _ToDoFiltersShim
// ---------------------------------------------------------------------------
// Bridges ToDoController.activeFilters (RxMap<String,dynamic>) to the
// RxMap<String,dynamic> that DocTypeListHeader reads for badge count.

class _ToDoFiltersShim extends RxMap<String, dynamic> {
  final ToDoController _ctrl;
  _ToDoFiltersShim(this._ctrl) : super({});

  @override
  int get length => _ctrl.activeFilters.length;

  @override
  bool get isEmpty => _ctrl.activeFilters.isEmpty;

  @override
  bool get isNotEmpty => _ctrl.activeFilters.isNotEmpty;
}
