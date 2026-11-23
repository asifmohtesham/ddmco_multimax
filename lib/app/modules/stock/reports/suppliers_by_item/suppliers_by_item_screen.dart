// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_binding.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_controller.dart';

class SuppliersByItemScreen extends StatefulWidget {
  const SuppliersByItemScreen({super.key});

  @override
  State<SuppliersByItemScreen> createState() => _SuppliersByItemScreenState();
}

class _SuppliersByItemScreenState extends State<SuppliersByItemScreen> {
  static const _filterFields = [
    ReportFilterField(
      key: 'items',
      label: 'Items',
      type: ReportFilterType.doctypeMultiLink,
      linkDoctype: 'Item',
      prefixIcon: Icons.category_outlined,
    ),
    ReportFilterField(
      key: 'variant_of',
      label: 'Variant Of',
      type: ReportFilterType.doctypeMultiLink,
      linkDoctype: 'Item',
      linkFilters: {'has_variants': 1},
      prefixIcon: Icons.account_tree_outlined,
    ),
    ReportFilterField(
      key: 'suppliers',
      label: 'Suppliers',
      type: ReportFilterType.doctypeMultiLink,
      linkDoctype: 'Supplier',
      prefixIcon: Icons.local_shipping_outlined,
    ),
    ReportFilterField(
      key: 'warehouses',
      label: 'Warehouses',
      type: ReportFilterType.doctypeMultiLink,
      linkDoctype: 'Warehouse',
      prefixIcon: Icons.warehouse_outlined,
    ),
    ReportFilterField(
      key: 'from_date',
      label: 'From Date',
      type: ReportFilterType.datePicker,
      prefixIcon: Icons.calendar_today_outlined,
    ),
    ReportFilterField(
      key: 'to_date',
      label: 'To Date',
      type: ReportFilterType.datePicker,
      prefixIcon: Icons.calendar_today_outlined,
    ),
  ];

  late final _controller = Get.find<SuppliersByItemController>(
    tag: SuppliersByItemBinding.tagForRoute(ModalRoute.of(context)),
  );
  final _scrollController = ScrollController();
  final _draft = {
    for (final field in _filterFields) field.key: TextEditingController(),
  };

  @override
  void dispose() {
    _scrollController.dispose();
    for (final input in _draft.values) {
      input.dispose();
    }
    super.dispose();
  }

  void _loadDraft() {
    final filters = _controller.filters.value.toJson();
    for (final entry in _draft.entries) {
      final value = filters[entry.key];
      entry.value.text = switch (value) {
        List<String>() => joinMultiValue(value),
        String() => value,
        _ => '',
      };
    }
  }

  SuppliersByItemFilters get _draftFilters => SuppliersByItemFilters(
    items: splitMultiValue(_draft['items']!.text),
    variantOf: splitMultiValue(_draft['variant_of']!.text),
    suppliers: splitMultiValue(_draft['suppliers']!.text),
    warehouses: splitMultiValue(_draft['warehouses']!.text),
    fromDate: DateTime.tryParse(_draft['from_date']!.text),
    toDate: DateTime.tryParse(_draft['to_date']!.text),
  );

  void _openFilters(BuildContext context, {String? focusKey}) {
    if (_controller.isLoading.value) return;
    _loadDraft();
    showReportFilterSheet(
      context: context,
      title: 'Suppliers by Item Filters',
      fields: _filterFields,
      controllers: _draft,
      focusKey: focusKey,
      onRun: () => _controller.run(filters: _draftFilters),
      runBusy: _controller.isLoading,
      onClear: _clearFilters,
      validate: () => _draftFilters.hasInvalidDateRange
          ? SuppliersByItemReportException.invalidDateRange
          : null,
    );
  }

  void _clearFilters() {
    _controller.run(filters: const SuppliersByItemFilters());
  }

  void _clearFilter(String key) {
    _loadDraft();
    _draft[key]!.clear();
    _controller.run(filters: _draftFilters);
  }

  List<Widget> _filterChips(BuildContext context) => [
    for (final field in _filterFields)
      if (_controller.activeFilters[field.key] case final value?)
        FilterChipWidget(
          icon: field.prefixIcon!,
          label: '${field.label} · $value',
          onTap: () => _openFilters(context, focusKey: field.key),
          onDeleted: () => _clearFilter(field.key),
        ),
  ];

  @override
  Widget build(BuildContext context) {
    final fromItem =
        ModalRoute.of(context)?.settings.arguments is SuppliersByItemFilters;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return AppShellScaffold(
      body: Obx(() {
        final loading = _controller.isLoading.value;
        final error = _controller.error.value;
        final nodes = _controller.nodes.toList();

        return RefreshIndicator(
          onRefresh: _controller.run,
          child: Scrollbar(
            controller: _scrollController,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                DocTypeListHeader(
                  title: 'Suppliers by Item',
                  automaticallyImplyLeading: fromItem,
                  activeFilters: _controller.activeFilters,
                  onFilterTap: () => _openFilters(context),
                  filterChipsBuilder: _filterChips,
                  onClearAllFilters: _clearFilters,
                  extraActions: [
                    AsyncIconButton(
                      busy: _controller.isLoading,
                      onPressed: _controller.run,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh report',
                      spinnerColor: Theme.of(context).colorScheme.onSurface,
                    ),
                  ],
                ),
                if (loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (error != null || nodes.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ReportState(
                      message: error ?? 'No suppliers recorded',
                      icon: error == null
                          ? Icons.inventory_2_outlined
                          : Icons.error_outline,
                      retry: error == null ? null : _controller,
                    ),
                  )
                else ...[
                  _SuppliersTree(nodes: nodes),
                  SliverToBoxAdapter(
                    child: _ReportFooter(
                      nodes: nodes,
                      bottomPadding: bottomPadding,
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
}

class _ReportState extends StatelessWidget {
  const _ReportState({required this.message, required this.icon, this.retry});

  final String message;
  final IconData icon;
  final SuppliersByItemController? retry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (retry case final controller?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: AsyncFilledButton(
                  busy: controller.isLoading,
                  onPressed: controller.run,
                  icon: const Icon(Icons.refresh),
                  label: 'Retry',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReportFooter extends StatelessWidget {
  const _ReportFooter({required this.nodes, required this.bottomPadding});

  final List<SuppliersByItemNode> nodes;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final totals = <String?, num>{};

    void addTotals(List<SuppliersByItemNode> nodes) {
      for (final node in nodes) {
        final row = node.row;
        if (row.totalQtyReceived case final quantity?
            when row.kind == SuppliersByItemRowKind.supplier) {
          totals.update(
            row.stockUom,
            (total) => total + quantity,
            ifAbsent: () => quantity,
          );
        }
        addTotals(node.children);
      }
    }

    addTotals(nodes);
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPadding + 16),
      child: Column(
        children: [
          Text('End of list', style: style),
          Text('Total qty received', style: style),
          if (totals.isEmpty) Text('0', style: style),
          for (final MapEntry(key: uom, value: quantity) in totals.entries)
            Text(
              [
                FormattingHelper.formatQtyGrouped(quantity.toDouble()),
                ?uom,
              ].join(' '),
              style: style,
            ),
        ],
      ),
    );
  }
}

class _SuppliersTree extends StatefulWidget {
  const _SuppliersTree({required this.nodes});

  final List<SuppliersByItemNode> nodes;

  @override
  State<_SuppliersTree> createState() => _SuppliersTreeState();
}

class _SuppliersTreeState extends State<_SuppliersTree> {
  final _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final visible = <({SuppliersByItemNode node, int depth})>[];

    void addVisible(List<SuppliersByItemNode> nodes, int depth) {
      for (final node in nodes) {
        visible.add((node: node, depth: depth));
        if (_expanded.contains(node.row.nodeId)) {
          addVisible(node.children, depth + 1);
        }
      }
    }

    addVisible(widget.nodes, 0);
    return SliverList.builder(
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final (node: node, depth: depth) = visible[index];
        final row = node.row;
        final expanded = _expanded.contains(row.nodeId);
        return Align(
          key: ValueKey(row.nodeId),
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                12.0 + depth * 16.0,
                0,
                12,
                6,
              ),
              child: row.kind == SuppliersByItemRowKind.supplier
                  ? _SupplierTile(row: row)
                  : _GroupTile(
                      row: row,
                      hasNoSupplier:
                          row.kind == SuppliersByItemRowKind.item &&
                          !node.hasSuppliers,
                      expanded: expanded,
                      onTap: node.children.isEmpty
                          ? null
                          : () => setState(() {
                              if (expanded) {
                                _expanded.remove(row.nodeId);
                              } else {
                                _expanded.add(row.nodeId);
                              }
                            }),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.row,
    required this.hasNoSupplier,
    required this.expanded,
    this.onTap,
  });

  final SuppliersByItemRow row;
  final bool hasNoSupplier;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final count = row.supplierCount;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surface,
      child: Semantics(
        expanded: onTap == null ? null : expanded,
        child: ListTile(
          onTap: onTap,
          leading: Icon(
            row.kind == SuppliersByItemRowKind.template
                ? Icons.account_tree_outlined
                : Icons.category_outlined,
          ),
          title: Text(row.itemName ?? row.treeLabel),
          subtitle: hasNoSupplier
              ? const Text('No supplier recorded')
              : count == null
              ? null
              : Text(count == 1 ? '1 supplier' : '$count suppliers'),
          trailing: onTap == null
              ? null
              : Icon(expanded ? Icons.expand_less : Icons.expand_more),
        ),
      ),
    );
  }
}

class _SupplierTile extends StatelessWidget {
  const _SupplierTile({required this.row});

  final SuppliersByItemRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quantity = row.totalQtyReceived;
    final rate = row.lastRate;
    final provenance = [?row.rateSource, ?row.rateDate].join(' ');

    final details = {
      'Part number': row.supplierPartNumber,
      'Last purchase': row.lastPurchaseDate,
      'Qty received': quantity == null
          ? null
          : [
              FormattingHelper.formatQtyGrouped(quantity.toDouble()),
              ?row.stockUom,
            ].join(' '),
      'Last PO': row.lastPoDate,
      if (rate != null)
        'Rate': [
          ?row.currency,
          FormattingHelper.formatAmount(rate.toDouble()),
          if (provenance.isNotEmpty) 'from $provenance',
        ].join(' '),
    };

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              row.supplierName ?? row.supplier ?? row.treeLabel,
              style: theme.textTheme.titleSmall,
            ),
            if (details.values.any((value) => value != null)) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  for (final entry in details.entries)
                    if (entry.value case final value?)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(value, style: theme.textTheme.bodySmall),
                        ],
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
