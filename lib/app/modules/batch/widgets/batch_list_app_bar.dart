import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/batch/batch_controller.dart';
import 'package:multimax/app/modules/batch/widgets/batch_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';

/// DocTypeListAppBar for the **Batch** DocType.
///
/// Wraps [DocTypeListHeader] and pre-wires all reactive state from
/// [BatchController] so [BatchScreen] only needs to drop this widget
/// into its [CustomScrollView] slivers list:
///
/// ```dart
/// CustomScrollView(
///   slivers: [
///     const BatchListAppBar(),
///     // … list content slivers …
///   ],
/// )
/// ```
///
/// ### What this widget owns
/// | Concern | Wired to |
/// |---|---|
/// | Collapsing large title | `'Batch'` (static) |
/// | Global ERPNext search | `Batch` doctype → [AppRoutes.BATCH_FORM] |
/// | Search & filter | `controller.searchQuery` + `controller.onSearchChanged` |
/// | Filter badge | `controller.activeFilters.length` |
/// | Filter sheet | [BatchFilterBottomSheet] via `Get.bottomSheet` |
/// | Active filter chips | Built from `controller.activeFilters` |
/// | Clear-all chips button | `controller.clearFilters` |
class BatchListAppBar extends StatelessWidget {
  const BatchListAppBar({super.key});

  // ── filter sheet ──────────────────────────────────────────────────────────

  static void _openFilterSheet() {
    Get.bottomSheet(
      const BatchFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  // ── active filter chips ───────────────────────────────────────────────────

  List<Widget> _buildFilterChips(
      BuildContext context, BatchController ctrl) {
    final chips = <Widget>[];
    final colorScheme = Theme.of(context).colorScheme;

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

    final af = ctrl.activeFilters;

    if (af.containsKey('item') && (af['item'] as String).isNotEmpty) {
      chips.add(chip(
        icon: Icons.inventory_2_outlined,
        label: 'Item: ${af['item']}',
        onDeleted: () => ctrl.removeFilter('item'),
      ));
    }

    if (af.containsKey('name')) {
      final val = af['name'];
      final display = val is List
          ? val.last.toString().replaceAll('%', '')
          : val.toString();
      if (display.isNotEmpty) {
        chips.add(chip(
          icon: Icons.qr_code_outlined,
          label: 'Batch: $display',
          onDeleted: () => ctrl.removeFilter('name'),
        ));
      }
    }

    if (af.containsKey('custom_purchase_order') &&
        (af['custom_purchase_order'] as String).isNotEmpty) {
      chips.add(chip(
        icon: Icons.receipt_long_outlined,
        label: 'PO: ${af['custom_purchase_order']}',
        onDeleted: () => ctrl.removeFilter('custom_purchase_order'),
      ));
    }

    if (af.containsKey('custom_supplier') &&
        (af['custom_supplier'] as String).isNotEmpty) {
      chips.add(chip(
        icon: Icons.local_shipping_outlined,
        label: 'Supplier: ${af['custom_supplier']}',
        onDeleted: () => ctrl.removeFilter('custom_supplier'),
      ));
    }

    if (af.containsKey('disabled')) {
      chips.add(chip(
        icon: Icons.block_outlined,
        label: 'Includes Disabled',
        onDeleted: () => ctrl.removeFilter('disabled'),
      ));
    }

    return chips;
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final BatchController ctrl = Get.find();

    return DocTypeListHeader(
      title: 'Batch',

      // Global ERPNext API search ────────────────────────────────────────────
      searchDoctype: 'Batch',
      searchRoute: AppRoutes.BATCH_FORM,

      // Search & filter wiring ───────────────────────────────────────────────
      searchQuery: ctrl.searchQuery,
      onSearchChanged: ctrl.onSearchChanged,
      onSearchClear: () {
        ctrl.searchQuery.value = '';
        ctrl.fetchBatches(clear: true);
      },

      // Filter (badge + sheet) ───────────────────────────────────────────────
      activeFilters: _ActiveFiltersShim(ctrl),
      onFilterTap: _openFilterSheet,

      // Active filter chips ──────────────────────────────────────────────────
      filterChipsBuilder: (ctx) => _buildFilterChips(ctx, ctrl),
      onClearAllFilters: ctrl.clearFilters,
    );
  }
}

// ---------------------------------------------------------------------------
// _ActiveFiltersShim
// ---------------------------------------------------------------------------
// Bridges BatchController.activeFilters (RxMap<String,dynamic>) to the
// RxMap<String,dynamic> contract expected by DocTypeListHeader.
// We override length / isEmpty / isNotEmpty so the badge count reflects
// the actual number of active filters stored in the controller.

class _ActiveFiltersShim extends RxMap<String, dynamic> {
  final BatchController _ctrl;
  _ActiveFiltersShim(this._ctrl) : super({});

  @override
  int get length => _ctrl.activeFilters.length;

  @override
  bool get isEmpty => _ctrl.activeFilters.isEmpty;

  @override
  bool get isNotEmpty => _ctrl.activeFilters.isNotEmpty;
}
