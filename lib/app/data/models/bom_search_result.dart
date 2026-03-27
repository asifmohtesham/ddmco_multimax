/// A single row from the ERPNext v15 "BOM Search" query report.
///
/// Frappe's `frappe.desk.query_report.run` returns a columnar response:
///   message.columns → List of column definitions (Map or plain String)
///   message.result  → List<List<dynamic>> rows
///
/// Use [BomSearchResult.fromColumnar] to parse a row at runtime after
/// resolving column indices from the column-keys list.
class BomSearchResult {
  final String bom;
  final String item;
  final String itemName;
  final double qty;
  final String uom;
  final bool isDefault;
  final bool isActive;

  const BomSearchResult({
    required this.bom,
    required this.item,
    required this.itemName,
    required this.qty,
    required this.uom,
    required this.isDefault,
    required this.isActive,
  });

  /// Constructs a [BomSearchResult] from a single Frappe report row.
  ///
  /// [colKeys] is the ordered list of lowercased fieldnames resolved from
  /// `message.columns`.  [row] is the parallel `List<dynamic>` value row
  /// from `message.result`.
  factory BomSearchResult.fromColumnar(
    List<String> colKeys,
    List<dynamic> row,
  ) {
    dynamic _v(String key) {
      final idx = colKeys.indexOf(key);
      return (idx >= 0 && idx < row.length) ? row[idx] : null;
    }

    double _toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    bool _toBool(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      if (v is int) return v == 1;
      return v.toString() == '1' || v.toString().toLowerCase() == 'true';
    }

    return BomSearchResult(
      bom:       _v('name')?.toString()      ?? _v('bom')?.toString()       ?? '',
      item:      _v('item')?.toString()       ?? '',
      itemName:  _v('item_name')?.toString()  ?? '',
      qty:       _toDouble(_v('qty')),
      uom:       _v('uom')?.toString()        ?? '',
      isDefault: _toBool(_v('is_default')),
      isActive:  _toBool(_v('is_active')),
    );
  }
}
