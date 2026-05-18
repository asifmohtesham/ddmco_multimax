import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
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
    final cs = Theme.of(context).colorScheme;

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

    final chips = <Widget>[];
    controller.activeFilters.forEach((key, label) {
      chips.add(chip(key, label));
    });
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
          onRefresh: controller.runReport,
          color: cs.primary,
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
                          Icon(Icons.style_outlined,
                              size: 64, color: cs.outlineVariant),
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

// ── Variant tile ──────────────────────────────────────────────────────────────

class _VariantTile extends StatelessWidget {
  final Map<String, dynamic>             row;
  final List<Map<String, dynamic>>       columns;
  final ItemVariantDetailsController     controller;

  const _VariantTile({
    required this.row,
    required this.columns,
    required this.controller,
  });

  static const _skipFields = {'item', 'item_name', 'variant_of'};

  // ── Attribute → icon mapping ───────────────────────────────────────────────
  static IconData _iconForLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('colour') || l.contains('color')) return Icons.palette_outlined;
    if (l.contains('size'))                           return Icons.straighten;
    if (l.contains('material') || l.contains('leather') || l.contains('faux')) {
      return Icons.texture;
    }
    if (l.contains('zip'))                            return Icons.lock_outline;
    if (l.contains('coin'))                           return Icons.toll;
    if (l.contains('loop'))                           return Icons.loop;
    if (l.contains('pocket'))                         return Icons.account_balance_wallet_outlined;
    if (l.contains('card') || l.contains('slot'))     return Icons.credit_card_outlined;
    if (l.contains('stitch') || l.contains('sewing')) return Icons.waves;
    if (l.contains('buckle'))                         return Icons.panorama_fish_eye;
    if (l.contains('snap'))                           return Icons.adjust;
    if (l.contains('lining'))                         return Icons.layers_outlined;
    if (l.contains('compartment'))                    return Icons.inbox_outlined;
    if (l.contains('gusset') || l.contains('expand')) return Icons.open_in_full;
    if (l.contains('strap') || l.contains('belt'))    return Icons.horizontal_rule;
    if (l.contains('magnet'))                         return Icons.settings_input_component_outlined;
    if (l.contains('clasp') || l.contains('hook'))    return Icons.lock_clock_outlined;
    if (l.contains('rfid') || l.contains('blocking')) return Icons.shield_outlined;
    if (l.contains('weight'))                         return Icons.monitor_weight_outlined;
    if (l.contains('dimension') || l.contains('length') || l.contains('width') || l.contains('height')) {
      return Icons.straighten;
    }
    return Icons.label_outlined;
  }

  // Truthy "yes" values from ERPNext (Select "Yes", Check 1, etc.)
  static bool _isBoolTrue(dynamic v) {
    if (v == null) return false;
    final s = v.toString().toLowerCase().trim();
    return s == 'yes' || s == '1' || s == 'true';
  }

  // Values that should not render a chip at all
  static bool _isEmpty(dynamic v) {
    if (v == null) return true;
    final s = v.toString().trim();
    return s.isEmpty || s == '—' || s == '-';
  }

  static bool _isBoolFalse(dynamic v) {
    if (v == null) return true;
    final s = v.toString().toLowerCase().trim();
    return s == 'no' || s == '0' || s == 'false';
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

    final itemCode = row['item']?.toString()      ?? '—';
    final itemName = row['item_name']?.toString() ?? '';

    final attrCols = columns
        .where((c) => !_skipFields.contains(c['fieldname'] as String? ?? ''))
        .toList();

    return Obx(() {
      final imageUrl   = _imageUrl(controller.itemImages[itemCode]);
      final stockRows  = controller.stockBalances[itemCode];
      final isStockLoading = controller.loadingStock[itemCode] == true;
      final isExpanded = stockRows != null;

      return Card(
        elevation: 1,
        shadowColor: cs.shadow.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Get.toNamed(
            AppRoutes.ITEM_FORM,
            arguments: {'name': itemCode},
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header: image + codes ──────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ItemThumb(imageUrl: imageUrl, itemCode: itemCode),
                    const SizedBox(width: 12),
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
                          if (itemName.isNotEmpty && itemName != itemCode)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                itemName,
                                style: text.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant),
                                maxLines: 2,
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

                // ── Attribute chips ────────────────────────────────────────
                if (attrCols.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing:    6,
                    runSpacing: 6,
                    children: [
                      for (final col in attrCols) ...[
                        Builder(builder: (context) {
                          final fieldname = col['fieldname'] as String? ?? '';
                          final label     = col['label']     as String? ?? fieldname;
                          final val       = row[fieldname];
                          if (_isEmpty(val) || _isBoolFalse(val)) {
                            return const SizedBox.shrink();
                          }
                          final icon    = _iconForLabel(label);
                          final isBool  = _isBoolTrue(val);
                          return _AttrChip(
                            icon:    icon,
                            value:   isBool ? null : val.toString(),
                            tooltip: label,
                          );
                        }),
                      ],
                    ],
                  ),
                ],

                // ── Stock balance button ───────────────────────────────────
                const SizedBox(height: 10),
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
                            size: 16),
                    label: Text(isExpanded ? 'Hide Stock' : 'Check Stock'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.primary,
                      side: BorderSide(
                          color: cs.primary.withValues(alpha: 0.4)),
                      visualDensity: VisualDensity.compact,
                      textStyle: text.labelSmall,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                ),

                // ── Stock rows ─────────────────────────────────────────────
                if (isExpanded) ...[
                  const SizedBox(height: 8),
                  if (stockRows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'No stock in any warehouse.',
                        style: text.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    )
                  else
                    for (final r in stockRows)
                      _StockRow(
                        warehouse: r['warehouse']?.toString() ?? '—',
                        qty: (r['actual_qty'] as num?)
                                ?.toStringAsFixed(0) ??
                            '0',
                      ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }
}

// ── Item thumbnail ─────────────────────────────────────────────────────────────

class _ItemThumb extends StatelessWidget {
  final String? imageUrl;
  final String  itemCode;
  const _ItemThumb({this.imageUrl, required this.itemCode});

  static const _size = 54.0;

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final initials = itemCode.length >= 2
        ? itemCode.substring(0, 2).toUpperCase()
        : itemCode.toUpperCase();

    final fallback = Container(
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

    if (imageUrl == null) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        imageUrl!,
        width:  _size,
        height: _size,
        fit:    BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : Container(
                width: _size, height: _size,
                color: cs.surfaceContainerHighest,
                child: const Center(
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
      ),
    );
  }
}

// ── Attribute chip ─────────────────────────────────────────────────────────────

class _AttrChip extends StatelessWidget {
  final IconData icon;
  final String?  value;   // null → boolean (icon-only chip)
  final String   tooltip;
  const _AttrChip({required this.icon, this.value, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color:        cs.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: cs.onSecondaryContainer),
            if (value != null) ...[
              const SizedBox(width: 4),
              Text(
                value!,
                style: text.labelSmall?.copyWith(
                  color:      cs.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Stock row ──────────────────────────────────────────────────────────────────

class _StockRow extends StatelessWidget {
  final String warehouse;
  final String qty;
  const _StockRow({required this.warehouse, required this.qty});

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.warehouse, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              warehouse,
              style:    text.bodySmall?.copyWith(color: cs.onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$qty pcs',
            style: text.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color:      cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}
