import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_filter_sheet.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_group_card.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_totals_footer.dart';

class BomStockCustomerCodeScreen
    extends GetView<BomStockCustomerCodeController> {
  const BomStockCustomerCodeScreen({super.key});

  List<Widget> _buildFilterChips(BuildContext context) {
    final chips = <Widget>[];
    controller.activeFilters.forEach((key, label) {
      chips.add(FilterChipWidget(
        icon: Icons.filter_alt_outlined,
        label: label,
        onDeleted: () => controller.clearFilter(key),
      ));
    });
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppShellScaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: Obx(() {
        final rows = controller.filteredRows;
        return Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.runReport,
                color: cs.primary,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    DocTypeListHeader(
                      title: 'BOM Stock with Customer Code',
                      automaticallyImplyLeading: false,
                      activeFilters: controller.activeFilters
                          .map((k, v) => MapEntry(k, v as dynamic))
                          .obs,
                      onFilterTap: () =>
                          showBomStockFilterSheet(context, controller),
                      filterChipsBuilder: _buildFilterChips,
                      onClearAllFilters: controller.clearFilters,
                      extraActionsKey: controller.isRunning.value,
                      extraActions: [
                        AsyncIconButton(
                          busy: controller.isRunning,
                          onPressed: controller.runReport,
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Run report',
                        ),
                      ],
                    ),

                    // ── POS missing-codes banner ──────────────────────────
                    if (controller.posMissingCodes.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${controller.posMissingCodes.length} Customer '
                            'Code(s) from the selected POS Upload were not '
                            'found: ${controller.posMissingCodes.join(', ')}',
                            style: TextStyle(color: cs.onErrorContainer, fontSize: 12),
                          ),
                        ),
                      ),

                    // ── Segmented row filter ──────────────────────────────
                    if (!controller.isRunning.value &&
                        controller.reportRows.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: _SegmentedRowFilter(
                            value: controller.rowFilter.value,
                            onChanged: controller.setRowFilter,
                          ),
                        ),
                      ),

                    // ── Body ──────────────────────────────────────────────
                    if (controller.isRunning.value)
                      const SliverToBoxAdapter(child: DocCardSkeletonList())
                    else if (controller.reportRows.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inventory_2_outlined,
                                    size: 64, color: cs.outlineVariant),
                                const SizedBox(height: 16),
                                Text(
                                  'Set filters and run the report',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                                const SizedBox(height: 24),
                                FilledButton.tonalIcon(
                                  onPressed: () => showBomStockFilterSheet(
                                      context, controller),
                                  icon: const Icon(Icons.filter_alt_outlined),
                                  label: const Text('Run Report'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else if (rows.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'No items match this filter',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ),
                        ),
                      )
                    else if (controller.posUpload.value != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate(
                            controller.groupedRows
                                .map((g) => BomStockGroupCard(
                                      group: g,
                                      expanded: controller.isGroupExpanded(g.code),
                                      onToggle: () => controller.toggleGroup(g.code),
                                    ))
                                .toList(),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: BomStockTile(row: rows[index]),
                            ),
                            childCount: rows.length,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (!controller.isRunning.value &&
                controller.reportRows.isNotEmpty)
              BomStockTotalsFooter(
                totals: BomStockCustomerCodeController.sumTotals(rows),
                hasDemand: controller.posUpload.value != null,
              ),
          ],
        );
      }),
    );
  }
}

/// All | In Stock | Shortage — client-side segmented filter over the rows.
class _SegmentedRowFilter extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _SegmentedRowFilter({required this.value, required this.onChanged});

  static const _segments = [
    ('ALL', 'All'),
    ('instock', 'In Stock'),
    ('shortage', 'Shortage'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          for (final (val, label) in _segments)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(val),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: value == val ? cs.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: value == val ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
