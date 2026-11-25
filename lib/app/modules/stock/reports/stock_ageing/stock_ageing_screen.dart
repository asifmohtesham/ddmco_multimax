import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/item_image.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_anchor.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_controller.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_owner_overlay.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_sheet.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_controller.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_logic.dart';

final _qtyFormat = NumberFormat('#,##0.##', 'en_GB');
final _compactFormat = NumberFormat.compact(locale: 'en_GB');

String _qty(num v) => _qtyFormat.format(v);

String _measuredTotal(
  String formatted,
  int measured,
  int expected, {
  String unit = '',
}) {
  final number = expected > 0 && measured == 0 ? '—' : formatted;
  final withUnit = unit.isEmpty ? number : '$number $unit';
  return measured > 0 && measured < expected ? '$withUnit (partial)' : withUnit;
}

/// yyyy-MM-dd → DD/MM/YYYY; anything else is returned unchanged.
String _displayDate(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : DateFormat('dd/MM/yyyy').format(d);
}

/// Fresh → old ramp (green, lime, amber, orange, red). Fixed rather than
/// derived from the theme, whose primary and error colours can both be red.
const _ageRamp = [
  Color(0xFF2E9E6A),
  Color(0xFF8DB33A),
  Color(0xFFE0B020),
  Color(0xFFE8802A),
  Color(0xFFD64545),
];

/// Colour of bucket [index] out of [count], interpolated along [_ageRamp].
Color _bucketColour(int index, int count) {
  if (count <= 1) return _ageRamp.first;
  final t = index / (count - 1) * (_ageRamp.length - 1);
  final lo = t.floor().clamp(0, _ageRamp.length - 2);
  return Color.lerp(_ageRamp[lo], _ageRamp[lo + 1], t - lo)!;
}

class StockAgeingScreen extends GetView<StockAgeingController> {
  const StockAgeingScreen({super.key});

  /// [focusKey] opens the sheet on that filter, ready to edit.
  void _openFilters(BuildContext context, {String? focusKey}) =>
      showReportFilterSheet(
        context: context,
        focusKey: focusKey,
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
        onTap: () => _openFilters(context, focusKey: e.key),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AppShellScaffold(
      body: Obx(() {
        final loading = controller.isLoading.value;
        final error = controller.errorMessage.value;
        final hasData = controller.rows.isNotEmpty;
        final shown = controller.visibleRows;
        final buckets = controller.buckets.toList();
        final fields = controller.fields.state.value;
        final owner = controller.fields.ownerGeneration;
        final view = controller.view.state.value;
        final columns = controller.columns.toList();
        final sort = controller.sort.value;
        final search = controller.searchQuery.value;
        final quantityLabel = fields.label('qty') ?? 'Available Qty';
        final oldest = buckets.lastOrNull;
        final sorts = {
          'age': fields.label('average_age') ?? 'Average Age',
          'qty': quantityLabel,
          'old': oldest?.reportLabel == null
              ? 'Oldest bucket'
              : oldest!.qualifiedLabel,
          'code': fields.label('item_code') ?? 'Item Code',
        };
        final counters = <(String, String), int>{};
        final occurrenceIds = [
          for (final row in shown) _occurrence(row, counters),
        ];

        return RefreshIndicator(
          onRefresh: controller.refreshReport,
          color: cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
          child: ReportFieldsResults(
            controller: controller.fields,
            viewController: controller.view,
            scrollController: controller.scrollController,
            result: (controller.resultRevision.value, search, sort),
            occurrenceIds: occurrenceIds,
            builder: (context, anchors) => CustomScrollView(
              controller: controller.scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                anchors.header(
                  DocTypeListHeader(
                    title: 'Stock Ageing',
                    automaticallyImplyLeading: false,
                    activeFilters: controller.activeFilters,
                    onFilterTap: () => _openFilters(context),
                    filterChipsBuilder: _buildFilterChips,
                    onClearAllFilters: controller.clearFilters,
                    extraActions: [
                      ReportFieldsAction(controller: controller.fields),
                      _ViewAction(controller: controller),
                    ],
                    quickChips: [
                      for (final e in sorts.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: sort == e.key,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => controller.setSort(e.key),
                        ),
                    ],
                    quickChipsKey: (
                      sort,
                      sorts.values.join('|'),
                      controller.activeFilters.values.join('|'),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: loading && hasData
                      ? const LinearProgressIndicator(minHeight: 2)
                      : const SizedBox.shrink(),
                ),
                if (hasData && error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _RetryNotice(
                        message: error,
                        onRetry: controller.refreshReport,
                      ),
                    ),
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
                        quantityLabel: quantityLabel,
                        buckets: buckets,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                      child: _SearchField(
                        controller: controller.searchController,
                        onChanged: controller.onSearchChanged,
                      ),
                    ),
                  ),
                ],
                if (!hasData &&
                    (loading || (!controller.hasRun.value && error == null)))
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _LoadingState(),
                  )
                else if (!hasData)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      icon: error == null
                          ? Icons.hourglass_empty_rounded
                          : Icons.error_outline_rounded,
                      message: error ?? 'No stock found for these filters',
                      onFilters: () => _openFilters(context),
                      onRetry: error == null ? null : controller.refreshReport,
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
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    sliver: SliverList.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) => anchors.row(
                        occurrenceIds[i],
                        i,
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _AgeingTile(
                            row: shown[i],
                            columns: columns,
                            buckets: buckets,
                            fields: fields,
                            showAgeBar: view.shows('ageBar'),
                            imageUrl: controller.imageUrlOf(shown[i]),
                            onTap: () => _showDetail(
                              context,
                              shown[i],
                              columns,
                              buckets,
                              owner,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _AgeingEnd(
                      rows: shown,
                      buckets: buckets,
                      quantityLabel: quantityLabel,
                      bottomInset: bottomInset,
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

  static (String, String, int) _occurrence(
    Map<String, dynamic> row,
    Map<(String, String), int> counts,
  ) {
    final identity = (
      row['item_code']?.toString() ?? '',
      row['warehouse']?.toString() ?? '',
    );
    final occurrence = counts.update(
      identity,
      (count) => count + 1,
      ifAbsent: () => 0,
    );
    return (identity.$1, identity.$2, occurrence);
  }

  void _showDetail(
    BuildContext context,
    Map<String, dynamic> row,
    List<ReportColumn> columns,
    List<AgeBucket> buckets,
    int generation,
  ) {
    final fields = controller.fields;
    if (generation != fields.ownerGeneration) return;
    final imageUrl = controller.imageUrlOf(row);
    final asOn = StockAgeingLogic.reportDate(
      controller.asOn.value,
      controller.fetchedAt.value,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // The sheet draws its own handle so the image can run edge to edge,
      // clipped to the sheet's rounded corners.
      clipBehavior: Clip.antiAlias,
      builder: (_) => ReportFieldsOwnerOverlay(
        fields: fields,
        generation: generation,
        builder: (_) => _DetailSheet(
          row: row,
          columns: columns,
          buckets: buckets,
          imageUrl: imageUrl,
          asOn: asOn,
          fields: fields,
          generation: generation,
        ),
      ),
    );
  }
}

class _ViewAction extends StatelessWidget {
  const _ViewAction({required this.controller});

  final StockAgeingController controller;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      Obx(() {
        final view = controller.view;
        final state = view.state.value;
        return CheckboxMenuButton(
          value: state.selected('ageBar'),
          closeOnActivate: false,
          onChanged: state.canEdit('ageBar')
              ? (value) => view.setVisible('ageBar', value ?? false)
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Age bar'),
              if (state.pendingKeys.contains('ageBar') || state.snapshot.saving)
                const Padding(
                  padding: EdgeInsetsDirectional.only(start: 12),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel: 'Saving field settings…',
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    ],
    builder: (context, menu, _) => IconButton(
      tooltip: 'View',
      icon: const Icon(Icons.tune),
      onPressed: () {
        if (menu.isOpen) {
          menu.close();
        } else {
          menu.open();
        }
      },
    ),
  );
}

class _RetryNotice extends StatelessWidget {
  const _RetryNotice({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppColors.red300 : AppColors.red700;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          Icon(Icons.error_outline, color: ink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: ink)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _AgeingEnd extends StatelessWidget {
  const _AgeingEnd({
    required this.rows,
    required this.buckets,
    required this.quantityLabel,
    required this.bottomInset,
  });

  final List<Map<String, dynamic>> rows;
  final List<AgeBucket> buckets;
  final String quantityLabel;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final byUnit = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final unit = row['uom']?.toString().trim() ?? '';
      byUnit.putIfAbsent(unit, () => []).add(row);
    }
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.scheme.textMuted);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 16, 12, 80 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('End of list', style: style, textAlign: TextAlign.center),
          for (final entry in byUnit.entries) _unitTotals(entry, style),
        ],
      ),
    );
  }

  Widget _unitTotals(
    MapEntry<String, List<Map<String, dynamic>>> entry,
    TextStyle? style,
  ) {
    final totals = StockAgeingLogic.totals(entry.value, buckets);
    final unit = entry.key.isEmpty ? 'Unknown UOM' : entry.key;
    final count = entry.value.length;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        [
          '$quantityLabel ${_measuredTotal(_qty(totals.qty), totals.qtyCount, count, unit: unit)}',
          for (var i = 0; i < buckets.length; i++)
            '${buckets[i].qualifiedLabel} · ${_measuredTotal(_qty(totals.bucketQty[i]), totals.bucketQtyCount[i], count, unit: unit)}',
        ].join('\n'),
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }
}

// ── Search ──────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        // Drop focus on a tap elsewhere so the keyboard does not reopen
        // when the filter or detail sheet closes.
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search item, variant or warehouse',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
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
  final String quantityLabel;

  const _SummaryCard({
    required this.asOn,
    required this.fetchedAt,
    required this.rowCount,
    required this.totals,
    required this.buckets,
    required this.quantityLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fetched = fetchedAt;
    final now = DateTime.now();
    final sameDay =
        fetched != null &&
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
              asOn.isEmpty
                  ? fetchedText.replaceFirst(' · f', 'F')
                  : 'As on ${_displayDate(asOn)}$fetchedText',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: quantityLabel,
                    value: _measuredTotal(_qty(totals.qty), totals.qtyCount, rowCount),
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: 'Value',
                    value: _measuredTotal(
                      _compactFormat.format(totals.value),
                      totals.valueCount,
                      rowCount * buckets.length,
                    ),
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
                      colour: _bucketColour(i, buckets.length),
                      text:
                          '${buckets[i].qualifiedLabel}: ${_measuredTotal(_qty(totals.bucketQty[i]), totals.bucketQtyCount[i], rowCount)}',
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
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
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
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
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
                // Stretch so the childless coloured boxes fill the bar height.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < shares.length; i++)
                    if (shares[i] > 0)
                      Expanded(
                        // Flex is an int; scale so small shares stay visible.
                        flex: (shares[i] / total * 1000).round().clamp(1, 1000),
                        child: ColoredBox(
                          color: _bucketColour(i, shares.length),
                        ),
                      ),
                ],
              ),
      ),
    );
  }
}

// ── Row tile ────────────────────────────────────────────────────────────────

/// One report row. Item Code and Available Qty are always shown; every other
/// element is a report column the user has chosen, under the column's own
/// title.
class _AgeingTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final List<ReportColumn> columns;
  final List<AgeBucket> buckets;

  final FieldsState fields;
  final bool showAgeBar;
  final String? imageUrl;
  final VoidCallback onTap;

  const _AgeingTile({
    required this.row,
    required this.columns,
    required this.buckets,
    required this.fields,
    required this.showAgeBar,
    required this.imageUrl,
    required this.onTap,
  });

  /// Columns with their own place on the card, so not repeated in the
  /// label–value list.
  static const _placed = {'item_code', 'qty', 'uom', 'item_name', 'variant_of'};

  String _text(String key) => row[key]?.toString().trim() ?? '';

  ReportColumn? _column(String fieldname) {
    for (final c in columns) {
      if (c.fieldname == fieldname) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final strong = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final code = _text('item_code');
    final name = _text('item_name');
    final variantOf = _text('variant_of');
    final variantCol = _column('variant_of');
    final qtyCol = _column('qty');
    final quantity = StockAgeingLogic.measurement(row['qty']);
    final qtyText = quantity == null ? '—' : _qty(quantity);
    final uom = _text('uom');

    final showImage = columns.any(
      (c) => c.isImage && fields.shows(c.fieldname),
    );
    final showVariant =
        fields.shows('variant_of') &&
        variantCol != null &&
        variantOf.isNotEmpty;

    // Remaining chosen columns, in report order, under their own titles.
    final pairs = <(String, String, String?)>[
      for (final c in columns)
        if (fields.shows(c.fieldname) &&
            !_placed.contains(c.fieldname) &&
            !c.isImage &&
            _text(c.fieldname).isNotEmpty)
          (
            c.label,
            StockAgeingLogic.formatCell(c, row[c.fieldname]),
            c.rangeHint,
          ),
      if (_column('warehouse') == null && _text('warehouse').isNotEmpty)
        (fields.label('warehouse')!, _text('warehouse'), null),
    ];

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
              LayoutBuilder(
                builder: (context, constraints) {
                  const thumbnailSize = 46.0;
                  const thumbnailGap = 10.0;
                  const quantityGap = 12.0;
                  final thumbnailWidth = showImage
                      ? thumbnailSize + thumbnailGap
                      : 0;
                  final maxQuantityWidth =
                      ((constraints.maxWidth - thumbnailWidth - quantityGap) /
                              2)
                          .clamp(0.0, double.infinity);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showImage) ...[
                        ItemThumbnail(
                          imageUrl: imageUrl,
                          itemCode: code,
                          itemName: name,
                          size: thumbnailSize,
                        ),
                        const SizedBox(width: thumbnailGap),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              code,
                              style: strong,
                              semanticsLabel:
                                  '${fields.label('item_code')} $code',
                            ),
                            if (name.isNotEmpty && name != code)
                              Text(
                                name,
                                semanticsLabel:
                                    '${fields.label('item_name')} $name',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: muted,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: quantityGap),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxQuantityWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              qtyCol?.label ?? 'Available Qty',
                              style: muted,
                              textAlign: TextAlign.end,
                            ),
                            Text(
                              '$qtyText $uom'.trim(),
                              semanticsLabel: uom.isEmpty
                                  ? null
                                  : "$qtyText ${fields.label('uom') ?? 'UOM'} $uom",
                              textAlign: TextAlign.end,
                              style: strong,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (showVariant) ...[
                const SizedBox(height: 8),
                _VariantBadge(label: variantCol.label, value: variantOf),
              ],
              if (pairs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 2,
                  children: [
                    for (final (label, value, hint) in pairs)
                      Text.rich(
                        TextSpan(
                          text: label.isEmpty ? '' : '$label  ',
                          style: muted,
                          children: [
                            TextSpan(
                              text: value,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            if (hint != null) TextSpan(text: '\n$hint'),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              if (showAgeBar && buckets.isNotEmpty) ...[
                const SizedBox(height: 10),
                _BucketBar(
                  values: [
                    for (final b in buckets)
                      StockAgeingLogic.num_(row[b.qtyKey]),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The prominent "Variant Of" line on a card: the column title and its value
/// in a tinted badge.
class _VariantBadge extends StatelessWidget {
  final String label;
  final String value;
  const _VariantBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(
          text: '$label  ',
          style: theme.textTheme.labelMedium?.copyWith(
            color: cs.onPrimaryContainer,
          ),
          children: [
            TextSpan(
              text: value,
              style: theme.textTheme.titleSmall?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Every column of one report row, in report order and under the report's
/// own column titles, with the item image shown large at the top.
class _DetailSheet extends StatelessWidget {
  final Map<String, dynamic> row;
  final List<ReportColumn> columns;
  final List<AgeBucket> buckets;
  final String? imageUrl;
  final ReportFieldsController fields;
  final int generation;

  /// The date the row's ages are counted from; null leaves out the year.
  final DateTime? asOn;

  const _DetailSheet({
    required this.row,
    required this.columns,
    required this.buckets,
    required this.imageUrl,
    required this.asOn,
    required this.fields,
    required this.generation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final code = row['item_code']?.toString() ?? '';
    final name = row['item_name']?.toString() ?? '';

    // Bucket columns carry their bucket's colour as a visual key.
    final bucketIndex = <String, int>{
      for (var i = 0; i < buckets.length; i++) ...{
        buckets[i].qtyKey: i,
        buckets[i].valueKey: i,
      },
    };

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.only(
          bottom: 24 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          if (imageUrl != null)
            // Edge to edge: no side padding, no gap above. The handle sits
            // over the image.
            Stack(
              alignment: Alignment.topCenter,
              children: [
                GestureDetector(
                  onTap: () => showDialog<void>(
                    context: context,
                    useSafeArea: false,
                    builder: (_) => ReportFieldsOwnerOverlay(
                      fields: fields,
                      generation: generation,
                      builder: (_) => ItemImagePreview(
                        url: imageUrl!,
                        title: [code, name]
                            .where((text) => text.isNotEmpty)
                            .join(' · '),
                      ),
                    ),
                  ),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl!,
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                    placeholder: (_, __) => AspectRatio(
                      aspectRatio: 1,
                      child: ColoredBox(color: cs.surfaceContainerHighest),
                    ),
                    errorWidget: (_, __, ___) => AspectRatio(
                      aspectRatio: 2,
                      child: ColoredBox(
                        color: cs.surfaceContainerHighest,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                const _SheetHandle(onImage: true),
              ],
            )
          else
            const _SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (name.isNotEmpty)
                  Text(
                    name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                for (final c in columns)
                  // The image is shown above; without one its row reads "—".
                  if (!(c.isImage && imageUrl != null))
                    _DetailLine(
                      label: c.rangeHint == null
                          ? c.label
                          : '${c.label}\n${c.rangeHint}',
                      value: c.isImage
                          ? '—'
                          : StockAgeingLogic.formatDetailCell(
                              c,
                              row[c.fieldname],
                              asOn: asOn,
                            ),
                      dot: bucketIndex.containsKey(c.fieldname)
                          ? _bucketColour(
                              bucketIndex[c.fieldname]!,
                              buckets.length,
                            )
                          : null,
                      numeric: const {
                        'Float',
                        'Int',
                        'Currency',
                        'Percent',
                      }.contains(c.fieldtype),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The sheet's drag handle. Over an image it gets a dark backing so it stays
/// visible on light and dark photos alike.
class _SheetHandle extends StatelessWidget {
  final bool onImage;
  const _SheetHandle({this.onImage = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: 36,
        height: 5,
        decoration: BoxDecoration(
          color: onImage ? Colors.white : cs.onSurfaceVariant,
          borderRadius: BorderRadius.circular(3),
          border: onImage
              ? Border.all(color: Colors.black54, width: 0.5)
              : null,
          boxShadow: onImage
              ? const [BoxShadow(color: Colors.black45, blurRadius: 4)]
              : null,
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? dot;
  final bool numeric;

  const _DetailLine({
    required this.label,
    required this.value,
    this.dot,
    this.numeric = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Row(
              children: [
                if (dot != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: numeric ? TextAlign.end : TextAlign.start,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
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
  final VoidCallback? onRetry;

  const _EmptyState({
    required this.icon,
    required this.message,
    this.onFilters,
    this.onRetry,
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
            if (onFilters != null || onRetry != null) ...[
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                children: [
                  if (onFilters != null)
                    FilledButton.tonalIcon(
                      onPressed: onFilters,
                      icon: const Icon(Icons.filter_alt_outlined),
                      label: const Text('Set Filters'),
                    ),
                  if (onRetry != null)
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('Retry'),
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
