import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// A field the POS & DN Item Rate report can be grouped by. Pure — no GetX.
enum PosDnGroupField {
  itemGroup('item_group', 'Item Group', false),
  customer('customer', 'Customer', false),
  customerGroup('customer_group', 'Customer Group', false),
  posItemName('upload_item', 'POS Item Name', false),
  rate('upload_rate', 'Rate', true);

  const PosDnGroupField(this.key, this.label, this.numeric);

  final String key;
  final String label;

  /// Rate is a numeric key — sorted by value, not lexically.
  final bool numeric;

  /// Placeholder for blank/missing group values; always sorts last.
  static const String blank = '—';

  /// The group key for [row] under this field (formatted, never empty).
  String valueOf(Map<String, dynamic> row) {
    if (numeric) {
      final n = toNum(row[key]);
      return n == null ? blank : formatQty(n);
    }
    final s = (row[key] ?? '').toString().trim();
    return s.isEmpty ? blank : s;
  }
}

/// One node in the group tree. Leaf nodes carry [rows] and empty [children];
/// parent nodes carry [children] and empty [rows]. [count]/[posQty]/[dnQty]
/// aggregate recursively.
class GroupNode {
  GroupNode(this.key);
  final String key;
  final List<Map<String, dynamic>> rows = [];
  final List<GroupNode> children = [];
  int count = 0;
  num posQty = 0;
  num dnQty = 0;
}

/// Groups [rows] by [primary], optionally sub-grouping by [secondary].
/// Sorted ascending by key (numeric for rate); [PosDnGroupField.blank] last.
List<GroupNode> groupRows(
  List<Map<String, dynamic>> rows,
  PosDnGroupField primary, {
  PosDnGroupField? secondary,
}) {
  final buckets = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    (buckets[primary.valueOf(r)] ??= []).add(r);
  }

  final nodes = <GroupNode>[];
  buckets.forEach((pk, pRows) {
    final node = GroupNode(pk);
    if (secondary == null) {
      node.rows.addAll(pRows);
      _fillLeafTotals(node);
    } else {
      final sub = <String, List<Map<String, dynamic>>>{};
      for (final r in pRows) {
        (sub[secondary.valueOf(r)] ??= []).add(r);
      }
      final children = <GroupNode>[];
      sub.forEach((sk, sRows) {
        final c = GroupNode(sk)..rows.addAll(sRows);
        _fillLeafTotals(c);
        children.add(c);
      });
      _sortNodes(children, secondary);
      node.children.addAll(children);
      _fillParentTotals(node);
    }
    nodes.add(node);
  });

  _sortNodes(nodes, primary);
  return nodes;
}

void _fillLeafTotals(GroupNode n) {
  n.count = n.rows.length;
  for (final r in n.rows) {
    n.posQty += toNum(r['upload_qty']) ?? 0;
    n.dnQty += toNum(r['dn_qty']) ?? 0;
  }
}

void _fillParentTotals(GroupNode n) {
  for (final c in n.children) {
    n.count += c.count;
    n.posQty += c.posQty;
    n.dnQty += c.dnQty;
  }
}

void _sortNodes(List<GroupNode> nodes, PosDnGroupField field) {
  nodes.sort((a, b) {
    final aBlank = a.key == PosDnGroupField.blank;
    final bBlank = b.key == PosDnGroupField.blank;
    if (aBlank != bBlank) return aBlank ? 1 : -1;
    if (aBlank && bBlank) return 0;
    if (field.numeric) {
      return (toNum(a.key) ?? 0).compareTo(toNum(b.key) ?? 0);
    }
    return a.key.toLowerCase().compareTo(b.key.toLowerCase());
  });
}

/// Returns null when [secondary] would duplicate [primary]; else [secondary].
PosDnGroupField? sanitizeSecondary(
    PosDnGroupField? primary, PosDnGroupField? secondary) {
  if (secondary == null) return null;
  return secondary == primary ? null : secondary;
}
