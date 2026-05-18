import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/todo/todo_controller.dart';
import 'package:multimax/app/modules/todo/widgets/todo_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';

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
    final af = ctrl.activeFilters;

    // Status
    if (af.containsKey('status') &&
        (af['status'] as String?)?.isNotEmpty == true) {
      chips.add(FilterChipWidget(
        icon: Icons.label_outline,
        label: 'Status: ${af['status']}',
        onDeleted: () => ctrl.removeFilter('status'),
      ));
    }

    // Priority
    if (af.containsKey('priority') &&
        (af['priority'] as String?)?.isNotEmpty == true) {
      chips.add(FilterChipWidget(
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
      chips.add(FilterChipWidget(
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
      automaticallyImplyLeading: false,

      // Global ERPNext search
      searchDoctype: 'ToDo',
      searchRoute: AppRoutes.TODO_FORM,

      // Search wiring
      searchQuery: ctrl.searchQuery,
      onSearchChanged: ctrl.onSearchChanged,
      onSearchClear: () {
        ctrl.searchQuery.value = '';
        ctrl.onSearchChanged('');
      },

      // Filter badge + sheet
      activeFilters: ctrl.activeFilters,
      onFilterTap: _openFilterSheet,

      // Active filter chips row
      filterChipsBuilder: (ctx) => _buildFilterChips(ctx, ctrl),
      onClearAllFilters: ctrl.clearFilters,
    );
  }
}

