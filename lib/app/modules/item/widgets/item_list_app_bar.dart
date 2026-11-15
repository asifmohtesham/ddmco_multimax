import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/filter_focus.dart';
import 'package:multimax/app/modules/item/item_controller.dart';
import 'package:multimax/app/modules/item/widgets/item_filter_bottom_sheet.dart';
import 'package:multimax/app/shared/image_scan/image_scan_result.dart';

class ItemListAppBar extends StatelessWidget {
  const ItemListAppBar({super.key});

  // Open instantly; warm the reference data in the background. The sheet's
  // main content needs no reference data — it's only consumed by the
  // Link/Attribute selectors, which show per-field spinners until it arrives.
  // Awaiting here would make the tap feel unresponsive (no feedback, then a
  // late open); progressive in-sheet loading is the better UX.
  //
  // [focusKey] opens the sheet on that filter, ready to edit.
  static void _openFilterSheet(ItemController controller, {String? focusKey}) {
    controller.ensureReferenceDataLoaded();
    Get.bottomSheet(
      FilterFocusScope.wrap(const ItemFilterBottomSheet(), focusKey: focusKey),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  List<Widget> _buildFilterChips(
      BuildContext context, ItemController controller) {
    final chips = <Widget>[];

    // showImagesOnly is NOT added to the filter badge chips;
    // it has its own AppBar icon toggle (see extraActions below).

    for (final (index, filter) in controller.activeFilters.indexed) {
      if (filter.value.isEmpty) continue;
      chips.add(FilterChipWidget(
        icon: Icons.filter_alt_outlined,
        label: '${filter.label}: ${filter.value}',
        onDeleted: () {
          controller.activeFilters.remove(filter);
          controller.fetchItems(clear: true);
        },
        // The sheet's rows start as copies of activeFilters, in order.
        onTap: () => _openFilterSheet(controller,
            focusKey: ItemFilterBottomSheet.rowFocusKey(index)),
      ));
    }

    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final ItemController controller = Get.find();

    return DocTypeListHeader(
      title: 'Item',
      automaticallyImplyLeading: false,
      searchDoctype: 'Item',
      searchRoute: AppRoutes.ITEM_FORM,
      onImageScanResult: (ImageScanResult result) {
        Get.toNamed(
          AppRoutes.ITEM_FORM,
          arguments: {
            'itemCode': result.itemCode,
            'batchNo': result.batchNo,
          },
        );
      },

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

      activeFilters: controller.activeFiltersMap,
      onFilterTap: () => _openFilterSheet(controller),

      filterChipsBuilder: (ctx) => _buildFilterChips(ctx, controller),
      onClearAllFilters: controller.clearFilters,
    );
  }
}
