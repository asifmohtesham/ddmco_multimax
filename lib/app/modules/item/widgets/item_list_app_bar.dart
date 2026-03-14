import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/item/item_controller.dart';
import 'package:multimax/app/modules/item/widgets/item_filter_bottom_sheet.dart';

/// DocTypeListAppBar for the **Item** DocType.
///
/// Wraps [DocTypeListHeader] and pre-wires all reactive state from
/// [ItemController] so that [ItemScreen] only needs to drop this widget
/// into its [CustomScrollView] slivers list:
///
/// ```dart
/// CustomScrollView(
///   slivers: [
///     const ItemListAppBar(),
///     // … list content slivers …
///   ],
/// )
/// ```
///
/// ### What this widget owns
/// | Concern | Wired to |
/// |---|---|
/// | Collapsing large title | `'Item Master'` (static) |
/// | Global ERPNext search | `Item` doctype → [AppRoutes.ITEM_FORM] |
/// | Grid / list toggle action | `controller.isGridView` / `controller.toggleLayout` |
/// | Local SearchBar | `controller.searchQuery` + `controller.onSearchChanged` |
/// | Filter badge | `controller.filterCount` |
/// | Filter sheet | [ItemFilterBottomSheet] via `Get.bottomSheet` |
/// | Active filter chips | Built from `controller.activeFilters` |
/// | Clear-all chips button | `controller.clearFilters` |
class ItemListAppBar extends StatelessWidget {
  const ItemListAppBar({super.key});

  // ── helpers ──────────────────────────────────────────────────────────────

  static void _openFilterSheet() {
    Get.bottomSheet(
      const ItemFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  // ── filter chips ─────────────────────────────────────────────────────────

  List<Widget> _buildFilterChips(
      BuildContext context, ItemController controller) {
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

    // "Show Images Only" pseudo-filter
    if (controller.showImagesOnly.value) {
      chips.add(chip(
        icon: Icons.image_outlined,
        label: 'Images Only',
        onDeleted: () {
          controller.showImagesOnly.value = false;
          controller.fetchItems(clear: true);
        },
      ));
    }

    // One chip per active FilterRow
    for (final filter in controller.activeFilters) {
      if (filter.value.isEmpty) continue;
      chips.add(chip(
        icon: Icons.filter_alt_outlined,
        label: '${filter.label}: ${filter.value}',
        onDeleted: () {
          controller.activeFilters.remove(filter);
          controller.fetchItems(clear: true);
        },
      ));
    }

    return chips;
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ItemController controller = Get.find();

    return DocTypeListHeader(
      title: 'Item Master',

      // Global ERPNext API search ──────────────────────────────────────────
      searchDoctype: 'Item',
      searchRoute: AppRoutes.ITEM_FORM,

      // Grid / list toggle ─────────────────────────────────────────────────
      extraActions: [
        Obx(() => IconButton(
              tooltip: controller.isGridView.value ? 'List view' : 'Grid view',
              icon: Icon(
                controller.isGridView.value
                    ? Icons.view_list_outlined
                    : Icons.grid_view_outlined,
              ),
              onPressed: controller.toggleLayout,
            )),
      ],

      // Local SearchBar ────────────────────────────────────────────────────
      searchQuery: controller.searchQuery,
      searchHint: 'Search Items (Name, Code, Desc...)',
      onSearchChanged: controller.onSearchChanged,
      onSearchClear: () {
        controller.searchQuery.value = '';
        controller.fetchItems(clear: true);
      },

      // Filter button (badge driven by filterCount) ────────────────────────
      // DocTypeListHeader expects RxMap for activeFilters; we proxy the
      // RxList<FilterRow> count through a dedicated RxMap shim so the badge
      // remains reactive without touching the controller's data model.
      activeFilters: _ActiveFiltersShim(controller),
      onFilterTap: _openFilterSheet,

      // Active filter chips ────────────────────────────────────────────────
      filterChipsBuilder: (ctx) => _buildFilterChips(ctx, controller),
      onClearAllFilters: controller.clearFilters,
    );
  }
}

// ---------------------------------------------------------------------------
// _ActiveFiltersShim
// ---------------------------------------------------------------------------
// [DocTypeListHeader] reads [activeFilters.length] and [activeFilters.isNotEmpty]
// via an [RxMap<String, dynamic>].  ItemController uses an [RxList<FilterRow>]
// and a scalar [filterCount] getter that also counts the "images only" pseudo-
// filter.  This thin shim bridges the two without altering either class.

class _ActiveFiltersShim extends RxMap<String, dynamic> {
  final ItemController _ctrl;
  _ActiveFiltersShim(this._ctrl) : super({});

  @override
  int get length => _ctrl.filterCount;

  @override
  bool get isEmpty => _ctrl.filterCount == 0;

  @override
  bool get isNotEmpty => _ctrl.filterCount > 0;
}
