import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_controller.dart';

class ItemVariantDetailsScreen extends GetView<ItemVariantDetailsController> {
  const ItemVariantDetailsScreen({super.key});

  // ── Filter field descriptors ───────────────────────────────────────────────
  List<ReportFilterField> get _fields => [
    const ReportFilterField(
      key:         'item_code',
      label:       'Item *',
      type:        ReportFilterType.doctypeLink,
      linkDoctype: 'Item',
      prefixIcon:  Icons.category_outlined,
      required:    true,
      linkFilters: {'disabled': 0, 'has_variants': 1},
    ),
  ];

  // ── Filter chip builder ────────────────────────────────────────────────────
  List<Widget> _buildFilterChips(BuildContext context) {
    // Routes through the shared FilterChipWidget so chip styling stays uniform
    // across every list and report screen.
    final chips = <Widget>[];
    controller.activeFilters.forEach((key, label) => chips.add(FilterChipWidget(
          icon: Icons.filter_alt_outlined,
          label: label,
          onDeleted: () => controller.clearFilter(key),
        )));
    return chips;
  }

  void _openFilters(BuildContext context) => showReportFilterSheet(
    context:     context,
    title:       'Item Variant Details Filters',
    fields:      _fields,
    controllers: controller.filterControllers,
    onRun:       controller.runReport,
    onClear:     controller.clearFilters,
  );

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppShellScaffold(
      body: Obx(() {
        return RefreshIndicator(
          onRefresh:       controller.runReport,
          color:           cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              DocTypeListHeader(
                title:                     'Item Variant Details',
                automaticallyImplyLeading: false,
                activeFilters: controller.activeFilters
                    .map((k, v) => MapEntry(k, v as dynamic))
                    .obs,
                onFilterTap:        () => _openFilters(context),
                filterChipsBuilder: _buildFilterChips,
                onClearAllFilters:  controller.clearFilters,
              ),

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
                          Icon(Icons.style_outlined, size: 64, color: cs.outlineVariant),
                          const SizedBox(height: 16),
                          Text(
                            'Enter an Item and tap Run Report',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.tonalIcon(
                            onPressed: () => _openFilters(context),
                            icon:  const Icon(Icons.filter_alt_outlined),
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
                          child: _VariantTile(
                            row:        row,
                            columns:    controller.reportColumns,
                            controller: controller,
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

// ── Image gallery viewer ──────────────────────────────────────────────────────

void _openImageViewer(
  BuildContext context, {
  required List<_GalleryItem> items,
  required int                initialIndex,
}) {
  // showGeneralDialog fills the whole screen; showDialog constrains content
  // through DialogRoute's centering + width logic, which produces a box.
  showGeneralDialog<void>(
    context:            context,
    barrierDismissible: true,
    barrierLabel:       '',
    barrierColor:       Colors.black87,
    transitionDuration: const Duration(milliseconds: 150),
    transitionBuilder:  (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
    pageBuilder: (ctx, _, __) => _ImageGallery(
      items:        items,
      initialIndex: initialIndex,
    ),
  );
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

  // Non-attribute report columns that must not render as attribute chips
  static const _skipFields = {
    'variant_name', 'item', 'item_name', 'variant_of',
    'current_stock', 'in_production', 'open_orders',
    'avg_buying_price_list_rate', 'avg_selling_price_list_rate',
  };

  static bool _isEmpty(dynamic v) {
    if (v == null) return true;
    final s = v.toString().trim();
    return s.isEmpty || s == '—' || s == '-';
  }

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

    final attrCols = columns
        .where((c) => !_skipFields.contains(c['fieldname'] as String? ?? ''))
        .toList();

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
                  for (final r in controller.reportData) {
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
                  if (attrCols.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: [
                        for (final col in attrCols)
                          Builder(builder: (ctx) {
                            final fieldname = col['fieldname'] as String? ?? '';
                            final label     = col['label']     as String? ?? fieldname;
                            final val       = row[fieldname];
                            if (_isEmpty(val)) return const SizedBox.shrink();
                            return _AttrChip(label: label, value: val.toString());
                          }),
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
                      label: Text(isExpanded ? 'Hide Stock' : 'Check Stock'),
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

  Color _qtyColor(ColorScheme cs) {
    if (qty < 0) return cs.error;
    if (qty == 0) return cs.onSurfaceVariant;
    return const Color(0xFF2E7D32); // green.shade800 — accessible on white
  }

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final text  = Theme.of(context).textTheme;
    final color = _qtyColor(cs);

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
  final int                initialIndex;
  const _ImageGallery({required this.items, required this.initialIndex});

  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  late final PageController _page;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _page    = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad    = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final total     = widget.items.length;
    final item      = widget.items[_current];

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Swipeable image pages ──────────────────────────────────
        PageView.builder(
          controller:    _page,
          itemCount:     total,
          onPageChanged: (i) => setState(() => _current = i),
          itemBuilder:   (_, i) {
            // ValueKey forces InteractiveViewer to reset its transform
            // (zoom + pan) when the user swipes to a new page.
            return InteractiveViewer(
              key:      ValueKey(i),
              minScale: 0.5,
              maxScale: 8.0,
              child: Center(
                child: Image.network(
                  widget.items[i].url,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, prog) => prog == null
                      ? child
                      : const Center(
                          child: CircularProgressIndicator(
                              color: Colors.white)),
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined,
                        size: 64, color: Colors.white54),
                  ),
                ),
              ),
            );
          },
        ),

        // ── Top bar: counter + close ───────────────────────────────
        Positioned(
          top: topPad + 8, left: 0, right: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _pill('${_current + 1} / $total'),
                const Spacer(),
                IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    minimumSize:     const Size(48, 48),
                  ),
                  icon:      const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),

        // ── Bottom caption: item code + name + dots ────────────────
        Positioned(
          bottom: bottomPad + 16, left: 16, right: 16,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(
              color:        Colors.black54,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize:      MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemCode,
                  style: const TextStyle(
                    color:      Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize:   15,
                  ),
                ),
                if (item.itemName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.itemName,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (total > 1) ...[
                  const SizedBox(height: 10),
                  _PageDots(current: _current, total: total),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color:        Colors.black54,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 13),
    ),
  );
}

// ── Page dot indicator ─────────────────────────────────────────────────────────

class _PageDots extends StatelessWidget {
  final int current;
  final int total;
  const _PageDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    // Show dots only when there are few enough to display clearly;
    // the "N / total" counter in the top pill handles the rest.
    if (total > 9) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve:    Curves.easeOut,
          width:    active ? 20 : 6,
          height:   6,
          margin:   const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color:        active ? Colors.white : Colors.white38,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
