import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_search/bom_search_controller.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';

class BomSearchScreen extends GetView<BomSearchController> {
  const BomSearchScreen({super.key});

  // ── Filter field descriptors ────────────────────────────────────────────────
  //
  // FocusNodes come from the controller so DataWedge knows which slot to
  // write into. Cannot be static const because FocusNode is a runtime object.

  List<ReportFilterField> get _fields => [
    ReportFilterField(
      key:        'item1',
      label:      'Item Code 1 *',
      prefixIcon: Icons.looks_one_outlined,
      required:   true,
      focusNode:  controller.item1Focus,
    ),
    ReportFilterField(
      key:        'item2',
      label:      'Item Code 2',
      prefixIcon: Icons.looks_two_outlined,
      focusNode:  controller.item2Focus,
    ),
    ReportFilterField(
      key:        'item3',
      label:      'Item Code 3',
      prefixIcon: Icons.looks_3_outlined,
      focusNode:  controller.item3Focus,
    ),
    ReportFilterField(
      key:        'item4',
      label:      'Item Code 4',
      prefixIcon: Icons.looks_4_outlined,
      focusNode:  controller.item4Focus,
    ),
    ReportFilterField(
      key:        'item5',
      label:      'Item Code 5',
      prefixIcon: Icons.looks_5_outlined,
      focusNode:  controller.item5Focus,
    ),
  ];

  static const _sectionLabels = <String, String>{};

  // ── Filter chip builder ────────────────────────────────────────────

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

  // ── Build ───────────────────────────────────────────────────────────────────

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
              // ── Unified header ─────────────────────────────────────────
              DocTypeListHeader(
                title: 'BOM Search',
                activeFilters: controller.activeFilters
                    .map((k, v) => MapEntry(k, v as dynamic))
                    .obs,
                onFilterTap: () => showReportFilterSheet(
                  context:       context,
                  title:         'BOM Search Filters',
                  fields:        _fields,
                  controllers:   controller.filterControllers,
                  onRun:         controller.runReport,
                  onClear:       controller.clearFilters,
                  sectionLabels: _sectionLabels,
                ),
                filterChipsBuilder: _buildFilterChips,
                onClearAllFilters:  controller.clearFilters,
              ),

              // ── Results ───────────────────────────────────────────────
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
                            Icons.account_tree_outlined,
                            size: 64,
                            color: cs.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Set Item Code 1 and tap Run Report',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.tonalIcon(
                            onPressed: () => showReportFilterSheet(
                              context:       context,
                              title:         'BOM Search Filters',
                              fields:        _fields,
                              controllers:   controller.filterControllers,
                              onRun:         controller.runReport,
                              onClear:       controller.clearFilters,
                              sectionLabels: _sectionLabels,
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
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final row = controller.reportData[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _BomSearchTile(row: row),
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

class _BomSearchTile extends StatelessWidget {
  final Map<String, dynamic> row;
  const _BomSearchTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final isDefault = _truthy(row['is_default']);
    final isActive  = _truthy(row['is_active']);

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
              children: [
                Expanded(
                  child: Text(
                    row['name']?.toString() ??
                        row['bom_no']?.toString() ??
                        '—',
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700),
                  ),
                ),
                if (isDefault)
                  _Badge(
                      label: 'Default',
                      bg: cs.primaryContainer,
                      fg: cs.onPrimaryContainer),
                if (isDefault && isActive) const SizedBox(width: 6),
                if (isActive)
                  _Badge(
                      label: 'Active',
                      bg: cs.tertiaryContainer,
                      fg: cs.onTertiaryContainer),
              ],
            ),
            const SizedBox(height: 8),
            if ((row['item']?.toString() ?? '').isNotEmpty)
              _Detail(
                icon: Icons.inventory_2_outlined,
                label: row['item_name']?.toString() ??
                    row['item']?.toString() ??
                    '',
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                _Detail(
                  icon: Icons.numbers_outlined,
                  label:
                      'Qty: ${row['quantity']?.toString() ?? row['qty']?.toString() ?? '—'}'
                      '${(row['uom']?.toString() ?? '').isNotEmpty ? ' ${row['uom']}' : ''}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _truthy(dynamic val) {
    if (val == null) return false;
    if (val is bool) return val;
    if (val is num) return val != 0;
    return val.toString() == '1' || val.toString().toLowerCase() == 'true';
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color  bg;
  final Color  fg;
  const _Badge({
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _Detail({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: cs.onSurface),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
