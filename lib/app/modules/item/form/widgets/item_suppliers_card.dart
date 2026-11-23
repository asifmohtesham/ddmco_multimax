// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';
import 'package:multimax/app/modules/global_widgets/form_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/supplier_status_pill.dart';

class ItemSuppliersCard extends StatefulWidget {
  const ItemSuppliersCard({
    super.key,
    required this.isTemplate,
    required this.loadReport,
    required this.onViewReport,
  });

  final bool isTemplate;
  final Future<List<SuppliersByItemNode>> Function() loadReport;
  final VoidCallback onViewReport;

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

        return DocSectionCard(
          title: 'Suppliers',
          children: [
            if (snapshot.connectionState != ConnectionState.done)
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
            else
              ..._buildReportRows(context, snapshot.data ?? const []),
            TextButton(
              onPressed: widget.onViewReport,
              child: const Text('View full report'),
            ),
          ],
        );
      },
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
    for (final row in _reportRows(nodes)) {
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
          _formatLeadTime(row.leadTimeDays!, row.leadTimeReceipts),
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
    yield _formatLeadTime(totalDays / receipts, receipts);
  }

  String _formatLeadTime(num days, int? receipts) =>
      'Lead time: ${days.toStringAsFixed(1)} days'
      '${receipts == null ? '' : ' ($receipts receipts)'}';

  Iterable<SuppliersByItemRow> _reportRows(
    List<SuppliersByItemNode> nodes,
  ) sync* {
    for (final node in nodes) {
      yield node.row;
      yield* _reportRows(node.children);
    }
  }
}
