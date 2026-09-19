import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/selectable_filter_chip.dart';
import 'package:multimax/app/modules/pricing/item_price/item_price_controller.dart';
import 'package:multimax/app/modules/pricing/item_price/widgets/item_price_filter_sheet.dart';

class ItemPriceListAppBar extends StatelessWidget {
  const ItemPriceListAppBar({super.key});

  void _openFilters() => Get.bottomSheet(
        const ItemPriceFilterSheet(),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
      );

  List<Widget> _chips(ItemPriceController c) {
    final af = c.activeFilters;
    return [
      if (af['validity'] != null)
        FilterChipWidget(
          icon: Icons.event_outlined,
          label: '${af['validity']}',
          onDeleted: () => c.removeFilter('validity'),
        ),
      if (af['scoped'] == true)
        FilterChipWidget(
          icon: Icons.person_outline,
          label: 'Has customer or supplier',
          onDeleted: () => c.removeFilter('scoped'),
        ),
      if (af['batch'] == true)
        FilterChipWidget(
          icon: Icons.tag,
          label: 'Has batch',
          onDeleted: () => c.removeFilter('batch'),
        ),
      if (af['zero'] == true)
        FilterChipWidget(
          icon: Icons.exposure_zero,
          label: 'Zero rate',
          onDeleted: () => c.removeFilter('zero'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<ItemPriceController>();
    return DocTypeListHeader(
      title: 'Item Price',
      automaticallyImplyLeading: false,
      searchDoctype: 'Item Price',
      searchRoute: AppRoutes.ITEM_PRICE_FORM,
      searchQuery: c.searchQuery,
      onSearchChanged: c.onSearchChanged,
      onSearchClear: () => c.onSearchChanged(''),
      activeFilters: c.activeFilters,
      onFilterTap: _openFilters,
      filterChipsBuilder: (_) => _chips(c),
      onClearAllFilters: c.clearFilters,
      // Own Obx: the sliver header does not repaint on content-only changes.
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: SizedBox(
          height: 52,
          child: Obx(
            () => ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              children: [
                _chip(c, '', 'All'),
                for (final l in c.priceLists) _chip(c, l.name, l.name),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(ItemPriceController c, String value, String label) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: SelectableFilterChip(
          label: label,
          count: c.listCounts[value],
          selected: c.selectedPriceList.value == value,
          onSelected: (_) => c.selectPriceList(value),
        ),
      );
}
