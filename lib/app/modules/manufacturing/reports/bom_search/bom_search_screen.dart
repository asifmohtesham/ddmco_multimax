import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_search/bom_search_controller.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';

class BomSearchScreen extends GetView<BomSearchController> {
  const BomSearchScreen({super.key});

  // ── Filter field descriptors ─────────────────────────────────────────────────────────
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

  // ── Filter chip builder ────────────────────────────────────────────────────

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

  // ── Build ─────────────────────────────────────────────────────────────────────

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
              // ── Unified header ─────────────────────────────────────────────────────
              DocTypeListHeader(
                title:                    'BOM Search',
                automaticallyImplyLeading: false,
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

              // ── Results ────────────────────────────────────────────────────────────
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

// ── Result tile ──────────────────────────────────────────────────────────────────

/// Displays a single row from the BOM Search report.
///
/// The Frappe query_report.run response for this report returns exactly
/// two columns per row:
///   - `parent`  – the BOM document name  (e.g. "BOM-3000015-001")
///   - `doctype` – the linked DocType name (always "BOM")
class _BomSearchTile extends StatelessWidget {
  final Map<String, dynamic> row;
  const _BomSearchTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final bom     = row['parent']?.toString()  ?? '—';
    final doctype = row['doctype']?.toString() ?? '';

    return Material(
      color: cs.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // TODO: navigate to BOM form
          // Get.toNamed(Routes.BOM_FORM, arguments: bom);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.account_tree_outlined,
                  size: 20,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bom,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (doctype.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        doctype,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: cs.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
