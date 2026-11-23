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
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/global_widgets/supplier_status_pill.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_binding.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_controller.dart';

class SuppliersByItemScreen extends StatefulWidget {
  const SuppliersByItemScreen({super.key});

  @override
  State<SuppliersByItemScreen> createState() => _SuppliersByItemScreenState();
}

class _SuppliersByItemScreenState extends State<SuppliersByItemScreen> {
  static const _includeDraftsKey = 'include_drafts';
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
      helperText:
          "Shows items bought from these suppliers, with all of each item's suppliers.",
    ),
    ReportFilterField(
      key: 'warehouses',
      label: 'Warehouses',
      type: ReportFilterType.doctypeMultiLink,
      linkDoctype: 'Warehouse',
      prefixIcon: Icons.warehouse_outlined,
      helperText:
          'Filters balance, projected stock, and reorder quantities. '
          'Groups include child warehouses. '
          'All warehouses are used when empty.',
    ),
    ReportFilterField(
      key: _includeDraftsKey,
      label: 'Include draft purchase orders',
      type: ReportFilterType.switchToggle,
      prefixIcon: Icons.edit_note_outlined,
      helperText:
          'Suppliers that appear only on draft purchase orders are hidden when off.',
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
    final filters = _controller.filters.value;
    final links = filters.linkFilters;
    for (final entry in _draft.entries) {
      entry.value.text = entry.key == _includeDraftsKey
          ? (filters.includeDrafts ? '1' : '')
          : joinMultiValue(links[entry.key] ?? const []);
    }
  }

  SuppliersByItemFilters get _draftFilters => SuppliersByItemFilters(
    items: splitMultiValue(_draft['items']!.text),
    variantOf: splitMultiValue(_draft['variant_of']!.text),
    suppliers: splitMultiValue(_draft['suppliers']!.text),
    warehouses: splitMultiValue(_draft['warehouses']!.text),
    includeDrafts: _draft[_includeDraftsKey]!.text == '1',
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
    );
  }

  void _clearFilters() {
    _controller.run(filters: const SuppliersByItemFilters());
  }

  void _clearFilter(String key) {
    _loadDraft();
    _draft[key]!.text = key == _includeDraftsKey ? '1' : '';
    _controller.run(filters: _draftFilters);
  }

  List<Widget> _filterChips(BuildContext context) => [
    for (final field in _filterFields)
      if (_controller.activeFilters[field.key] case final value?)
        FilterChipWidget(
          icon: field.prefixIcon!,
          label: field.key == _includeDraftsKey
              ? 'Draft POs · $value'
              : '${field.label} · $value',
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

String _quantity(num quantity, [String? uom]) =>
    [FormattingHelper.formatQtyGrouped(quantity.toDouble()), ?uom].join(' ');

class _ReportFooter extends StatelessWidget {
  const _ReportFooter({required this.nodes, required this.bottomPadding});

  final List<SuppliersByItemNode> nodes;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final totals = SuppliersByItemNode.quantityTotalsByUom(nodes);
    final sections = {
      'Total balance qty': [
        for (final entry in totals.entries)
          if (entry.value.balanceQty case final quantity?)
            _quantity(quantity, entry.key),
      ],
      'Total projected qty': [
        for (final entry in totals.entries)
          if (entry.value.projectedQty case final quantity?)
            _quantity(quantity, entry.key),
      ],
      'Total open order qty': [
        for (final entry in totals.entries)
          if (entry.value.openOrderQty case final quantity?)
            _quantity(quantity, entry.key),
      ],
    };
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPadding + 16),
      child: Column(
        children: [
          Text('End of list', style: style),
          for (final section in sections.entries)
            if (section.value.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(section.key, style: style),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                children: [
                  for (final total in section.value) Text(total, style: style),
                ],
              ),
            ],
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
    final supplierSummary = hasNoSupplier
        ? 'No supplier recorded'
        : switch (count) {
            null => null,
            1 => '1 supplier',
            _ => '$count suppliers',
          };
    final quantities = [
      if (row.balanceQty case final balance?)
        'Balance: ${_quantity(balance, row.stockUom)}',
      if (row.projectedQty case final projected?)
        'Projected: ${_quantity(projected, row.stockUom)}',
      if (row.reorderLevel case final level? when level > 0)
        'Reorder level: ${_quantity(level, row.stockUom)}',
    ];
    final details = <Widget>[
      if (supplierSummary != null) Text(supplierSummary),
      if (quantities.isNotEmpty)
        Wrap(
          spacing: 12,
          children: [for (final quantity in quantities) Text(quantity)],
        ),
      if (row.isBelowReorderLevel)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: StatusPill(
            status: 'Below reorder level',
            colorStatus: 'On Hold',
          ),
        ),
    ];
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
          subtitle: details.isEmpty
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: details,
                ),
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
    final nameStyle = theme.textTheme.titleSmall;
    final receipts = row.leadTimeReceipts;
    final counts = [
      if (row.poCount case final count?) '$count POs',
      if (row.receiptCount case final count?) '$count receipts',
    ];
    final procurementDetails = [
      if (row.openOrderQty case final open? when open > 0)
        'Open: ${_quantity(open, row.stockUom)}',
      if (row.draftOrderQty case final draft? when draft > 0)
        'Draft: ${_quantity(draft)}',
      if (row.leadTimeDays case final days?)
        'Lead time: ${days.toStringAsFixed(1)} days'
            '${receipts == null ? '' : ' ($receipts receipts)'}',
      if (counts.isNotEmpty) counts.join(' · '),
    ];

    final details = {
      'Part number': row.supplierPartNumber,
      'Sources': row.sources,
      'Last purchase': row.lastPurchaseDate,
      'Qty received': quantity == null
          ? null
          : _quantity(quantity, row.stockUom),
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
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  row.supplierName ?? row.supplier ?? row.treeLabel,
                  style: row.matchedSupplier
                      ? nameStyle?.copyWith(fontWeight: FontWeight.bold)
                      : nameStyle,
                ),
                SupplierStatusPill(status: row.supplierStatus),
              ],
            ),
            if (procurementDetails.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final detail in procurementDetails)
                    Text(detail, style: theme.textTheme.bodySmall),
                ],
              ),
            ],
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
