import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_controller.dart';

class StockBalanceScreen extends GetView<StockBalanceController> {
  const StockBalanceScreen({super.key});

  // ── Standard fields that should never render as attribute chips ────────────
  static const _skipFields = {
    'item_code',
    'item_name',
    'warehouse',
    'item_group',
    'stock_uom',
    'opening_qty',
    'in_qty',
    'out_qty',
    'balance_qty',
    'opening_val',
    'in_val',
    'out_val',
    'balance_val',
    'valuation_rate',
  };

  // ── Filter chip builder ───────────────────────────────────────────────────
  //
  // Returns List<Widget> — one InputChip per active filter.
  // DocTypeListHeader wraps them in a horizontal SingleChildScrollView
  // internally, so this builder only needs to produce the chip widgets.

  List<Widget> _buildFilterChips(BuildContext context) {
    // Routes through the shared FilterChipWidget so chip styling stays uniform
    // across every list and report screen.
    final chips = <Widget>[];
    // Relies on being called synchronously inside the parent Obx() rebuild.
    controller.activeFilters.forEach((key, label) {
      chips.add(FilterChipWidget(
        icon: Icons.filter_alt_outlined,
        label: label,
        onDeleted: () => controller.clearFilter(key),
      ));
    });
    return chips;
  }

  // ── Filter sheet helper ───────────────────────────────────────────────────

  void _openFilters(BuildContext context) => showReportFilterSheet(
        context: context,
        title: 'Stock Balance Filters',
        fields: controller.filterFields,
        controllers: controller.filterControllers,
        chipGroups: controller.chipGroups,
        onRun: controller.runReport,
        onClear: controller.clearFilters,
      );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppShellScaffold(
      body: Obx(() {
        return RefreshIndicator(
          onRefresh: controller.runReport,
          color: cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Unified header ──────────────────────────────────────
              DocTypeListHeader(
                title: 'Stock Balance',
                automaticallyImplyLeading: false,
                activeFilters: controller.activeFilters,
                onFilterTap: () => _openFilters(context),
                filterChipsBuilder: _buildFilterChips,
                onClearAllFilters: controller.clearFilters,
              ),

              // ── Results ────────────────────────────────────────────
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
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: cs.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Set filters and run the report',
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
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final row = controller.reportData[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _BalanceTile(
                            row: row,
                            attrCols: controller.reportColumns
                                .where((c) => !_skipFields
                                    .contains(c['fieldname'] as String? ?? ''))
                                .toList(),
                          ),
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

// ── Result tile ──────────────────────────────────────────────────────────────

class _BalanceTile extends StatelessWidget {
  final Map<String, dynamic>       row;
  final List<Map<String, dynamic>> attrCols;

  const _BalanceTile({required this.row, required this.attrCols});

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;

    final itemCode  = row['item_code']?.toString() ?? '—';
    final itemName  = row['item_name']?.toString() ?? '';
    final warehouse = row['warehouse']?.toString() ?? '';

    final rawQty    = row['balance_qty'];
    final balanceQty = (rawQty is num) ? rawQty.toDouble() : double.tryParse(rawQty?.toString() ?? '') ?? 0.0;
    final isNeg     = balanceQty < 0;

    final badgeBg     = isNeg ? cs.errorContainer     : cs.tertiaryContainer;
    final badgeFg     = isNeg ? cs.onErrorContainer    : cs.onTertiaryContainer;
    final badgeBorder = (isNeg ? cs.error : cs.tertiary).withValues(alpha: 0.3);

    final openingQty = row['opening_qty'];
    final inQty      = row['in_qty'];
    final outQty     = row['out_qty'];

    return Material(
      color: cs.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemCode,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      if (itemName.isNotEmpty && itemName != itemCode)
                        Text(
                          itemName,
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeBorder),
                  ),
                  child: Text(
                    balanceQty % 1 == 0 ? balanceQty.toStringAsFixed(0) : balanceQty.toString(),
                    style: TextStyle(
                        color: badgeFg, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),

            const Divider(height: 20),

            // ── Warehouse ─────────────────────────────────────────────
            _Detail(label: 'Warehouse', value: warehouse),
            const SizedBox(height: 8),

            // ── Opening / In / Out ────────────────────────────────────
            Row(
              children: [
                Expanded(child: _Detail(label: 'Opening', value: openingQty)),
                Expanded(child: _Detail(label: 'In',      value: inQty)),
                Expanded(child: _Detail(label: 'Out',     value: outQty)),
              ],
            ),

            // ── Attribute chips (non-standard columns) ─────────────────
            if (attrCols.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final col in attrCols)
                    Builder(builder: (ctx) {
                      final fieldname = col['fieldname'] as String? ?? '';
                      final label     = col['label']     as String? ?? fieldname;
                      final val       = row[fieldname];
                      if (val == null || val.toString().trim().isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return _AttrChip(label: label, value: val.toString());
                    }),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Detail widget ─────────────────────────────────────────────────────────────

class _Detail extends StatelessWidget {
  final String  label;
  final dynamic value;
  const _Detail({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Format quantity values: show whole numbers without decimals
    String formatValue(dynamic val) {
      if (val?.toString().isEmpty == true) return '—';
      final str = val.toString();
      final num? parsed = num.tryParse(str);
      if (parsed != null && parsed % 1 == 0) {
        return parsed.toStringAsFixed(0);
      }
      return str;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          formatValue(value),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

// ── Attribute chip ─────────────────────────────────────────────────────────────

class _AttrChip extends StatelessWidget {
  final String label;
  final String value;
  const _AttrChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $value',
        style: text.labelSmall?.copyWith(
          color: cs.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
