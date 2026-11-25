import 'package:multimax/app/data/models/suppliers_by_item_report.dart';

abstract final class SuppliersByItemColumnLabels {
  static const balanceQty = 'Balance Qty';
  static const projectedQty = 'Projected Qty';
  static const openOrderQty = 'Open Order Qty';
  static const supplierPartNumber = 'Supplier Part Number';
  static const leadTimeDays = 'Lead Time (Days)';
  static const leadTimeReceipts = 'Lead Time Receipts';
  static const noSupplierRecorded = 'No supplier recorded';
}

extension SuppliersByItemLabels on SuppliersByItemRow {
  String get itemTitle =>
      (kind == SuppliersByItemRowKind.template ? template : itemCode) ??
      treeLabel;

  String? get distinctItemName {
    final name = itemName;
    return name == '-' || name == itemTitle ? null : name;
  }
}

String countLabel(int count, String noun) =>
    '$count $noun${count == 1 ? '' : 's'}';

String leadTimeLabel(num days, int? receipts) {
  final duration = days.toStringAsFixed(1);
  return [
    '${SuppliersByItemColumnLabels.leadTimeDays} $duration',
    if (receipts != null)
      '${SuppliersByItemColumnLabels.leadTimeReceipts} $receipts',
  ].join(' · ');
}
