import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock/reports/batch_wise_balance/batch_wise_balance_controller.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';

class BatchWiseBalanceScreen extends GetView<BatchWiseBalanceController> {
  const BatchWiseBalanceScreen({super.key});

  // ── Filter chip builder ─────────────────────────────────────────────────

  List<Widget> _buildFilterChips(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final chips = <Widget>[];

    Widget chip(String key, String label) => Chip(
          avatar: Icon(Icons.filter_alt_outlined,
              size: 14, color: cs.onSecondaryContainer),
          label: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w600),
          ),
          backgroundColor: cs.secondaryContainer,
          deleteIconColor: cs.onSecondaryContainer,
          onDeleted: () => controller.clearFilter(key),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        );

    controller.activeFilters.forEach((key, label) {
      chips.add(chip(key, label));
    });
    return chips;
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: Obx(() {
        return RefreshIndicator(
          onRefresh: controller.runReport,
          color: cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Unified header ───────────────────────────────────────────
              DocTypeListHeader(
                title: 'Batch-Wise Balance',
                automaticallyImplyLeading: false,
                activeFilters: controller.activeFilters
                    .map((k, v) => MapEntry(k, v as dynamic))
                    .obs,
                onFilterTap: () => showReportFilterSheet(
                  context: context,
                  title:   'Batch-Wise Balance Filters',
                  fields:  BatchWiseBalanceController.filterFields,
                  controllers: controller.filterControllers,
                  onRun:   controller.runReport,
                  onClear: controller.clearFilters,
                ),
                filterChipsBuilder: _buildFilterChips,
                onClearAllFilters:  controller.clearFilters,
              ),

              // ── Results ───────────────────────────────────────────────────
              if (controller.isLoading.value)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (controller.reportData.isEmpty)
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
                            style: TextStyle(
                                color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.tonalIcon(
                            onPressed: () => showReportFilterSheet(
                              context: context,
                              title:  'Batch-Wise Balance Filters',
                              fields: BatchWiseBalanceController.filterFields,
                              controllers: controller.filterControllers,
                              onRun:  controller.runReport,
                              onClear: controller.clearFilters,
                            ),
                            icon: const Icon(Icons.filter_alt_outlined),
                            label: const Text('Set Filters'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding:
                      const EdgeInsets.fromLTRB(12, 4, 12, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final row =
                            controller.reportData[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _BalanceTile(row: row),
                        );
                      },
                      childCount: controller.reportData.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

// ── Result tile ───────────────────────────────────────────────────────────────────

class _BalanceTile extends StatelessWidget {
  final Map<String, dynamic> row;
  const _BalanceTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

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
                        row['item'] ?? 'Unknown Item',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                      if ((row['item_name'] ?? '') != '' &&
                          row['item_name'] != row['item'])
                        Text(
                          row['item_name'],
                          style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color:
                            cs.tertiary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${row['balance_qty'] ?? 0}',
                    style: TextStyle(
                        color: cs.onTertiaryContainer,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                    child: _Detail(
                        label: 'Batch',
                        value: row['batch'])),
                Expanded(
                    child: _Detail(
                        label: 'Warehouse',
                        value: row['warehouse'])),
              ],
            ),
            if ((row['expiry_date'] ?? '') != '') ...[
              const SizedBox(height: 8),
              _Detail(
                  label: 'Expiry',
                  value: row['expiry_date']),
            ],
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  final String  label;
  final dynamic value;
  const _Detail({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11, color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          value?.toString().isNotEmpty == true
              ? value.toString()
              : '—',
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
