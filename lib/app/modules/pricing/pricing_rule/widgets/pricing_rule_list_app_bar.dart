import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/header_choice_row.dart';
import 'package:multimax/app/modules/global_widgets/option_picker_sheet.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/pricing_rule_controller.dart';

class PricingRuleListAppBar extends StatelessWidget {
  const PricingRuleListAppBar({super.key});

  // The side picker is the screen's whole filter sheet; its chip re-opens it.
  void _pickSide(BuildContext context, PricingRuleController c) =>
      showOptionPickerSheet(
        context,
        title: 'Side',
        options: const ['All sides', 'Selling', 'Buying'],
        paintOptionsOnMaterial: true,
        selected: c.side.isEmpty ? 'All sides' : c.side,
        onSelected: (v) => c.setSide(v == 'All sides' ? '' : v),
      );

  @override
  Widget build(BuildContext context) {
    final c = Get.find<PricingRuleController>();
    return DocTypeListHeader(
      title: 'Pricing Rule',
      automaticallyImplyLeading: false,
      searchDoctype: 'Pricing Rule',
      searchRoute: AppRoutes.PRICING_RULE_FORM,
      searchQuery: c.searchQuery,
      onSearchChanged: c.onSearchChanged,
      onSearchClear: () => c.onSearchChanged(''),
      activeFilters: c.activeFilters,
      onFilterTap: () => _pickSide(context, c),
      filterChipsBuilder: (_) => [
        if (c.side.isNotEmpty)
          FilterChipWidget(
            icon: Icons.storefront_outlined,
            label: 'Side: ${c.side}',
            onDeleted: () => c.setSide(''),
            onTap: () => _pickSide(context, c),
          ),
      ],
      onClearAllFilters: c.clearFilters,
      measuredBottomBuilder: (_) {
        final busy = _busy(c);
        return HeaderChoiceRow(
          options: [
            _choice(c, '', 'All'),
            for (final status in PricingRuleController.statuses)
              _choice(c, status, status),
          ],
          solidSelection: true,
          busy: busy,
          busyLabel: busy && c.rules.isNotEmpty
              ? 'Updating pricing rules'
              : null,
        );
      },
    );
  }

  bool _busy(PricingRuleController c) =>
      c.isLoading.value || c.isFetchingMore.value;

  HeaderChoiceOption _choice(
    PricingRuleController c,
    String value,
    String label,
  ) {
    final count = c.statusCounts[value];
    final caption = count == null ? label : '$label ($count)';
    return HeaderChoiceOption(
      id: 'rule-status:$value',
      groupId: 'rule-status',
      label: caption,
      semanticLabel: caption,
      dotColor: value.isEmpty ? null : StatusPill.dotColorForStatus(value),
      selected: c.status.value == value,
      onPressed: () {
        if (!_busy(c)) c.selectStatus(value);
      },
    );
  }
}
