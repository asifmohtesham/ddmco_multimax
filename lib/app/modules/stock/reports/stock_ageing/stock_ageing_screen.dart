import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_controller.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_logic.dart';

final _qtyFormat = NumberFormat('#,##0.##', 'en_GB');
final _valueFormat = NumberFormat('#,##0.00', 'en_GB');
final _compactFormat = NumberFormat.compact(locale: 'en_GB');

String _qty(num v) => _qtyFormat.format(v);

/// yyyy-MM-dd → DD/MM/YYYY; anything else is returned unchanged.
String _displayDate(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : DateFormat('dd/MM/yyyy').format(d);
}

/// Bucket colour: a ramp from the theme's primary (fresh) to error (oldest).
Color _bucketColour(ColorScheme cs, int index, int count) => count <= 1
    ? cs.primary
    : Color.lerp(cs.primary, cs.error, index / (count - 1))!;

class StockAgeingScreen extends GetView<StockAgeingController> {
  const StockAgeingScreen({super.key});

  static const _sorts = {
    'age': 'Oldest',
    'qty': 'Quantity',
    'old': 'Oldest bucket',
    'code': 'Item code',
  };

  void _openFilters(BuildContext context) => showReportFilterSheet(
        context: context,
        title: 'Stock Ageing Filters',
        fields: controller.filterFields,
        controllers: controller.filterControllers,
        toggles: controller.filterToggles,
        onRun: controller.runReport,
        onClear: controller.clearFilters,
      );

  List<Widget> _buildFilterChips(BuildContext context) => [
        for (final e in controller.activeFilters.entries)
          FilterChipWidget(
            icon: Icons.filter_alt_outlined,
            label: e.value,
            onDeleted: () => controller.clearFilter(e.key),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppShellScaffold(
      body: Obx(() {
        final loading = controller.isLoading.value;
        final hasData = controller.rows.isNotEmpty;
        final shown = controller.visibleRows;
        final buckets = controller.buckets.toList();

        return RefreshIndicator(
          onRefresh: controller.refreshReport,
          color: cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              DocTypeListHeader(
                title: 'Stock Ageing',
                automaticallyImplyLeading: false,
                activeFilters: controller.activeFilters,
                onFilterTap: () => _openFilters(context),
                filterChipsBuilder: _buildFilterChips,
                onClearAllFilters: controller.clearFilters,
              ),

              if (loading && hasData)
                const SliverToBoxAdapter(
                  child: LinearProgressIndicator(minHeight: 2),
                ),

              if (hasData) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: _SummaryCard(
                      asOn: controller.asOn.value,
                      fetchedAt: controller.fetchedAt.value,
                      rowCount: shown.length,
                      totals: controller.totalsOf(shown),
                      buckets: buckets,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: _SearchField(
                      onChanged: controller.onSearchChanged,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        for (final e in _sorts.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(e.value),
                              selected: controller.sort.value == e.key,
                              onSelected: (_) => controller.setSort(e.key),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],

              if (!hasData && loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _LoadingState(),
                )
              else if (!hasData)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    icon: controller.errorMessage.value == null
                        ? Icons.hourglass_empty_rounded
                        : Icons.error_outline_rounded,
                    message: controller.errorMessage.value ??
                        'No stock found for these filters',
                    onFilters: () => _openFilters(context),
                  ),
                )
              else if (shown.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    icon: Icons.search_off_outlined,
                    message: 'No rows match your search',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                  sliver: SliverList.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _AgeingTile(
                        row: shown[i],
                        buckets: buckets,
                        onTap: () => _showDetail(context, shown[i], buckets),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  void _showDetail(
    BuildContext context,
    Map<String, dynamic> row,
    List<AgeBucket> buckets,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _DetailSheet(row: row, buckets: buckets),
    );
  }
}

// ── Search ──────────────────────────────────────────────────────────────────

class _SearchField extends StatefulWidget {
  final ValueChanged<String> onChanged;
  const _SearchField({required this.onChanged});

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _text,
      onChanged: (v) {
        widget.onChanged(v);
        setState(() {});
      },
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search item, variant or warehouse',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _text.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _text.clear();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// ── Summary ─────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String asOn;
  final DateTime? fetchedAt;
  final int rowCount;
  final StockAgeingTotals totals;
  final List<AgeBucket> buckets;

  const _SummaryCard({
    required this.asOn,
    required this.fetchedAt,
    required this.rowCount,
    required this.totals,
    required this.buckets,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fetched = fetchedAt;
    final now = DateTime.now();
    final sameDay = fetched != null &&
        fetched.year == now.year &&
        fetched.month == now.month &&
        fetched.day == now.day;
    final fetchedText = fetched == null
        ? ''
        : ' · fetched ${DateFormat(sameDay ? 'HH:mm' : 'dd/MM/yyyy HH:mm').format(fetched)}';

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'As on ${_displayDate(asOn)}$fetchedText',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Figure(label: 'Quantity', value: _qty(totals.qty)),
                ),
                Expanded(
                  child: _Figure(
                    label: 'Value',
                    value: _compactFormat.format(totals.value),
                  ),
                ),
                Expanded(
                  child: _Figure(label: 'Rows', value: _qty(rowCount)),
                ),
              ],
            ),
            if (buckets.isNotEmpty) ...[
              const SizedBox(height: 12),
              _BucketBar(values: totals.bucketQty, height: 10),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < buckets.length; i++)
                    _LegendItem(
                      colour: _bucketColour(cs, i, buckets.length),
                      text:
                          '${buckets[i].label}: ${_qty(totals.bucketQty[i])}',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  const _Figure({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color colour;
  final String text;
  const _LegendItem({required this.colour, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(text,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Stacked horizontal bar: one segment per bucket, sized by its share.
class _BucketBar extends StatelessWidget {
  final List<double> values;
  final double height;
  const _BucketBar({required this.values, this.height = 6});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Negative stock would give a negative flex; clamp to zero.
    final shares = [for (final v in values) v > 0 ? v : 0.0];
    final total = shares.fold<double>(0, (a, b) => a + b);

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: total <= 0
            ? ColoredBox(color: cs.outlineVariant)
            : Row(
                children: [
                  for (var i = 0; i < shares.length; i++)
                    if (shares[i] > 0)
                      Expanded(
                        // Flex is an int; scale so small shares stay visible.
                        flex: (shares[i] / total * 1000).round().clamp(1, 1000),
                        child: ColoredBox(
                          color: _bucketColour(cs, i, shares.length),
                        ),
                      ),
                ],
              ),
      ),
    );
  }
}

// ── Row tile ────────────────────────────────────────────────────────────────

class _AgeingTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final List<AgeBucket> buckets;
  final VoidCallback onTap;

  const _AgeingTile({
    required this.row,
    required this.buckets,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final code = row['item_code']?.toString() ?? '';
    final name = row['item_name']?.toString() ?? '';
    final warehouse = row['warehouse']?.toString() ?? '';
    final uom = row['uom']?.toString() ?? '';
    final age = StockAgeingLogic.num_(row['average_age']).round();

    return Material(
      color: cs.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          code,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        if (name.isNotEmpty && name != code)
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_qty(StockAgeingLogic.num_(row['qty']))} $uom'
                            .trim(),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        'avg $age ${age == 1 ? 'day' : 'days'}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
              if (warehouse.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.warehouse_outlined,
                        size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        warehouse,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
              if (buckets.isNotEmpty) ...[
                const SizedBox(height: 10),
                _BucketBar(values: [
                  for (final b in buckets) StockAgeingLogic.num_(row[b.qtyKey]),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Detail sheet ────────────────────────────────────────────────────────────

class _DetailSheet extends StatelessWidget {
  final Map<String, dynamic> row;
  final List<AgeBucket> buckets;
  const _DetailSheet({required this.row, required this.buckets});

  String _text(String key) {
    final v = row[key]?.toString().trim() ?? '';
    return v.isEmpty ? '—' : v;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final figures = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final uom = row['uom']?.toString() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_text('item_code'),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          Text(_text('item_name'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Available',
                  value:
                      '${_qty(StockAgeingLogic.num_(row['qty']))} $uom'.trim(),
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Average age',
                  value:
                      '${StockAgeingLogic.num_(row['average_age']).round()} d',
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Earliest / Latest',
                  value:
                      '${StockAgeingLogic.num_(row['earliest']).round()} / ${StockAgeingLogic.num_(row['latest']).round()} d',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: Text('Age (days)', style: theme.textTheme.labelSmall),
              ),
              Expanded(
                flex: 3,
                child: Text('Qty',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall),
              ),
              Expanded(
                flex: 4,
                child: Text('Value',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall),
              ),
            ],
          ),
          for (var i = 0; i < buckets.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _bucketColour(cs, i, buckets.length),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: Text(buckets[i].label)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      _qty(StockAgeingLogic.num_(row[buckets[i].qtyKey])),
                      textAlign: TextAlign.end,
                      style: figures,
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      _valueFormat.format(
                          StockAgeingLogic.num_(row[buckets[i].valueKey])),
                      textAlign: TextAlign.end,
                      style: figures,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _DetailLine(label: 'Warehouse', value: _text('warehouse')),
          _DetailLine(label: 'Item Group', value: _text('item_group')),
          _DetailLine(label: 'Brand', value: _text('brand')),
          _DetailLine(label: 'Variant Of', value: _text('variant_of')),
          _DetailLine(
              label: 'Country of Origin', value: _text('country_of_origin')),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;
  const _DetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

// ── Empty / loading states ──────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Calculating stock ageing…\nThis can take about 20 seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? onFilters;

  const _EmptyState({
    required this.icon,
    required this.message,
    this.onFilters,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            if (onFilters != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: onFilters,
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Set Filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
