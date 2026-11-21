import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/item_image.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_controller.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_logic.dart';

class ItemVariantDetailsScreen extends GetView<ItemVariantDetailsController> {
  const ItemVariantDetailsScreen({super.key});

  static const filterFields = [
    ReportFilterField(
      key: 'item',
      label: 'Items',
      type: ReportFilterType.doctypeMultiLink,
      linkDoctype: 'Item',
      prefixIcon: Icons.category_outlined,
      linkFilters: {'has_variants': 1},
    ),
    ReportFilterField(
      key: 'item_group',
      label: 'Item Groups',
      type: ReportFilterType.doctypeMultiLink,
      linkDoctype: 'Item Group',
      prefixIcon: Icons.account_tree_outlined,
    ),
    ReportFilterField(
      key: 'warehouse',
      label: 'Warehouses',
      type: ReportFilterType.doctypeMultiLink,
      linkDoctype: 'Warehouse',
      prefixIcon: Icons.warehouse_outlined,
    ),
  ];

  List<Widget> _buildFilterChips(BuildContext context) {
    if (controller.isLoading.value) return [];
    return [
      for (final entry in controller.activeFilters.entries)
        FilterChipWidget(
          icon: Icons.filter_alt_outlined,
          label: entry.value,
          onDeleted: () => controller.clearFilter(entry.key),
          onTap: () => _openFilters(context, focusKey: entry.key),
        ),
    ];
  }

  void _openFilters(BuildContext context, {String? focusKey}) {
    if (controller.isLoading.value) return;
    showReportFilterSheet(
      context: context,
      focusKey: focusKey,
      title: 'Item Variant Details Filters',
      fields: filterFields,
      controllers: controller.filterControllers,
      onRun: controller.runReport,
      onClear: controller.clearFilters,
      validate: controller.validateFilters,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return AppShellScaffold(
      body: Obx(() {
        final busy = controller.isLoading.value;
        return RefreshIndicator(
          onRefresh: controller.runReport,
          color: cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
          child: Scrollbar(
            interactive: true,
            thumbVisibility: !busy && controller.reportData.isNotEmpty,
            controller: controller.scrollController,
            child: CustomScrollView(
              controller: controller.scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                DocTypeListHeader(
                  title: 'Item Variant Details',
                  automaticallyImplyLeading: false,
                  activeFilters: <String, dynamic>{
                    if (!busy) ...controller.activeFilters,
                  }.obs,
                  onFilterTap: busy ? null : () => _openFilters(context),
                  filterChipsBuilder: _buildFilterChips,
                  onClearAllFilters: busy ? null : controller.clearFilters,
                ),

                if (busy)
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
                              Icons.style_outlined,
                              size: 64,
                              color: cs.outlineVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              controller.reportError.value ??
                                  (controller.hasRun.value
                                      ? 'No variants match these filters.'
                                      : 'Select Items or Item Groups, then run the report.'),
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
                    // Keep card taps outside the scrollbar thumb's touch target.
                    padding: EdgeInsets.fromLTRB(12, 4, 32, 80 + bottomPadding),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        if (index == controller.reportData.length) {
                          final summary = variantQuantitySummary(
                            controller.reportData,
                            controller.reportColumns,
                          );
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              ['End of list', ...summary].join('\n'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          );
                        }
                        final row = controller.reportData[index];
                        // v16.55 heads each template's variants with a
                        // subtotal row; it is a heading, not a variant.
                        if (isTemplateRow(row)) {
                          return _TemplateHeader(
                            row: row,
                            columns: controller.reportColumns,
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _VariantTile(
                            row: row,
                            columns: controller.reportColumns,
                            controller: controller,
                          ),
                        );
                      }, childCount: controller.reportData.length + 1),
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ── Image gallery viewer ──────────────────────────────────────────────────────

void _openImageViewer(
  BuildContext context, {
  required List<_GalleryItem> items,
  required int initialIndex,
}) {
  showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (_) => _ImageGallery(
      items: items,
      initialIndex: initialIndex,
    ),
  );
}

// ── Template heading ──────────────────────────────────────────────────────────

/// The subtotal row ERPNext v16.55 puts above each template's variants:
/// the template's code and Item Group, and the totals the report gives it,
/// under the report's own column labels.
class _TemplateHeader extends StatelessWidget {
  final Map<String, dynamic>       row;
  final List<Map<String, dynamic>> columns;

  const _TemplateHeader({required this.row, required this.columns});

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final code      = row['variant_name']?.toString() ?? '';
    final itemGroup = row['item_group']?.toString() ?? '';
    final totals    = templateTotals(row, columns);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            code,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (itemGroup.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                itemGroup,
                style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          if (totals.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 14, runSpacing: 4,
                children: [
                  for (final t in totals)
                    Text.rich(
                      TextSpan(
                        text: '${t.label}  ',
                        style: text.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                        children: [
                          TextSpan(
                            text: t.value,
                            style: text.labelMedium?.copyWith(
                              color:      cs.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Variant tile ──────────────────────────────────────────────────────────────

class _VariantTile extends StatelessWidget {
  final Map<String, dynamic>         row;
  final List<Map<String, dynamic>>   columns;
  final ItemVariantDetailsController controller;

  const _VariantTile({
    required this.row,
    required this.columns,
    required this.controller,
  });

  String? _imageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    return '${Get.find<ApiProvider>().baseUrl}$path';
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final itemCode = row['variant_name']?.toString()
        ?? row['item']?.toString()
        ?? '—';

    final chips = variantChips(row, columns).toList();

    return Obx(() {
      final details        = controller.itemDetails[itemCode];
      final itemName       = details?['item_name']  as String? ?? '';
      final itemGroup      = details?['item_group'] as String? ?? '';
      final imageUrl       = _imageUrl(details?['image'] as String?);
      final stockRows      = controller.stockBalances[itemCode];
      final isStockLoading = controller.loadingStock[itemCode] == true;
      final isExpanded     = stockRows != null;

      return Card(
        elevation:       1,
        shadowColor:     cs.shadow.withValues(alpha: 0.12),
        clipBehavior:    Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Full-width image banner (tap to open gallery) ──────
            if (imageUrl != null)
              InkWell(
                onTap: () {
                  // Collect all variant images in report order so the gallery
                  // can slide between items; open at the tapped item's index.
                  final items       = <_GalleryItem>[];
                  var   startIndex  = 0;
                  for (final r in variantRowsOf(controller.reportData)) {
                    final code = r['variant_name']?.toString()
                        ?? r['item']?.toString() ?? '';
                    final url  = _imageUrl(
                        controller.itemDetails[code]?['image'] as String?);
                    if (url == null) continue;
                    if (code == itemCode) startIndex = items.length;
                    items.add(_GalleryItem(
                      url:      url,
                      itemCode: code,
                      itemName: controller.itemDetails[code]?['item_name']
                              as String? ?? '',
                    ));
                  }
                  if (items.isEmpty) return;
                  _openImageViewer(
                    context,
                    items:        items,
                    initialIndex: startIndex,
                  );
                },
                child: _ImageBanner(imageUrl: imageUrl),
              ),

            // ── Content ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header row (tappable → item form) ──────────
                  InkWell(
                    onTap: () => Get.toNamed(
                      AppRoutes.ITEM_FORM,
                      arguments: {'itemCode': itemCode},
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (imageUrl == null) ...[
                            _ItemThumb(itemCode: itemCode),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  itemCode,
                                  style: text.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (itemName.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      itemName,
                                      style: text.bodySmall?.copyWith(
                                          color: cs.onSurface),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                if (itemGroup.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 1),
                                    child: Text(
                                      itemGroup,
                                      style: text.labelSmall?.copyWith(
                                          color: cs.onSurfaceVariant),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              color: cs.outlineVariant, size: 18),
                        ],
                      ),
                    ),
                  ),

                  // ── Attribute chips ──────────────────────────────
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: [
                        for (final chip in chips)
                          _AttrChip(label: chip.label, value: chip.value),
                      ],
                    ),
                  ],

                  // ── Check Stock button ───────────────────────────
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isStockLoading
                          ? null
                          : () => controller.fetchStockBalance(itemCode),
                      icon: isStockLoading
                          ? SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: cs.primary),
                            )
                          : Icon(
                              isExpanded
                                  ? Icons.expand_less
                                  : Icons.inventory_2_outlined,
                              size: 16,
                            ),
                      label: Text(isExpanded ? 'Hide Stock' :
                          controller.activeFilters.containsKey('warehouse')
                              ? 'Check Stock Across Warehouses'
                              : 'Check Stock'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.primary,
                        side:  BorderSide(color: cs.primary.withValues(alpha: 0.4)),
                        visualDensity: VisualDensity.compact,
                        textStyle: text.labelSmall,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),

                  // ── Stock section ────────────────────────────────
                  if (isExpanded) _StockSection(rows: stockRows),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ── Full-width image banner ────────────────────────────────────────────────────

class _ImageBanner extends StatelessWidget {
  final String imageUrl;
  static const _height = 200.0;

  const _ImageBanner({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width:  double.infinity,
      height: _height,
      child: Image.network(
        imageUrl,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : ColoredBox(
                color: cs.surfaceContainerHighest,
                child: const Center(
                  child: SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
        errorBuilder: (_, __, ___) => ColoredBox(
          color: cs.surfaceContainerHighest,
          child: Center(
            child: Icon(Icons.broken_image_outlined,
                size: 48, color: cs.outlineVariant),
          ),
        ),
      ),
    );
  }
}

// ── Initials thumbnail (shown only when no image is available) ────────────────

class _ItemThumb extends StatelessWidget {
  final String itemCode;
  static const _size = 54.0;
  const _ItemThumb({required this.itemCode});

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final initials = itemCode.length >= 2
        ? itemCode.substring(0, 2).toUpperCase()
        : itemCode.toUpperCase();
    return Container(
      width: _size, height: _size,
      decoration: BoxDecoration(
        color:        cs.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color:      cs.onPrimaryContainer,
          fontWeight: FontWeight.w700,
          fontSize:   17,
        ),
      ),
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
        color:        cs.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $value',
        style: text.labelSmall?.copyWith(
          color:      cs.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Stock section (container + summary + rows) ────────────────────────────────

class _StockSection extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _StockSection({required this.rows});

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, left: 4),
        child: Text(
          'No stock in any rack.',
          style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    final totalQty = rows.fold<double>(
      0, (sum, r) => sum + ((r['qty'] as num?)?.toDouble() ?? 0),
    );

    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color:        cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(Icons.shelves, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '${rows.length} rack${rows.length != 1 ? 's' : ''}',
                  style: text.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                Text(
                  'Total  ${totalQty.toStringAsFixed(0)} pcs',
                  style: text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: totalQty > 0 ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1, thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
          // Per-rack rows
          ...rows.asMap().entries.map((entry) {
            final isLast = entry.key == rows.length - 1;
            final r      = entry.value;
            return Column(
              children: [
                _StockRow(
                  rack: r['rack']?.toString() ?? '—',
                  qty:  (r['qty'] as num?) ?? 0,
                ),
                if (!isLast)
                  Divider(
                    height: 1,
                    indent: 14, endIndent: 14,
                    color: cs.outlineVariant.withValues(alpha: 0.2),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ── Stock row ──────────────────────────────────────────────────────────────────

class _StockRow extends StatelessWidget {
  final String rack;
  final num    qty;
  const _StockRow({required this.rack, required this.qty});

  Color _qtyColor(ColorScheme cs, Brightness brightness) {
    if (qty < 0) return cs.error;
    if (qty == 0) return cs.onSurfaceVariant;
    // Status ramp: x700 on light surfaces, x300 on dark — a fixed dark
    // green is unreadable on the dark-mode tint.
    return brightness == Brightness.dark
        ? AppColors.green300
        : AppColors.green700;
  }

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final text  = Theme.of(context).textTheme;
    final color = _qtyColor(cs, Theme.of(context).brightness);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              rack,
              style: text.bodyMedium?.copyWith(color: cs.onSurface),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:        color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${qty.toStringAsFixed(0)} pcs',
              style: text.labelMedium?.copyWith(
                color:      color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Gallery data ───────────────────────────────────────────────────────────────

class _GalleryItem {
  final String url;
  final String itemCode;
  final String itemName;
  const _GalleryItem({
    required this.url,
    required this.itemCode,
    required this.itemName,
  });
}

// ── Full-screen image gallery ─────────────────────────────────────────────────

class _ImageGallery extends StatefulWidget {
  final List<_GalleryItem> items;
  final int initialIndex;
  const _ImageGallery({required this.items, required this.initialIndex});

  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  late int _current = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    final item = widget.items[_current];

    return ItemImagePreview(
      key: ValueKey(_current),
      url: item.url,
      title: [item.itemCode, item.itemName]
          .where((text) => text.isNotEmpty)
          .join(' · '),
      navigationActions: [
        if (total > 1) ...[
          IconButton(
            tooltip: 'Previous image',
            onPressed: _current == 0 ? null : () => setState(() => _current--),
            icon: const Icon(Icons.chevron_left),
          ),
          Text('${_current + 1} / $total'),
          IconButton(
            tooltip: 'Next image',
            onPressed: _current == total - 1
                ? null
                : () => setState(() => _current++),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ],
    );
  }
}
