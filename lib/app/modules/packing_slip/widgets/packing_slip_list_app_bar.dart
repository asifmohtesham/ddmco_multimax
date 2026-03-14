import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/packing_slip/packing_slip_controller.dart';
import 'package:multimax/app/modules/packing_slip/widgets/packing_slip_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';

/// DocTypeListAppBar for the **Packing Slip** DocType.
///
/// Drop into [PackingSlipScreen]'s [CustomScrollView] slivers list:
/// ```dart
/// CustomScrollView(
///   slivers: [
///     const PackingSlipListAppBar(),
///     // … list content slivers …
///   ],
/// )
/// ```
class PackingSlipListAppBar extends StatelessWidget {
  const PackingSlipListAppBar({super.key});

  // ── filter sheet ──────────────────────────────────────────────────────────

  static void _openFilterSheet() {
    Get.bottomSheet(
      const PackingSlipFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  // ── active filter chips ───────────────────────────────────────────────────

  List<Widget> _buildFilterChips(
      BuildContext context, PackingSlipController ctrl) {
    final chips = <Widget>[];
    final colorScheme = Theme.of(context).colorScheme;
    final af = ctrl.activeFilters;

    Widget chip({
      required IconData icon,
      required String label,
      required VoidCallback onDeleted,
    }) {
      return Chip(
        avatar:
            Icon(icon, size: 16, color: colorScheme.onSecondaryContainer),
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

    // Delivery Note
    if (af.containsKey('delivery_note')) {
      final val = af['delivery_note'];
      final display = val is List
          ? val.last.toString().replaceAll('%', '')
          : val.toString();
      if (display.isNotEmpty) {
        chips.add(chip(
          icon: Icons.local_shipping_outlined,
          label: 'DN: $display',
          onDeleted: () => ctrl.removeFilter('delivery_note'),
        ));
      }
    }

    // PO No
    if (af.containsKey('custom_po_no')) {
      final val = af['custom_po_no'];
      final display = val is List
          ? val.last.toString().replaceAll('%', '')
          : val.toString();
      if (display.isNotEmpty) {
        chips.add(chip(
          icon: Icons.receipt_long_outlined,
          label: 'PO: $display',
          onDeleted: () => ctrl.removeFilter('custom_po_no'),
        ));
      }
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

    // Date Range
    if (af.containsKey('creation')) {
      final val = af['creation'];
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
        onDeleted: () => ctrl.removeFilter('creation'),
      ));
    }

    return chips;
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final PackingSlipController ctrl = Get.find();

    return DocTypeListHeader(
      title: 'Packing Slips',

      // Global ERPNext API search
      searchDoctype: 'Packing Slip',
      searchRoute: AppRoutes.PACKING_SLIP_FORM,

      // Local SearchBar
      searchQuery: ctrl.searchQuery,
      searchHint: 'Search slips, DN, PO, customer…',
      onSearchChanged: ctrl.onSearchChanged,
      onSearchClear: () {
        ctrl.searchQuery.value = '';
        ctrl.onSearchChanged('');
      },

      // Filter badge + sheet
      activeFilters: _PackingSlipFiltersShim(ctrl),
      onFilterTap: _openFilterSheet,

      // Active filter chips row
      filterChipsBuilder: (ctx) => _buildFilterChips(ctx, ctrl),
      onClearAllFilters: ctrl.clearFilters,
    );
  }
}

// ---------------------------------------------------------------------------
// _PackingSlipFiltersShim
// ---------------------------------------------------------------------------
// Bridges PackingSlipController.activeFilters (RxMap<String,dynamic>) to the
// RxMap<String,dynamic> that DocTypeListHeader reads .length / isEmpty from
// for the filter badge count.

class _PackingSlipFiltersShim extends RxMap<String, dynamic> {
  final PackingSlipController _ctrl;
  _PackingSlipFiltersShim(this._ctrl) : super({});

  @override
  int get length => _ctrl.activeFilters.length;

  @override
  bool get isEmpty => _ctrl.activeFilters.isEmpty;

  @override
  bool get isNotEmpty => _ctrl.activeFilters.isNotEmpty;
}
