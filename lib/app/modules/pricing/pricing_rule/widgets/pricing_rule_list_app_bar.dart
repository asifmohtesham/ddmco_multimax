import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/option_picker_sheet.dart';
import 'package:multimax/app/modules/global_widgets/selectable_filter_chip.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/pricing_rule_controller.dart';

class PricingRuleListAppBar extends StatelessWidget {
  const PricingRuleListAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<PricingRuleController>();
    return DocTypeListHeader(
      title: 'Pricing Rule',
      automaticallyImplyLeading: false,
      searchQuery: c.searchQuery,
      onSearchChanged: c.onSearchChanged,
      onSearchClear: () => c.onSearchChanged(''),
      activeFilters: c.activeFilters,
      onFilterTap: () => showOptionPickerSheet(
        context,
        title: 'Side',
        options: const ['All sides', 'Selling', 'Buying'],
        selected: c.side.isEmpty ? 'All sides' : c.side,
        onSelected: (v) => c.setSide(v == 'All sides' ? '' : v),
      ),
      filterChipsBuilder: (_) => [
        if (c.side.isNotEmpty)
          FilterChipWidget(
            icon: Icons.storefront_outlined,
            label: c.side,
            onDeleted: () => c.setSide(''),
          ),
      ],
      onClearAllFilters: c.clearFilters,
      // Own Obx wrapped in a SizedBox: ListView inside PreferredSize has
      // unbounded height otherwise (Tasks 5/6 gotcha).
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
                for (final s in PricingRuleController.statuses) _chip(c, s, s),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(PricingRuleController c, String value, String label) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: SelectableFilterChip(
          label: label,
          count: c.statusCounts[value],
          dotColor: value.isEmpty ? null : StatusPill.dotColorForStatus(value),
          selected: c.status.value == value,
          onSelected: (_) => c.selectStatus(value),
        ),
      );
}
