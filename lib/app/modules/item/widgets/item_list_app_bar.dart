import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/item/item_controller.dart';
import 'package:multimax/app/modules/item/widgets/item_filter_bottom_sheet.dart';

class ItemListAppBar extends StatelessWidget {
  const ItemListAppBar({super.key});

  // Fix #7: ensure reference data is loaded before opening the sheet.
  static void _openFilterSheet(ItemController controller) {
    controller.ensureReferenceDataLoaded().then((_) {
      Get.bottomSheet(
        const ItemFilterBottomSheet(),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
      );
    });
  }

  List<Widget> _buildFilterChips(
      BuildContext context, ItemController controller) {
    final chips = <Widget>[];
    final cs = Theme.of(context).colorScheme;

    Widget chip({
      required IconData icon,
      required String label,
      required VoidCallback onDeleted,
    }) {
      return Chip(
        avatar: Icon(icon, size: 16, color: cs.onSecondaryContainer),
        label: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
        ),
        backgroundColor: cs.secondaryContainer,
        deleteIconColor: cs.onSecondaryContainer,
        onDeleted: onDeleted,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      );
    }

    // Fix #13: showImagesOnly is NOT added to the filter badge chips.
    // It has its own AppBar icon toggle (see extraActions below).

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

  /// Returns a lightweight [RxMap] whose [length], [isEmpty], and [isNotEmpty]
  /// reflect [controller.filterCount]. [DocTypeListHeader] only reads these
  /// three members, so this is the full contract with the shared widget.
  RxMap<String, dynamic> _buildActiveFiltersMap(ItemController controller) {
    // Construct a fresh RxMap populated with one sentinel entry per active
    // filter so that .length == filterCount and .isEmpty == (filterCount == 0).
    final map = <String, dynamic>{};
    for (var i = 0; i < controller.filterCount; i++) {
      map['_$i'] = true;
    }
    return RxMap(map);
  }

  @override
  Widget build(BuildContext context) {
    final ItemController controller = Get.find();

    return DocTypeListHeader(
      title: 'Item',
      automaticallyImplyLeading: false,
      searchDoctype: 'Item',
      searchRoute: AppRoutes.ITEM_FORM,

      extraActions: [
        // Fix #13: standalone image-toggle icon button in AppBar.
        // Clearly separated from the filter badge so users always know
        // the current state without opening the filter sheet.
        Obx(() => IconButton(
              tooltip: controller.showImagesOnly.value
                  ? 'Showing items with images only (tap to show all)'
                  : 'Showing all items (tap to show images only)',
              icon: Icon(
                controller.showImagesOnly.value
                    ? Icons.image
                    : Icons.image_outlined,
              ),
              color: controller.showImagesOnly.value
                  ? Theme.of(context).colorScheme.primary
                  : null,
              onPressed: () =>
                  controller.setImagesOnly(!controller.showImagesOnly.value),
            )),
        Obx(() => IconButton(
              tooltip:
                  controller.isGridView.value ? 'List view' : 'Grid view',
              icon: Icon(
                controller.isGridView.value
                    ? Icons.view_list_outlined
                    : Icons.grid_view_outlined,
              ),
              onPressed: controller.toggleLayout,
            )),
      ],

      searchQuery: controller.searchQuery,
      onSearchChanged: controller.onSearchChanged,
      onSearchClear: () {
        controller.searchQuery.value = '';
        controller.fetchItems(clear: true);
      },

      activeFilters: _buildActiveFiltersMap(controller),
      onFilterTap: () => _openFilterSheet(controller),

      filterChipsBuilder: (ctx) => _buildFilterChips(ctx, controller),
      onClearAllFilters: controller.clearFilters,
    );
  }
}
