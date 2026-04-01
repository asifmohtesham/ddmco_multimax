import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/batch/batch_controller.dart';
import 'package:multimax/app/modules/batch/widgets/batch_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';

/// DocTypeListAppBar for the **Batch** DocType.
///
/// Passes [BatchController.activeFilters] (which is already
/// [RxMap<String,dynamic>]) directly to [DocTypeListHeader] — no shim
/// required.  This lets the [DocTypeListHeader] [Obx] subscribe to the
/// real reactive stream so badge counts and chip rows update correctly.
class BatchListAppBar extends StatelessWidget {
  const BatchListAppBar({super.key});

  // ── filter sheet ──────────────────────────────────────────────────

  static void _openFilterSheet() {
    Get.bottomSheet(
      const BatchFilterBottomSheet(),
      isScrollControlled: true,
      // backgroundColor defaults to transparent — no need to specify.
    );
  }

  // ── active filter chips ───────────────────────────────────────────

  List<Widget> _buildFilterChips(
      BuildContext context, BatchController ctrl) {
    final chips = <Widget>[];
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    Widget chip({
      required IconData icon,
      required String label,
      required VoidCallback onDeleted,
    }) {
      return Chip(
        avatar: Icon(icon, size: 16, color: colorScheme.onSecondaryContainer),
        label: Text(
          label,
          style: textTheme.labelSmall?.copyWith(
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

    if (af.containsKey('custom_supplier_name') &&
        (af['custom_supplier_name'] as String).isNotEmpty) {
      chips.add(chip(
        icon: Icons.local_shipping_outlined,
        label: 'Supplier: ${af['custom_supplier_name']}',
        onDeleted: () => ctrl.removeFilter('custom_supplier_name'),
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

      // Global ERPNext API search ─────────────────────────────────────
      searchDoctype: 'Batch',
      searchRoute: AppRoutes.BATCH_FORM,

      // Search & filter wiring ────────────────────────────────────
      searchQuery: ctrl.searchQuery,
      onSearchChanged: ctrl.onSearchChanged,
      onSearchClear: () {
        ctrl.searchQuery.value = '';
        ctrl.fetchBatches(clear: true);
      },

      // activeFilters is already RxMap<String,dynamic> — pass directly.
      // No shim needed; Obx in DocTypeListHeader subscribes to the real stream.
      activeFilters: ctrl.activeFilters,
      onFilterTap: _openFilterSheet,

      // Active filter chips ──────────────────────────────────────
      filterChipsBuilder: (ctx) => _buildFilterChips(ctx, ctrl),
      onClearAllFilters: ctrl.clearFilters,
    );
  }
}
