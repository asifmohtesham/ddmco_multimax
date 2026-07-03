import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/result_count_pill.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_filter_sheet.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_tile.dart';

class PosDnItemRateScreen extends StatefulWidget {
  const PosDnItemRateScreen({super.key});

  @override
  State<PosDnItemRateScreen> createState() => _PosDnItemRateScreenState();
}

class _PosDnItemRateScreenState extends State<PosDnItemRateScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  PosDnItemRateController get controller => Get.find<PosDnItemRateController>();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

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
        final counts = controller.counts;
        final bottomInset = MediaQuery.of(context).padding.bottom;
        return RefreshIndicator(
          onRefresh: controller.runReport,
          color: cs.primary,
          child: Scrollbar(
            controller: _scrollCtrl,
            child: CustomScrollView(
              controller: _scrollCtrl,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                DocTypeListHeader(
                  title: 'POS & DN Item Rate',
                  automaticallyImplyLeading: false,
                  searchQuery: controller.searchQuery,
                  onSearchChanged: controller.setSearchQuery,
                  onSearchClear: () => controller.setSearchQuery(''),
                  activeFilters: controller.activeFilters
                      .map((k, v) => MapEntry(k, v as dynamic))
                      .obs,
                  onFilterTap: () =>
                      showPosDnItemRateFilterSheet(context, controller),
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

                // ── Summary strip (mobile stand-in for the Desk banner) ──
                if (controller.reportRows.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: _SummaryStrip(
                        counts: counts,
                        onTapStatus: controller.setStatusFilter,
                      ),
                    ),
                  ),

                // ── Status chips ─────────────────────────────────────────
                if (!controller.isRunning.value &&
                    controller.reportRows.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: _StatusChipRow(
                        counts: counts,
                        value: controller.statusFilter.value,
                        onChanged: controller.setStatusFilter,
                      ),
                    ),
                  ),

                // ── Result count pill ────────────────────────────────────
                if (!controller.isRunning.value &&
                    controller.reportRows.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: ResultCountPill(
                        count: rows.length,
                        hasMore: false,
                        hasActiveFilters:
                            controller.statusFilter.value != 'ALL' ||
                            controller.searchQuery.value.trim().isNotEmpty ||
                            controller.activeFilters.isNotEmpty,
                        noun: 'row',
                        icon: Icons.receipt_long_outlined,
                      ),
                    ),
                  ),

                // ── Body ──────────────────────────────────────────────────
                if (controller.isRunning.value)
                  const SliverToBoxAdapter(child: DocCardSkeletonList())
                else if (controller.errorMessage.value != null &&
                    controller.reportRows.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline,
                                size: 64, color: cs.error),
                            const SizedBox(height: 16),
                            Text(
                              controller.errorMessage.value!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.tonalIcon(
                              onPressed: controller.runReport,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (!controller.hasRun.value)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined,
                                size: 64, color: cs.outlineVariant),
                            const SizedBox(height: 16),
                            Text(
                              'Runs over the last 30 days by default.\n'
                              'Adjust filters, then run the report.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.tonalIcon(
                              onPressed: () => showPosDnItemRateFilterSheet(
                                  context, controller),
                              icon: const Icon(Icons.filter_alt_outlined),
                              label: const Text('Run Report'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (controller.reportRows.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No rows for these filters',
                          style: TextStyle(color: cs.onSurfaceVariant),
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
                          'No rows match this status / search',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: PosDnItemRateTile(row: rows[index]),
                        ),
                        childCount: rows.length,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          EdgeInsets.fromLTRB(12, 4, 12, 16 + bottomInset),
                      child: _EndOfListFooter(
                        totals: PosDnItemRateController.sumTotals(rows),
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

/// N new | N no delivery | N no code — tap a count to filter to that status.
class _SummaryStrip extends StatelessWidget {
  final Map<String, int> counts;
  final ValueChanged<String> onTapStatus;
  const _SummaryStrip({required this.counts, required this.onTapStatus});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget cell(String status, String label) {
      final n = counts[status] ?? 0;
      final accent = posDnStatusAccent(context, status);
      return Expanded(
        child: InkWell(
          onTap: () => onTapStatus(status),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$n $label',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: accent),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          cell(PosDnItemRateController.statusNew, 'new'),
          const SizedBox(width: 6),
          cell(PosDnItemRateController.statusNoDelivery, 'no delivery'),
          const SizedBox(width: 6),
          cell(PosDnItemRateController.statusNoCode, 'no code'),
        ],
      ),
    );
  }
}

/// All + one chip per status present in the data (with row counts).
class _StatusChipRow extends StatelessWidget {
  final Map<String, int> counts;
  final String value;
  final ValueChanged<String> onChanged;
  const _StatusChipRow({
    required this.counts,
    required this.value,
    required this.onChanged,
  });

  static const _order = [
    PosDnItemRateController.statusNew,
    PosDnItemRateController.statusNoDelivery,
    PosDnItemRateController.statusNoCode,
    PosDnItemRateController.statusMapped,
  ];

  @override
  Widget build(BuildContext context) {
    final present = _order.where((s) => (counts[s] ?? 0) > 0);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ChoiceChip(
          label: const Text('All'),
          selected: value == 'ALL',
          onSelected: (_) => onChanged('ALL'),
          visualDensity: VisualDensity.compact,
        ),
        for (final s in present)
          ChoiceChip(
            label: Text('$s (${counts[s]})'),
            selected: value == s,
            // Toggle-off back to All when re-tapping the active chip.
            onSelected: (_) => onChanged(value == s ? 'ALL' : s),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

/// End-of-list marker + totals summary (row count, summed POS/DN qty over the
/// currently-shown rows). Rate is intentionally not summed.
class _EndOfListFooter extends StatelessWidget {
  final Map<String, num> totals;
  const _EndOfListFooter({required this.totals});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final count = totals['count'] ?? 0;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: cs.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('End of list · $count row${count == 1 ? '' : 's'}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ),
            Expanded(child: Divider(color: cs.outlineVariant)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Total(label: 'Total POS Qty', value: totals['pos_qty'] ?? 0),
              _Total(label: 'Total DN Qty', value: totals['dn_qty'] ?? 0),
            ],
          ),
        ),
      ],
    );
  }
}

class _Total extends StatelessWidget {
  final String label;
  final num value;
  const _Total({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final d = value.toDouble();
    final text = d == d.roundToDouble()
        ? d.toStringAsFixed(0)
        : d.toStringAsFixed(2);
    return Column(
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: cs.onSurfaceVariant)),
        Text(text,
            style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700, fontFamily: 'ShureTechMono')),
      ],
    );
  }
}
