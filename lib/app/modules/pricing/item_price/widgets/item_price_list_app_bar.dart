import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/filter_focus.dart';
import 'package:multimax/app/modules/global_widgets/header_choice_row.dart';
import 'package:multimax/app/modules/pricing/item_price/item_price_controller.dart';
import 'package:multimax/app/modules/pricing/item_price/widgets/item_price_filter_sheet.dart';

class ItemPriceListAppBar extends StatelessWidget {
  const ItemPriceListAppBar({super.key, this.sliverKey});

  final GlobalKey? sliverKey;

  /// [focusKey] opens the sheet on that filter, ready to edit.
  void _openFilters({String? focusKey}) => Get.bottomSheet(
    FilterFocusScope.wrap(const ItemPriceFilterSheet(), focusKey: focusKey),
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
  );

  List<Widget> _chips(ItemPriceController c) {
    final af = c.activeFilters;
    return [
      if (af['validity'] != null)
        FilterChipWidget(
          icon: Icons.event_outlined,
          label: 'Validity: ${af['validity']}',
          onDeleted: () => c.removeFilter('validity'),
          onTap: () => _openFilters(focusKey: 'validity'),
        ),
      if (af['scoped'] == true)
        FilterChipWidget(
          icon: Icons.person_outline,
          label: 'Has customer or supplier: On',
          onDeleted: () => c.removeFilter('scoped'),
          onTap: () => _openFilters(focusKey: 'scoped'),
        ),
      if (af['batch'] == true)
        FilterChipWidget(
          icon: Icons.tag,
          label: 'Has batch: On',
          onDeleted: () => c.removeFilter('batch'),
          onTap: () => _openFilters(focusKey: 'batch'),
        ),
      if (af['zero'] == true)
        FilterChipWidget(
          icon: Icons.exposure_zero,
          label: 'Zero rate: On',
          onDeleted: () => c.removeFilter('zero'),
          onTap: () => _openFilters(focusKey: 'zero'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<ItemPriceController>();
    return DocTypeListHeader(
      sliverKey: sliverKey,
      title: 'Item Price',
      automaticallyImplyLeading: false,
      searchDoctype: 'Item Price',
      searchRoute: AppRoutes.ITEM_PRICE_FORM,
      searchQuery: c.searchQuery,
      onSearchChanged: c.onSearchChanged,
      onSearchClear: () => c.onSearchChanged(''),
      activeFilters: c.activeFilters,
      onFilterTap: () => _openFilters(),
      filterChipsBuilder: (_) => _chips(c),
      onClearAllFilters: c.clearFilters,
      measuredBottomBuilder: (_) => HeaderChoiceRow(
        options: [
          _choice(c, '', 'All'),
          for (final list in c.priceLists) _choice(c, list.name, list.name),
        ],
        solidSelection: true,
        busy: _busy(c),
      ),
    );
  }

  bool _busy(ItemPriceController c) =>
      c.isPriceListLoading || c.isLoading.value || c.isFetchingMore.value;

  HeaderChoiceOption _choice(
    ItemPriceController c,
    String value,
    String label,
  ) {
    final count = c.listCounts[value];
    final caption = count == null ? label : '$label ($count)';
    return HeaderChoiceOption(
      id: 'price-list:$value',
      groupId: 'price-list',
      label: caption,
      semanticLabel: caption,
      selected: c.selectedPriceList.value == value,
      onPressed: () {
        if (!_busy(c)) c.selectPriceList(value);
      },
    );
  }
}
