import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_search/bom_search_controller.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_anchor.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_sheet.dart';

class BomSearchScreen extends GetView<BomSearchController> {
  const BomSearchScreen({super.key});

  // ── Filter field descriptors ───────────────────────────────────────────────────
  //
  // FocusNodes come from the controller so DataWedge knows which slot to
  // write into. Cannot be static const because FocusNode is a runtime object.

  List<ReportFilterField> get _fields => [
    ReportFilterField(
      key: 'item1',
      label: 'Item Code 1 *',
      prefixIcon: Icons.looks_one_outlined,
      required: true,
      focusNode: controller.item1Focus,
    ),
    ReportFilterField(
      key: 'item2',
      label: 'Item Code 2',
      prefixIcon: Icons.looks_two_outlined,
      focusNode: controller.item2Focus,
    ),
    ReportFilterField(
      key: 'item3',
      label: 'Item Code 3',
      prefixIcon: Icons.looks_3_outlined,
      focusNode: controller.item3Focus,
    ),
    ReportFilterField(
      key: 'item4',
      label: 'Item Code 4',
      prefixIcon: Icons.looks_4_outlined,
      focusNode: controller.item4Focus,
    ),
    ReportFilterField(
      key: 'item5',
      label: 'Item Code 5',
      prefixIcon: Icons.looks_5_outlined,
      focusNode: controller.item5Focus,
    ),
  ];

  static const _sectionLabels = <String, String>{};

  // ── Filter chip builder ────────────────────────────────────────────────

  /// [focusKey] opens the sheet on that filter, ready to edit.
  void _openFilters(BuildContext context, {String? focusKey}) =>
      showReportFilterSheet(
        context: context,
        focusKey: focusKey,
        title: 'BOM Search Filters',
        fields: _fields,
        controllers: controller.filterControllers,
        onRun: controller.runReport,
        runBusy: controller.isLoading,
        onClear: controller.clearFilters,
        sectionLabels: _sectionLabels,
      );

  List<Widget> _buildFilterChips(BuildContext context) {
    // Routes through the shared FilterChipWidget so chip styling stays uniform
    // across every list and report screen.
    final chips = <Widget>[];
    controller.activeFilters.forEach((key, label) {
      chips.add(
        FilterChipWidget(
          icon: Icons.filter_alt_outlined,
          label: label,
          onDeleted: () => controller.clearFilter(key),
          onTap: () => _openFilters(context, focusKey: key),
        ),
      );
    });
    return chips;
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppShellScaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: Obx(() {
        final rows = controller.reportData.toList(growable: false);
        final fields = controller.fields.state.value;
        final typesByParent = <String, Set<String>>{};
        final ids = [
          for (final (index, row) in rows.indexed)
            (row['doctype']?.toString(), row['parent']?.toString(), index),
        ];
        for (final row in rows) {
          final parent = row['parent']?.toString() ?? '';
          if (parent.isEmpty) continue;
          typesByParent
              .putIfAbsent(parent, () => {})
              .add(row['doctype']?.toString() ?? '');
        }
        return ReportFieldsResults(
          controller: controller.fields,
          scrollController: controller.scrollController,
          result: controller.resultRevision.value,
          occurrenceIds: ids,
          builder: (_, anchors) => Obx(
            () => RefreshIndicator(
              onRefresh: controller.runReport,
              color: cs.primary,
              backgroundColor: cs.surfaceContainerHighest,
              child: CustomScrollView(
                controller: controller.scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ── Unified header ────────────────────────────────────────────────
                  anchors.header(
                    DocTypeListHeader(
                      title: 'BOM Search',
                      automaticallyImplyLeading: false,
                      activeFilters: controller.activeFilters
                          .map((k, v) => MapEntry(k, v as dynamic))
                          .obs,
                      onFilterTap: () => _openFilters(context),
                      filterChipsBuilder: _buildFilterChips,
                      onClearAllFilters: controller.clearFilters,
                      extraActions: [
                        ReportFieldsAction(controller: controller.fields),
                      ],
                    ),
                  ),

                  // ── Results ────────────────────────────────────────────────────────
                  if (controller.isLoading.value)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (rows.isEmpty)
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
                                controller.errorMessage.value ??
                                    (controller.hasResult.value
                                        ? 'No BOMs found for the selected items.'
                                        : 'Set Item Code 1 and tap Run Report'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                              const SizedBox(height: 24),
                              FilledButton.tonalIcon(
                                onPressed: controller.errorMessage.value == null
                                    ? () => _openFilters(context)
                                    : controller.runReport,
                                icon: const Icon(Icons.filter_alt_outlined),
                                label: Text(
                                  controller.errorMessage.value == null
                                      ? 'Set Filters'
                                      : 'Retry',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final row = rows[index];
                          final parent = row['parent']?.toString() ?? '';
                          final protectType =
                              parent.isEmpty ||
                              row['doctype'] != 'BOM' ||
                              (typesByParent[parent]?.length ?? 0) > 1;
                          return anchors.row(
                            ids[index],
                            index,
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _BomSearchTile(
                                row: row,
                                showType:
                                    protectType || fields.shows('doctype'),
                                parentLabel: fields.label('parent')!,
                                typeLabel: fields.label('doctype')!,
                              ),
                            ),
                          );
                        }, childCount: rows.length),
                      ),
                    ),
                  if (controller.hasResult.value && rows.isNotEmpty)
                    SliverToBoxAdapter(
                      child: ListEndFooter(
                        hasMore: false,
                        bottomPadding: MediaQuery.paddingOf(context).bottom,
                        label:
                            'End of list · ${rows.length} result${rows.length == 1 ? '' : 's'}',
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ── Result tile ──────────────────────────────────────────────────────────────────

/// Displays a single row from the BOM Search report.
///
/// The Frappe query_report.run response for this report returns rows with:
///   - `parent`  – the BOM document name  (e.g. "BOM-3000015-001")
///   - `doctype` – the document kind for the Dynamic Link
class _BomSearchTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool showType;
  final String parentLabel;
  final String typeLabel;
  const _BomSearchTile({
    required this.row,
    required this.showType,
    required this.parentLabel,
    required this.typeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final parent = row['parent']?.toString() ?? '';
    final bom = parent.isEmpty ? '—' : parent;
    final doctype = row['doctype']?.toString() ?? '';

    return Material(
      color: cs.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Get.toNamed(AppRoutes.BOM_FORM, arguments: {'name': bom}),
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
                      semanticsLabel: '$parentLabel $bom',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (showType && doctype.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        doctype,
                        semanticsLabel: '$typeLabel $doctype',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }
}
