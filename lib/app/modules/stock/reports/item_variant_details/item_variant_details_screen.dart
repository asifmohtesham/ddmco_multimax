import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
              // ── Unified header ─────────────────────────────────────────────
              DocTypeListHeader(
                title:                    'Item Variant Details',
                automaticallyImplyLeading: false,
                activeFilters: controller.activeFilters
                    .map((k, v) => MapEntry(k, v as dynamic))
                    .obs,
                onFilterTap: () => showReportFilterSheet(
                  context:     context,
                  title:       'Item Variant Details Filters',
                  fields:      _fields,
                  controllers: controller.filterControllers,
                  onRun:       controller.runReport,
                  onClear:     controller.clearFilters,
                ),
                filterChipsBuilder: _buildFilterChips,
                onClearAllFilters:  controller.clearFilters,
              ),

              // ── Results ────────────────────────────────────────────────────
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
                            Icons.style_outlined,
                            size: 64,
                            color: cs.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Enter an Item and tap Run Report',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.tonalIcon(
                            onPressed: () => showReportFilterSheet(
                              context:     context,
                              title:       'Item Variant Details Filters',
                              fields:      _fields,
                              controllers: controller.filterControllers,
                              onRun:       controller.runReport,
                              onClear:     controller.clearFilters,
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
                          child: _VariantTile(
                            row:     row,
                            columns: controller.reportColumns,
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

// ── Result tile ───────────────────────────────────────────────────────────────

class _VariantTile extends StatelessWidget {
  final Map<String, dynamic>       row;
  final List<Map<String, dynamic>> columns;

  const _VariantTile({required this.row, required this.columns});

  static const _skipFields = {'item', 'item_name', 'variant_of'};

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final itemCode = row['item']?.toString()      ?? '—';
    final itemName = row['item_name']?.toString() ?? '';

    final attrColumns = columns
        .where((c) => !_skipFields.contains(c['fieldname'] as String? ?? ''))
        .toList();

    return Material(
      color: cs.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Get.toNamed(
          AppRoutes.ITEM_FORM,
          arguments: {'name': itemCode},
        ),
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
                          itemCode,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (itemName.isNotEmpty && itemName != itemCode)
                          Text(
                            itemName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: cs.outlineVariant),
                ],
              ),
              if (attrColumns.isNotEmpty) ...[
                const Divider(height: 20),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: attrColumns.map((col) {
                    final fieldname = col['fieldname'] as String? ?? '';
                    final label     = col['label']     as String? ?? fieldname;
                    return _Detail(label: label, value: row[fieldname]);
                  }).toList(),
                ),
              ],
            ],
          ),
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
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          value?.toString().isNotEmpty == true ? value.toString() : '—',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
