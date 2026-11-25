import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock/reports/batch_wise_balance/batch_wise_balance_binding.dart';
import 'package:multimax/app/modules/stock/reports/batch_wise_balance/batch_wise_balance_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_anchor.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_sheet.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';

import 'batch_wise_balance_fields.dart';

class BatchWiseBalanceScreen extends StatefulWidget {
  const BatchWiseBalanceScreen({super.key});

  @override
  State<BatchWiseBalanceScreen> createState() => _BatchWiseBalanceScreenState();
}

class _BatchWiseBalanceScreenState extends State<BatchWiseBalanceScreen> {
  late final controller = Get.find<BatchWiseBalanceController>(
    tag: BatchWiseBalanceBinding.tagForRoute(ModalRoute.of(context)),
  );

  // ── Filter chip builder ───────────────────────────────────────────────────
  //
  // Returns List<Widget> — one InputChip per active filter.
  // DocTypeListHeader wraps them in a horizontal SingleChildScrollView
  // internally, so this builder only needs to produce the chip widgets.
  // InputChip gives the delete icon a full 48dp tap target out of the box.

  /// [focusKey] opens the sheet on that filter, ready to edit.
  void _openFilters(BuildContext context, {String? focusKey}) =>
      showReportFilterSheet(
        context: context,
        focusKey: focusKey,
        title: 'Batch-Wise Balance History Filters',
        fields: controller.filterFields,
        controllers: controller.filterControllers,
        runBusy: controller.isLoading,
        onRun: controller.runReport,
        onClear: controller.clearFilters,
      );

  List<Widget> _buildFilterChips(BuildContext context) {
    // Routes through the shared FilterChipWidget so chip styling stays uniform
    // across every list and report screen.
    final chips = <Widget>[];
    controller.activeFilters.forEach((key, label) {
      chips.add(
        FilterChipWidget(
          icon: Icons.filter_alt_outlined,
          label: label,
          onDeleted: () => controller.clearFilter(key),
          onTap: () => _openFilters(context, focusKey: key),
        ),
      );
    });
    return chips;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppShellScaffold(
      body: Obx(() {
        final loading = controller.isLoading.value;
        final hasRun = controller.hasRun.value;
        final fields = controller.fields.state.value;
        final rows = controller.reportData.toList(growable: false);
        final occurrences = batchOccurrences(rows);
        final bottom = MediaQuery.paddingOf(context).bottom;
        final error = controller.reportError.value;
        return RefreshIndicator(
          onRefresh: controller.runReport,
          color: cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
          child: ReportFieldsResults(
            controller: controller.fields,
            scrollController: controller.scroll,
            result: controller.resultRevision.value,
            occurrenceIds: occurrences,
            builder: (context, anchors) => CustomScrollView(
              controller: controller.scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── Unified header ──────────────────────────────────────────
                anchors.header(
                  DocTypeListHeader(
                    title: 'Batch-Wise Balance History',
                    automaticallyImplyLeading: false,
                    activeFilters: controller.activeFilters,
                    onFilterTap: () => _openFilters(context),
                    filterChipsBuilder: _buildFilterChips,
                    onClearAllFilters: controller.clearFilters,
                    extraActions: [
                      ReportFieldsAction(controller: controller.fields),
                    ],
                  ),
                ),

                // ── Results ────────────────────────────────────────────────
                if (loading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (error != null || hasRun && rows.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            error ?? 'No rows for these filters',
                            textAlign: TextAlign.center,
                          ),
                          if (error != null)
                            TextButton(
                              onPressed: controller.runReport,
                              child: const Text('Retry'),
                            )
                          else ...[
                            const SizedBox(height: 16),
                            const Text('End of list'),
                          ],
                        ],
                      ),
                    ),
                  )
                else if (rows.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history_toggle_off_outlined,
                              size: 64,
                              color: cs.outlineVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Enter filters and tap the filter icon to run the report',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.tonalIcon(
                              onPressed: () => _openFilters(context),
                              icon: const Icon(Icons.filter_alt_outlined),
                              label: const Text('Set Filters'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        return anchors.row(
                          occurrences[index],
                          index,
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _BalanceTile(
                              row: rows[index],
                              fields: fields,
                            ),
                          ),
                        );
                      }, childCount: rows.length),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
                      child: _BatchFooter(
                        totals: batchTotals(rows),
                        columns: controller.columns,
                        fields: fields,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ── Result tile ──────────────────────────────────────────────────────────────

class _BalanceTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final FieldsState fields;
  const _BalanceTile({required this.row, required this.fields});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final quantity = batchQuantity(row['balance_qty']);
    final item = row['item']?.toString().trim().isNotEmpty == true
        ? row['item'].toString()
        : 'Unknown Item';

    return Material(
      color: cs.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item,
                        semanticsLabel:
                            "${fields.label('item') ?? 'Item'} $item",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      if ((row['item_name'] ?? '') != '' &&
                          row['item_name'] != row['item'])
                        Text(
                          row['item_name'].toString(),
                          semanticsLabel:
                              "${fields.label('item_name') ?? 'Item Name'} ${row['item_name']}",
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (fields.shows('balance_qty') || quantity == null)
                  Semantics(
                    label: fields.label('balance_qty') ?? 'Balance Qty',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: cs.tertiary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        quantity == null ? '—' : row['balance_qty'].toString(),
                        style: TextStyle(
                          color: cs.onTertiaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: _Detail(
                    label: fields.label('batch') ?? 'Batch',
                    value: row['batch'],
                  ),
                ),
                Expanded(
                  child: _Detail(
                    label: fields.label('warehouse') ?? 'Warehouse',
                    value: row['warehouse'],
                  ),
                ),
              ],
            ),
            if ((row['expiry_date'] ?? '') != '') ...[
              const SizedBox(height: 8),
              _Detail(label: 'Expiry', value: row['expiry_date']),
            ],
          ],
        ),
      ),
    );
  }
}

class _BatchFooter extends StatelessWidget {
  const _BatchFooter({
    required this.totals,
    required this.columns,
    required this.fields,
  });

  final Map<String, Map<String, num>> totals;
  final List<DeskColumn>? columns;
  final FieldsState fields;

  String _label(String key) {
    for (final column in columns ?? const <DeskColumn>[]) {
      if (column.fieldname == key && column.label.trim().isNotEmpty) {
        return column.label;
      }
    }
    return fields.label(key) ?? batchQuantityHeaders[key]!;
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Text('End of list'),
      if (totals.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('Totals'),
        for (final entry in totals.entries)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                Text(entry.key.isEmpty ? 'Unknown unit' : entry.key),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    for (final key in batchQuantityHeaders.keys)
                      if (entry.value.containsKey(key))
                        _Detail(label: _label(key), value: entry.value[key]),
                  ],
                ),
              ],
            ),
          ),
      ],
    ],
  );
}

class _Detail extends StatelessWidget {
  final String label;
  final dynamic value;
  const _Detail({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          value?.toString().isNotEmpty == true ? value.toString() : '—',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
