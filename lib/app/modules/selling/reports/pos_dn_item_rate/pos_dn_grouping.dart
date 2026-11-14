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
      // The group key is the FORMATTED rate string (via formatQty), not the
      // raw numeric value — rates that format identically (e.g. 10.001 and
      // 10.004 both -> "10.00") intentionally merge into a single group.
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

// ── Flattening for a single SliverList ──────────────────────────────────────

const String _sep = '␟'; // Unit Separator glyph — never in real values.

String primaryCollapseKey(String primaryKey) => 'P$_sep$primaryKey';
String secondaryCollapseKey(String primaryKey, String secondaryKey) =>
    'S$_sep$primaryKey$_sep$secondaryKey';

enum DisplayKind { primaryHeader, secondaryHeader, row }

/// A flattened render item: a primary/secondary header (carrying its
/// [GroupNode] and its [collapseKey]) or a leaf [row].
class DisplayItem {
  const DisplayItem._(this.kind, {this.node, this.row, this.collapseKey});

  final DisplayKind kind;
  final GroupNode? node;
  final Map<String, dynamic>? row;
  final String? collapseKey;

  factory DisplayItem.primaryHeader(GroupNode n) => DisplayItem._(
        DisplayKind.primaryHeader,
        node: n,
        collapseKey: primaryCollapseKey(n.key),
      );

  factory DisplayItem.secondaryHeader(GroupNode parent, GroupNode child) =>
      DisplayItem._(
        DisplayKind.secondaryHeader,
        node: child,
        collapseKey: secondaryCollapseKey(parent.key, child.key),
      );

  factory DisplayItem.row(Map<String, dynamic> r) =>
      DisplayItem._(DisplayKind.row, row: r);
}

/// Flattens [nodes] into render order, skipping the children of any header
/// whose collapse key is in [collapsed].
List<DisplayItem> flattenForDisplay(
    List<GroupNode> nodes, Set<String> collapsed) {
  final out = <DisplayItem>[];
  for (final p in nodes) {
    out.add(DisplayItem.primaryHeader(p));
    if (collapsed.contains(primaryCollapseKey(p.key))) continue;
    if (p.children.isEmpty) {
      for (final r in p.rows) {
        out.add(DisplayItem.row(r));
      }
    } else {
      for (final c in p.children) {
        out.add(DisplayItem.secondaryHeader(p, c));
        if (collapsed.contains(secondaryCollapseKey(p.key, c.key))) continue;
        for (final r in c.rows) {
          out.add(DisplayItem.row(r));
        }
      }
    }
  }
  return out;
}

/// Every header collapse key in [nodes] (both levels) — for collapse-all.
Set<String> collapseKeysFor(List<GroupNode> nodes) {
  final keys = <String>{};
  for (final p in nodes) {
    keys.add(primaryCollapseKey(p.key));
    for (final c in p.children) {
      keys.add(secondaryCollapseKey(p.key, c.key));
    }
  }
  return keys;
}
