// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/data/utils/suppliers_by_item_labels.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';
import 'package:multimax/app/modules/global_widgets/form_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/supplier_status_pill.dart';

class ItemSuppliersCard extends StatefulWidget {
  const ItemSuppliersCard({
    super.key,
    required this.itemCode,
    required this.isTemplate,
    required this.loadReport,
    required this.onViewReport,
  });

  final String itemCode;
  final bool isTemplate;
  final Future<List<SuppliersByItemNode>> Function() loadReport;
  final ValueChanged<bool> onViewReport;

  @override
  State<ItemSuppliersCard> createState() => _ItemSuppliersCardState();
}

class _ItemSuppliersCardState extends State<ItemSuppliersCard> {
  late Future<List<SuppliersByItemNode>> _report;

  @override
  void initState() {
    super.initState();
    _report = widget.loadReport();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SuppliersByItemNode>>(
      future: _report,
      builder: (context, snapshot) {
        if (snapshot.error case SuppliersByItemReportException(
          permissionDenied: true,
        )) {
          return const SizedBox.shrink();
        }

        final isLoading = snapshot.connectionState != ConnectionState.done;
        final nodes = snapshot.data ?? const [];
        final boms = _itemBoms(nodes).toList();
        return DocSectionCard(
          title: 'Suppliers',
          children: [
            if (isLoading)
              const LinearProgressIndicator()
            else if (snapshot.hasError)
              FormEmptyState(
                icon: Icons.error_outline,
                message: 'Could not load suppliers.',
                action: OutlinedButton(
                  onPressed: () =>
                      setState(() => _report = widget.loadReport()),
                  child: const Text('Retry'),
                ),
              )
            else ...[
              ..._buildReportRows(context, nodes),
              if (boms.isNotEmpty) ..._buildBomSection(context, boms),
            ],
            TextButton(
              onPressed: isLoading
                  ? null
                  : () => widget.onViewReport(boms.isNotEmpty),
              child: const Text('View full report'),
            ),
          ],
        );
      },
    );
  }

  Iterable<SuppliersByItemNode> _itemBoms(List<SuppliersByItemNode> nodes) =>
      nodes
          .expand(
            (node) => node.row.kind == SuppliersByItemRowKind.template
                ? node.children
                : [node],
          )
          .where(
            (node) =>
                node.row.kind == SuppliersByItemRowKind.item &&
                node.row.itemCode == widget.itemCode,
          )
          .expand((node) => node.children)
          .where((node) => node.row.kind == SuppliersByItemRowKind.bom);

  List<Widget> _buildBomSection(
    BuildContext context,
    List<SuppliersByItemNode> boms,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return [
      const Divider(),
      Text('Made from (BOM)', style: textTheme.titleSmall),
      for (final bom in boms) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            [
              bom.row.bomNo ?? bom.row.treeLabel,
              if (bom.row.bomIsDefault && bom.row.bomStatus != 'Draft')
                'default',
              if (bom.row.bomStatus == 'Draft') 'Draft',
            ].join(' · '),
            style: textTheme.labelLarge,
          ),
        ),
        for (final component in bom.children)
          if (component.row.kind == SuppliersByItemRowKind.component)
            _buildBomComponent(context, component),
      ],
    ];
  }

  Widget _buildBomComponent(
    BuildContext context,
    SuppliersByItemNode component,
  ) {
    final row = component.row;
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.scheme.textMuted);
    final supplierNames = {
      for (final child in component.children)
        if (child.row.kind == SuppliersByItemRowKind.supplier)
          if ((child.row.supplierName ?? child.row.supplier) case final name?)
            name,
    };
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 12, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.itemTitle),
          if (row.distinctItemName case final name?) Text(name, style: muted),
          Text(
            supplierNames.isEmpty
                ? 'No supplier recorded'
                : supplierNames.join(', '),
            style: muted,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildReportRows(
    BuildContext context,
    List<SuppliersByItemNode> nodes,
  ) {
    final stockKind = widget.isTemplate
        ? SuppliersByItemRowKind.template
        : SuppliersByItemRowKind.item;
    SuppliersByItemRow? stockRow;
    final suppliers = <String, List<SuppliersByItemRow>>{};
    for (final row in _summaryRows(nodes)) {
      if (row.kind == stockKind) {
        stockRow ??= row;
      } else if (row.kind == SuppliersByItemRowKind.supplier) {
        final supplier = row.supplier ?? row.supplierName ?? row.treeLabel;
        (suppliers[supplier] ??= []).add(row);
      }
    }

    return [
      if (stockRow case final stock?
          when stock.balanceQty != null || stock.projectedQty != null)
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            if (stock.balanceQty case final qty?)
              Text('Balance: ${_formatStockQty(qty, stock.stockUom)}'),
            if (stock.projectedQty case final qty?)
              Text('Projected: ${_formatStockQty(qty, stock.stockUom)}'),
          ],
        ),
      if (suppliers.isEmpty)
        const FormEmptyState(
          icon: Icons.local_shipping_outlined,
          message: 'No suppliers recorded',
        ),
      for (final rows in suppliers.values) _buildSupplierTile(context, rows),
    ];
  }

  Widget _buildSupplierTile(
    BuildContext context,
    List<SuppliersByItemRow> rows,
  ) {
    final supplier = rows.first;
    final status = rows.map((row) => row.supplierStatus).nonNulls.firstOrNull;
    final openOrders = <({String? uom, String? itemCode}), num>{};
    for (final row in rows) {
      if (row.openOrderQty case final qty? when qty > 0) {
        final uom = row.stockUom;
        final key = (
          uom: uom,
          itemCode: uom == null && rows.length > 1 ? row.itemCode : null,
        );
        openOrders.update(key, (total) => total + qty, ifAbsent: () => qty);
      }
    }

    final details = [
      if (!widget.isTemplate && supplier.supplierPartNumber != null)
        'Part no. ${supplier.supplierPartNumber}',
      for (final entry in openOrders.entries)
        [
          ?entry.key.itemCode,
          'Open: ${_formatStockQty(entry.value, entry.key.uom)}',
        ].join(' · '),
      ..._leadTimeDetails(rows),
    ];
    final detailStyle = TextStyle(color: context.scheme.textMuted);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            supplier.supplierName ?? supplier.supplier ?? supplier.treeLabel,
          ),
          SupplierStatusPill(status: status),
        ],
      ),
      subtitle: details.isEmpty
          ? null
          : Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final detail in details) Text(detail, style: detailStyle),
              ],
            ),
    );
  }

  String _formatStockQty(num qty, String? uom) =>
      [FormattingHelper.formatQtyGrouped(qty.toDouble()), ?uom].join(' ');

  Iterable<String> _leadTimeDetails(List<SuppliersByItemRow> rows) sync* {
    final samples = rows.where((row) => row.leadTimeDays != null).toList();
    if (samples.length <= 1 ||
        samples.any((row) => (row.leadTimeReceipts ?? 0) <= 0)) {
      for (final row in samples) {
        yield [
          if (samples.length > 1) ?row.itemCode,
          leadTimeLabel(row.leadTimeDays!, row.leadTimeReceipts),
        ].join(' · ');
      }
      return;
    }

    num totalDays = 0;
    var receipts = 0;
    for (final row in samples) {
      totalDays += row.leadTimeDays! * row.leadTimeReceipts!;
      receipts += row.leadTimeReceipts!;
    }
    yield leadTimeLabel(totalDays / receipts, receipts);
  }

  Iterable<SuppliersByItemRow> _summaryRows(
    List<SuppliersByItemNode> nodes,
  ) sync* {
    for (final node in nodes) {
      final row = node.row;
      final isTemplateItem =
          widget.isTemplate &&
          row.kind == SuppliersByItemRowKind.item &&
          row.itemCode == widget.itemCode;
      if (row.isComponent ||
          row.kind == SuppliersByItemRowKind.bom ||
          isTemplateItem) {
        continue;
      }
      yield row;
      yield* _summaryRows(node.children);
    }
  }
}
