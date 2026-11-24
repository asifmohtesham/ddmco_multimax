import 'package:multimax/app/data/models/suppliers_by_item_report.dart';

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
  final unit = duration == '1.0' ? 'day' : 'days';
  return 'Lead time: $duration $unit'
      '${receipts == null ? '' : ' (${countLabel(receipts, 'receipt')})'}';
}
