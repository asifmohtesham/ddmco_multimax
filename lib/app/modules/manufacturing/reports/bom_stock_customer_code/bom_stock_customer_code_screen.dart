import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_anchor.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_sheet.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_filter_sheet.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_group_card.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_totals_footer.dart';

class BomStockCustomerCodeScreen
    extends GetView<BomStockCustomerCodeController> {
  const BomStockCustomerCodeScreen({super.key});

  List<Widget> _buildFilterChips(BuildContext context) {
    final chips = <Widget>[];
    controller.activeFilters.forEach((key, label) {
      chips.add(
        FilterChipWidget(
          icon: Icons.filter_alt_outlined,
          label: label,
          onDeleted: () => controller.clearFilter(key),
          onTap: () =>
              showBomStockFilterSheet(context, controller, focusKey: key),
        ),
      );
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
        final fields = controller.fields.state.value;
        final hasDemand = controller.posUpload.value != null;
        final groups = hasDemand
            ? BomStockCustomerCodeController.groupByCustomerCode(rows)
            : const <BomStockGroup>[];
        final expanded = controller.expandedCodes.toSet();
        final groupIds = <Object>[];
        final childIds = <String, List<Object>>{};
        final parents = <Object, Object>{};
        final rowIds = <Object>[];
        final occurrenceIds = <Object>[];
        if (hasDemand) {
          for (final group in groups) {
            final groupId = ('code', group.code);
            groupIds.add(groupId);
            occurrenceIds.add(groupId);
            if (!expanded.contains(group.code)) continue;
            final children = [
              for (final (i, row) in group.rows.indexed)
                (group.code, row['item_code'], row['bom'], i),
            ];
            childIds[group.code] = children;
            occurrenceIds.addAll(children);
            parents.addEntries(children.map((id) => MapEntry(id, groupId)));
          }
        } else {
          rowIds.addAll([
            for (final (i, row) in rows.indexed)
              (row['item_code'], row['bom'], i),
          ]);
          occurrenceIds.addAll(rowIds);
        }
        final indices = {for (final (i, id) in occurrenceIds.indexed) id: i};
        return ReportFieldsResults(
          controller: controller.fields,
          scrollController: controller.scrollController,
          result: (
            controller.resultRevision.value,
            controller.rowFilter.value,
            controller.posUpload.value,
          ),
          occurrenceIds: occurrenceIds,
          fallbacks: (id) => [if (parents[id] case final parent?) parent],
          builder: (_, anchors) => Obx(() {
            Widget anchor(Object id, Widget child) =>
                anchors.row(id, indices[id]!, child);
            final failed = controller.errorMessage.value;
            final footer =
                !controller.isRunning.value &&
                failed == null &&
                controller.reportRows.isNotEmpty;
            final shortageRows = controller.rowFilter.value == 'shortage'
                ? controller.reportRows
                : rows;
            return Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: controller.runReport,
                    color: cs.primary,
                    child: CustomScrollView(
                      controller: controller.scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        anchors.header(
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
                              ReportFieldsAction(controller: controller.fields),
                              AsyncIconButton(
                                busy: controller.isRunning,
                                onPressed: controller.runReport,
                                icon: const Icon(Icons.refresh),
                                tooltip: 'Run report',
                              ),
                            ],
                          ),
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
                                style: TextStyle(
                                  color: cs.onErrorContainer,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),

                        // ── Segmented row filter ──────────────────────────────
                        if (!controller.isRunning.value &&
                            failed == null &&
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
                        else if (failed != null ||
                            controller.reportRows.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.inventory_2_outlined,
                                      size: 64,
                                      color: cs.outlineVariant,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      failed ??
                                          (controller.hasResult.value
                                              ? 'No items found for these filters'
                                              : 'Set filters and run the report'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    FilledButton.tonalIcon(
                                      onPressed: failed == null
                                          ? () => showBomStockFilterSheet(
                                              context,
                                              controller,
                                            )
                                          : controller.runReport,
                                      icon: const Icon(
                                        Icons.filter_alt_outlined,
                                      ),
                                      label: Text(
                                        failed == null ? 'Run Report' : 'Retry',
                                      ),
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
                        else if (hasDemand)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                            sliver: SliverList.builder(
                              itemCount: groups.length,
                              itemBuilder: (_, index) {
                                final group = groups[index];
                                return BomStockGroupCard(
                                  group: group,
                                  expanded: expanded.contains(group.code),
                                  onToggle: () =>
                                      controller.toggleGroup(group.code),
                                  fields: fields,
                                  anchorHeader: (heading) =>
                                      anchor(groupIds[index], heading),
                                  anchorLine: (i, line) =>
                                      anchor(childIds[group.code]![i], line),
                                );
                              },
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => anchor(
                                  rowIds[index],
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: BomStockTile(
                                      row: rows[index],
                                      fields: fields,
                                    ),
                                  ),
                                ),
                                childCount: rows.length,
                              ),
                            ),
                          ),
                  if (footer)
                          const SliverToBoxAdapter(
                            child: ListEndFooter(
                              hasMore: false,
                              label: 'End of list',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (footer)
                  anchors.footer(
                    BomStockTotalsFooter(
                      totals: BomStockCustomerCodeController.sumTotals(rows),
                      hasDemand: hasDemand,
                      shortageMeasured: shortageRows.every(
                        (row) => toNum(row['shortage_qty']) != null,
                      ),
                      fields: fields,
                    ),
                  ),
              ],
            );
          }),
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
