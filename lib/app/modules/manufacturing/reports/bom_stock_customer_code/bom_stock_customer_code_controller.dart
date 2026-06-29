import 'package:get/get.dart';

/// Controller for the "BOM Stock with Customer Code" report.
///
/// Parsing logic is exposed as pure static helpers so it can be unit-tested
/// without the network or GetX. Instance members (reactive state + actions)
/// are added on top of these.
class BomStockCustomerCodeController extends GetxController {
  // ── Static parsers (pure) ───────────────────────────────────────────────

  /// Data rows from a `query_report.run` `message`, excluding the appended
  /// `add_total_row` total (identified by an empty/absent `item_code`).
  static List<Map<String, dynamic>> parseDataRows(dynamic message) {
    if (message is! Map) return [];
    final result = message['result'];
    if (result is! List) return [];
    return result
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((r) => (r['item_code'] ?? '').toString().trim().isNotEmpty)
        .toList();
  }

  /// The appended total row (first result row with an empty `item_code`), or
  /// null when the report returned no total row.
  static Map<String, dynamic>? extractTotalRow(dynamic message) {
    if (message is! Map) return null;
    final result = message['result'];
    if (result is! List) return null;
    for (final e in result.whereType<Map>()) {
      final m = Map<String, dynamic>.from(e);
      if ((m['item_code'] ?? '').toString().trim().isEmpty) return m;
    }
    return null;
  }

  /// True when [row] is short of its POS-required quantity, mirroring the
  /// desk's red highlight: `required_qty` truthy and `running_total` below it.
  static bool isShortfall(Map<String, dynamic> row) {
    final req = row['required_qty'];
    if (req is! num || req == 0) return false;
    final rt = (row['running_total'] as num?)?.toDouble() ?? 0;
    return rt < req.toDouble();
  }

  /// Distinct, non-empty `customer_code` values in first-seen order.
  static List<String> distinctCustomerCodes(List<Map<String, dynamic>> rows) {
    final out = <String>[];
    for (final r in rows) {
      final c = (r['customer_code'] ?? '').toString().trim();
      if (c.isNotEmpty && !out.contains(c)) out.add(c);
    }
    return out;
  }

  /// Splits [uploadCodes] into codes present in [resultRows] (found) and codes
  /// absent from them (missing) — reproduces the desk's POS missing-codes
  /// banner using only readable result data.
  static (List<String>, List<String>) splitPosCodes(
    List<String> uploadCodes,
    List<Map<String, dynamic>> resultRows,
  ) {
    final present = distinctCustomerCodes(resultRows).toSet();
    final found = <String>[];
    final missing = <String>[];
    for (final raw in uploadCodes) {
      final code = raw.trim();
      if (code.isEmpty) continue;
      if (present.contains(code)) {
        if (!found.contains(code)) found.add(code);
      } else {
        if (!missing.contains(code)) missing.add(code);
      }
    }
    return (found, missing);
  }
}
