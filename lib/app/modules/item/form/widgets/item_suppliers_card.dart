// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';
import 'package:multimax/app/modules/global_widgets/form_empty_state.dart';

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
              ..._buildSupplierRows(snapshot.data ?? const []),
            TextButton(
              onPressed: widget.onViewReport,
              child: const Text('View full report'),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildSupplierRows(List<SuppliersByItemNode> nodes) {
    final suppliers = <String, SuppliersByItemRow>{};
    for (final row in _supplierRows(nodes)) {
      suppliers.putIfAbsent(
        row.supplier ?? row.supplierName ?? row.treeLabel,
        () => row,
      );
    }

    if (suppliers.isEmpty) {
      return const [
        FormEmptyState(
          icon: Icons.local_shipping_outlined,
          message: 'No suppliers recorded',
        ),
      ];
    }

    return [
      for (final row in suppliers.values)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(row.supplierName ?? row.supplier ?? row.treeLabel),
          subtitle: !widget.isTemplate && row.supplierPartNumber != null
              ? Text('Part no. ${row.supplierPartNumber}')
              : null,
        ),
    ];
  }

  Iterable<SuppliersByItemRow> _supplierRows(
    List<SuppliersByItemNode> nodes,
  ) sync* {
    for (final node in nodes) {
      if (node.row.kind == SuppliersByItemRowKind.supplier) yield node.row;
      yield* _supplierRows(node.children);
    }
  }
}
