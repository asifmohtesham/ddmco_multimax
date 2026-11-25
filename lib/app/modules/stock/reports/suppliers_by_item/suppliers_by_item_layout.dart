import '../../../../data/models/suppliers_by_item_report.dart';
import '../../../../data/models/suppliers_by_item_view.dart';
import '../../../../data/utils/suppliers_by_item_labels.dart';

import 'suppliers_by_item_fields.dart';

export '../../../../data/models/suppliers_by_item_view.dart';

typedef SuppliersByItemRowKey = Record;
typedef SuppliersByItemSourceKey = ({String nodeId});

enum SuppliersByItemOccurrence {
  supplierGroup,
  unresolvedSupplierGroup,
  noDirectGroup,
  otherRows,
  direct,
  componentMatch,
}

SuppliersByItemSourceKey _keyOf(SuppliersByItemNode node) =>
    (nodeId: node.row.nodeId);

class SuppliersByItemIndex {
  SuppliersByItemIndex._(this.roots, this.nodesById)
    : canonicalItems = Map.unmodifiable({
        for (final node in SuppliersByItemNode.topLevelItems(roots))
          node.row.itemIdentity: node,
      });

  final List<SuppliersByItemNode> roots;
  final Map<String, SuppliersByItemNode> nodesById;
  final Map<({String? code, String? nodeId}), SuppliersByItemNode>
  canonicalItems;

  late final _view = _projectTemplateView(this, showPlaceholders: true);
  late final _viewWithoutPlaceholders = _projectTemplateView(
    this,
    showPlaceholders: false,
  );
  late final _supplierView = _projectSupplierView(this, _view);
  late final _supplierViewWithoutPlaceholders = _projectSupplierView(
    this,
    _viewWithoutPlaceholders,
  );
  late final _summary = _summarize(this);
  late final _supplierLabels = _supplierDisplayLabels(nodesById.values);
  late final _owners = List<SuppliersByItemNode>.unmodifiable(
    roots.expand(
      (node) => node.row.kind == SuppliersByItemRowKind.template
          ? _variants(node)
          : _isOwner(node)
          ? [node]
          : const <SuppliersByItemNode>[],
    ),
  );
  late final _sourceOwners = _owners.toSet();
  late final _linksByOwner = _collectOwnerLinks();
  late final _sourceOrdinals = {
    for (final (ordinal, id) in nodesById.keys.indexed) id: ordinal,
  };

  Map<SuppliersByItemSourceKey, List<SuppliersByItemNode>>
  _collectOwnerLinks() {
    final byOwner = <SuppliersByItemSourceKey, List<SuppliersByItemNode>>{};
    for (final owner in _owners) {
      final canonical = _keyOf(canonicalItems[owner.row.itemIdentity]!);
      (byOwner[canonical] ??= []).addAll(_directSuppliers(owner));
    }
    return byOwner;
  }
}

SuppliersByItemIndex indexReport(Iterable<SuppliersByItemNode> roots) {
  final source = List<SuppliersByItemNode>.unmodifiable(roots);
  final nodes = <String, SuppliersByItemNode>{};
  void visit(SuppliersByItemNode node) {
    nodes[node.row.nodeId] = node;
    for (final child in node.children) {
      visit(child);
    }
  }

  for (final root in source) {
    visit(root);
  }
  return SuppliersByItemIndex._(source, Map.unmodifiable(nodes));
}

class SuppliersByItemLayoutRow {
  const SuppliersByItemLayoutRow._({
    required this.node,
    required this.ancestorKeys,
    required this.ownerKey,
    required this.children,
    required this.templateNode,
    required this.directSupplierCount,
    required this.hasDirectSupplier,
    required this.supplierLabel,
    required this.bomLabel,
    required this.variantCount,
    this.hasNamedSupplier = false,
    this.group,
    this.groupSupplierStatus,
    this.ownerNode,
    this.componentTrail = const [],
    this.componentPath,
    this.parentOutputUom,
    SuppliersByItemRowKey? occurrenceKey,
    SuppliersByItemNode? pairNode,
    Iterable<SuppliersByItemNode>? sortLinks,
  }) : _occurrenceKey = occurrenceKey,
       _pairNode = pairNode,
       _sortLinks = sortLinks;

  final SuppliersByItemRowKey? _occurrenceKey;
  final SuppliersByItemNode? _pairNode;
  final Iterable<SuppliersByItemNode>? _sortLinks;

  final SuppliersByItemNode node;
  final List<SuppliersByItemRowKey> ancestorKeys;
  final SuppliersByItemSourceKey? ownerKey;
  final List<SuppliersByItemLayoutRow> children;
  final SuppliersByItemNode? templateNode;
  final int? directSupplierCount;
  final bool hasDirectSupplier;
  final String supplierLabel;
  final bool hasNamedSupplier;
  final String bomLabel;
  final int variantCount;
  final SuppliersByItemSupplierGroup? group;
  final String? groupSupplierStatus;
  final SuppliersByItemNode? ownerNode;
  final List<SuppliersByItemNode> componentTrail;
  final String? componentPath;
  final String? parentOutputUom;

  SuppliersByItemSourceKey get sourceKey => _keyOf(node);
  SuppliersByItemRowKey get key => _occurrenceKey ?? sourceKey;
  SuppliersByItemNode? get pairNode =>
      _pairNode ??
      (group == null && node.row.kind == SuppliersByItemRowKind.supplier
          ? node
          : null);
  SuppliersByItemSourceKey? get pairKey =>
      pairNode == null ? null : _keyOf(pairNode!);
  bool get isPairOccurrence => _pairNode != null;
  bool get isComponentMatch => componentTrail.isNotEmpty;
  int get depth => ancestorKeys.length;
  SuppliersByItemRowKey? get parentKey => ancestorKeys.lastOrNull;
  String? get templateContext => templateNode?.row.itemTitle;

  SuppliersByItemLayoutRow _withChildren(
    List<SuppliersByItemLayoutRow> rows, {
    List<SuppliersByItemRowKey>? ancestors,
    SuppliersByItemRowKey? occurrenceKey,
    SuppliersByItemSupplierGroup? group,
    String? groupSupplierStatus,
    String? supplierLabel,
    bool? hasNamedSupplier,
  }) => SuppliersByItemLayoutRow._(
    node: node,
    ancestorKeys: ancestors ?? ancestorKeys,
    ownerKey: ownerKey,
    children: List.unmodifiable(rows),
    templateNode: ancestors == null ? templateNode : null,
    directSupplierCount: directSupplierCount,
    hasDirectSupplier: hasDirectSupplier,
    supplierLabel: supplierLabel ?? this.supplierLabel,
    hasNamedSupplier: hasNamedSupplier ?? this.hasNamedSupplier,
    bomLabel: bomLabel,
    variantCount: variantCount,
    group: group ?? this.group,
    groupSupplierStatus: groupSupplierStatus ?? this.groupSupplierStatus,
    ownerNode: ownerNode,
    componentTrail: componentTrail,
    componentPath: componentPath,
    parentOutputUom: parentOutputUom,
    occurrenceKey: occurrenceKey ?? _occurrenceKey,
    pairNode: _pairNode,
    sortLinks: _sortLinks,
  );
}

class SuppliersByItemSupplierGroup {
  const SuppliersByItemSupplierGroup._({
    required this.label,
    this.directItemCount = 0,
    this.componentMatchCount = 0,
    this.retainedDirectItemCount,
    this.retainedComponentMatchCount,
    this.supplierStatus,
    this.hasNamedSupplier = false,
    this.matchedSupplier = false,
    this.isNoDirect = false,
    this.isOther = false,
  });

  final String label;
  final int directItemCount;
  final int componentMatchCount;
  final int? retainedDirectItemCount;
  final int? retainedComponentMatchCount;
  final String? supplierStatus;
  final bool hasNamedSupplier;
  final bool matchedSupplier;
  final bool isNoDirect;
  final bool isOther;

  SuppliersByItemSupplierGroup _withRetainedCounts(
    int direct,
    int components,
  ) => SuppliersByItemSupplierGroup._(
    label: label,
    directItemCount: directItemCount,
    componentMatchCount: componentMatchCount,
    retainedDirectItemCount: direct,
    retainedComponentMatchCount: components,
    supplierStatus: supplierStatus,
    hasNamedSupplier: hasNamedSupplier,
    matchedSupplier: matchedSupplier,
    isNoDirect: isNoDirect,
    isOther: isOther,
  );
}

List<SuppliersByItemLayoutRow> buildTemplateView(
  SuppliersByItemIndex index, {
  bool showPlaceholders = true,
  SuppliersByItemView? view,
}) {
  final raw = showPlaceholders ? index._view : index._viewWithoutPlaceholders;
  if (view == null) return raw;
  final normal = <SuppliersByItemLayoutRow>[];
  final other = <SuppliersByItemLayoutRow>[];
  for (final row in raw) {
    if (row.node.row.kind == SuppliersByItemRowKind.template) {
      normal.add(
        row._withChildren([
          ...sortSiblings(
            row.children.where((child) => _isOwner(child.node)),
            view.sortField,
            view.sortDirection,
          ),
          ...row.children.where((child) => !_isOwner(child.node)),
        ]),
      );
    } else if (_isOwner(row.node)) {
      normal.add(row);
    } else {
      other.add(row);
    }
  }
  return List.unmodifiable([
    ...sortSiblings(normal, view.sortField, view.sortDirection),
    ...other,
  ]);
}

bool _isOwner(SuppliersByItemNode node) =>
    node.row.kind == SuppliersByItemRowKind.item && !node.row.isComponent;

Iterable<SuppliersByItemNode> _variants(SuppliersByItemNode template) =>
    template.children.where(_isOwner);

Iterable<SuppliersByItemNode> _directSuppliers(SuppliersByItemNode node) => node
    .children
    .where((child) => child.row.kind == SuppliersByItemRowKind.supplier);

({int? count, bool hasLink}) _linkCount(Iterable<SuppliersByItemNode> links) {
  final ids = links.map((child) => child.row.supplier).toSet();
  return (
    count: ids.contains(null) ? null : ids.length,
    hasLink: ids.isNotEmpty,
  );
}

String _supplierName(SuppliersByItemRow row) =>
    row.supplierName ?? row.supplier ?? row.treeLabel;

Map<String, String> _supplierDisplayLabels(
  Iterable<SuppliersByItemNode> nodes,
) {
  final suppliers = nodes
      .map((node) => node.row)
      .where((row) => row.kind == SuppliersByItemRowKind.supplier);
  final idsByName = <String, Set<String>>{};
  for (final supplier in suppliers) {
    final id = supplier.supplier;
    if (id != null) {
      idsByName.putIfAbsent(_supplierName(supplier), () => {}).add(id);
    }
  }
  return {
    for (final supplier in suppliers)
      supplier.nodeId:
          (idsByName[_supplierName(supplier)]?.length ?? 0) > 1 &&
              supplier.supplier != null
          ? '${_supplierName(supplier)} (${supplier.supplier})'
          : _supplierName(supplier),
  };
}

final _bomDecoration = RegExp(
  r'^(?:default|draft|[0-9]+ components?)$',
  caseSensitive: false,
);

String _bomIdentity(SuppliersByItemRow row, int ordinal) {
  if (row.bomNo case final code?) return code;
  final parts = row.treeLabel.split(' · ').map((part) => part.trim()).toList();
  final identity = parts.first;
  if (identity.isEmpty ||
      identity.toLowerCase() == 'bom' ||
      _bomDecoration.hasMatch(identity) ||
      !parts.skip(1).every(_bomDecoration.hasMatch)) {
    return 'BOM $ordinal';
  }
  return identity;
}

List<SuppliersByItemLayoutRow> _projectTemplateView(
  SuppliersByItemIndex index, {
  required bool showPlaceholders,
}) {
  SuppliersByItemLayoutRow project(
    SuppliersByItemNode node, {
    List<SuppliersByItemRowKey> ancestors = const [],
    SuppliersByItemNode? ownerNode,
    SuppliersByItemNode? templateNode,
    String? parentOutputUom,
    Set<String> itemPath = const {},
    int bomLevel = 0,
    int bomOrdinal = 1,
    bool stopBomDescent = false,
    bool templateLeaf = false,
  }) {
    final row = node.row;
    final kind = row.kind;
    final isOwner = index._sourceOwners.contains(node);
    final owner = isOwner ? index.canonicalItems[row.itemIdentity]! : ownerNode;
    final code = switch (kind) {
      SuppliersByItemRowKind.item ||
      SuppliersByItemRowKind.component => row.itemCode,
      _ => null,
    };
    final terminal =
        stopBomDescent ||
        row.bomCycle ||
        row.bomDepthLimit ||
        bomLevel >= 10 ||
        (code != null && itemPath.contains(code));
    final nextPath = code == null ? itemPath : {...itemPath, code};
    final nextAncestors = List<SuppliersByItemRowKey>.unmodifiable([
      ...ancestors,
      _keyOf(node),
    ]);
    final children = <SuppliersByItemLayoutRow>[];
    var nextBomOrdinal = 0;
    for (final child
        in templateLeaf ? const <SuppliersByItemNode>[] : node.children) {
      final childKind = child.row.kind;
      if (childKind == SuppliersByItemRowKind.placeholder &&
          !showPlaceholders) {
        continue;
      }
      final isBom = childKind == SuppliersByItemRowKind.bom;
      if (isBom && terminal) continue;
      children.add(
        project(
          child,
          ancestors: nextAncestors,
          ownerNode: owner,
          parentOutputUom: switch (kind) {
            SuppliersByItemRowKind.item ||
            SuppliersByItemRowKind.component => row.stockUom,
            _ => parentOutputUom,
          },
          itemPath: nextPath,
          bomLevel: isBom ? bomLevel + 1 : bomLevel,
          bomOrdinal: isBom ? ++nextBomOrdinal : 1,
          stopBomDescent: terminal,
        ),
      );
    }
    final suppliers = switch (kind) {
      SuppliersByItemRowKind.template => _variants(
        node,
      ).expand(_directSuppliers),
      _ => _directSuppliers(node),
    };
    final links = _linkCount(suppliers);
    return SuppliersByItemLayoutRow._(
      node: node,
      ancestorKeys: ancestors,
      ownerKey: owner == null ? null : _keyOf(owner),
      ownerNode: owner,
      children: List.unmodifiable(children),
      templateNode: templateNode,
      directSupplierCount: row.supplierCount ?? links.count,
      hasDirectSupplier: links.hasLink || (row.supplierCount ?? 0) > 0,
      supplierLabel: index._supplierLabels[row.nodeId] ?? row.treeLabel,
      hasNamedSupplier: row.supplierName != null,
      bomLabel: kind == SuppliersByItemRowKind.bom
          ? _bomIdentity(row, bomOrdinal)
          : row.treeLabel,
      variantCount: kind == SuppliersByItemRowKind.template
          ? _variants(node).length
          : 0,
      parentOutputUom: parentOutputUom,
      sortLinks: suppliers,
    );
  }

  final rows = <SuppliersByItemLayoutRow>[];
  final other = <SuppliersByItemNode>[];
  for (final node in index.roots) {
    if (node.row.kind == SuppliersByItemRowKind.template) {
      final variants = _variants(node).toList();
      if (variants.length == 1) {
        rows.add(project(variants.single, templateNode: node));
      } else {
        rows.add(project(node, templateLeaf: variants.isEmpty));
      }
      if (variants.length < 2) {
        other.addAll(node.children.where((child) => !_isOwner(child)));
      }
    } else if (_isOwner(node)) {
      rows.add(project(node));
    } else {
      other.add(node);
    }
  }
  var otherBomOrdinal = 0;
  for (final node in other) {
    rows.add(
      project(
        node,
        bomOrdinal: node.row.kind == SuppliersByItemRowKind.bom
            ? ++otherBomOrdinal
            : 1,
      ),
    );
  }
  return List.unmodifiable(rows);
}

const _noDirectGroup = (SuppliersByItemOccurrence.noDirectGroup,);
const _otherRows = (SuppliersByItemOccurrence.otherRows,);

SuppliersByItemRowKey _supplierGroupKey(SuppliersByItemNode pair) =>
    pair.row.supplier == null
    ? (SuppliersByItemOccurrence.unresolvedSupplierGroup, pair.row.nodeId)
    : (SuppliersByItemOccurrence.supplierGroup, pair.row.supplier!);

class _SupplierGroupBuilder {
  _SupplierGroupBuilder(this.key, this.firstPair);

  final SuppliersByItemRowKey key;
  final SuppliersByItemNode firstPair;
  final direct = <SuppliersByItemSourceKey, SuppliersByItemLayoutRow>{};
  final components = <SuppliersByItemLayoutRow>[];
  String? name;
  int? nameOrdinal;
  bool matched = false;

  String get id => firstPair.row.supplier ?? firstPair.row.nodeId;
  String get label => name ?? _supplierName(firstPair.row);

  void addPair(SuppliersByItemNode pair, int ordinal) {
    final sourceName = pair.row.supplierName;
    if (sourceName != null && (nameOrdinal == null || ordinal < nameOrdinal!)) {
      name = sourceName;
      nameOrdinal = ordinal;
    }
    matched = matched || pair.row.matchedSupplier;
  }

  SuppliersByItemLayoutRow build(bool disambiguate) {
    final hasNamedSupplier = name != null;
    final groupLabel = disambiguate && firstPair.row.supplier != null
        ? '$label ($id)'
        : label;
    final pairs = [...direct.values, ...components];
    final firstStatus = pairs.first.pairNode!.row.supplierStatus;
    final supplierStatus =
        firstStatus != null &&
            pairs.every(
              (pair) => pair.pairNode!.row.supplierStatus == firstStatus,
            )
        ? firstStatus
        : null;
    return _groupRow(
      key,
      [
        for (final pair in pairs)
          pair.supplierLabel == groupLabel &&
                  pair.hasNamedSupplier == hasNamedSupplier &&
                  supplierStatus == null
              ? pair
              : pair._withChildren(
                  pair.children,
                  supplierLabel: groupLabel,
                  hasNamedSupplier: hasNamedSupplier,
                  groupSupplierStatus: supplierStatus,
                ),
      ],
      SuppliersByItemSupplierGroup._(
        label: groupLabel,
        directItemCount: direct.length,
        componentMatchCount: components.length,
        supplierStatus: supplierStatus,
        hasNamedSupplier: hasNamedSupplier,
        matchedSupplier: matched,
      ),
    );
  }
}

SuppliersByItemLayoutRow _groupRow(
  SuppliersByItemRowKey key,
  List<SuppliersByItemLayoutRow> children,
  SuppliersByItemSupplierGroup group,
) => SuppliersByItemLayoutRow._(
  node: children.first.node,
  ancestorKeys: const [],
  ownerKey: null,
  children: List.unmodifiable(children),
  templateNode: null,
  directSupplierCount: null,
  hasDirectSupplier: false,
  supplierLabel: group.label,
  bomLabel: '',
  variantCount: 0,
  occurrenceKey: key,
  group: group,
);

SuppliersByItemLayoutRow _copyBranch(
  SuppliersByItemLayoutRow row,
  SuppliersByItemRowKey prefix,
  List<SuppliersByItemRowKey> ancestors, {
  SuppliersByItemRowKey? rootKey,
  Iterable<SuppliersByItemLayoutRow>? sourceChildren,
}) {
  final key = rootKey ?? (prefix, row.sourceKey.nodeId);
  final trail = List<SuppliersByItemRowKey>.unmodifiable([...ancestors, key]);
  return row._withChildren(
    [
      for (final child in sourceChildren ?? row.children)
        _copyBranch(child, prefix, trail),
    ],
    ancestors: ancestors,
    occurrenceKey: key,
  );
}

List<SuppliersByItemLayoutRow> _projectSupplierView(
  SuppliersByItemIndex index,
  List<SuppliersByItemLayoutRow> templateView,
) {
  final owners = <SuppliersByItemSourceKey, List<SuppliersByItemLayoutRow>>{};
  final other = <SuppliersByItemLayoutRow>[];
  void addOwner(SuppliersByItemLayoutRow row) {
    (owners[row.ownerKey!] ??= []).add(row);
  }

  for (final root in templateView) {
    if (root.variantCount > 1) {
      for (final child in root.children) {
        if (_isOwner(child.node)) {
          addOwner(child);
        } else {
          other.add(child);
        }
      }
    } else if (_isOwner(root.node)) {
      addOwner(root);
    } else {
      other.add(root);
    }
  }
  final groups = <SuppliersByItemRowKey, _SupplierGroupBuilder>{};
  final unsupplied = <SuppliersByItemLayoutRow>[];
  _SupplierGroupBuilder groupFor(SuppliersByItemNode pair) {
    final key = _supplierGroupKey(pair);
    return groups.putIfAbsent(key, () => _SupplierGroupBuilder(key, pair))
      ..addPair(pair, index._sourceOrdinals[pair.row.nodeId]!);
  }

  for (final MapEntry(key: ownerKey, value: sources) in owners.entries) {
    final owner = sources.first.ownerNode!;
    final ownerId = ownerKey.nodeId;
    final ownerLinks = index._linksByOwner[ownerKey]!;
    final ownerCount = owner.row.supplierCount ?? _linkCount(ownerLinks).count;
    final boms = sources
        .expand((row) => row.children)
        .where((row) => row.node.row.kind == SuppliersByItemRowKind.bom);

    if (ownerLinks.isEmpty) {
      if ((ownerCount ?? 0) > 0) {
        other.add(
          sources.first._withChildren([
            for (final source in sources) ...source.children,
          ]),
        );
      } else {
        final key = (_noDirectGroup, SuppliersByItemOccurrence.direct, ownerId);
        unsupplied.add(
          _copyBranch(
            sources.first,
            key,
            const [_noDirectGroup],
            rootKey: key,
            sourceChildren: sources.expand((row) => row.children),
          ),
        );
      }
    }

    for (final pair in ownerLinks) {
      final group = groupFor(pair);
      final ancestors = List<SuppliersByItemRowKey>.unmodifiable([group.key]);
      final key = (group.key, SuppliersByItemOccurrence.direct, ownerId);
      group.direct.putIfAbsent(
        ownerKey,
        () => SuppliersByItemLayoutRow._(
          node: owner,
          ancestorKeys: ancestors,
          ownerKey: ownerKey,
          ownerNode: owner,
          children: List.unmodifiable([
            for (final bom in boms)
              _copyBranch(bom, key, List.unmodifiable([...ancestors, key])),
          ]),
          templateNode: null,
          directSupplierCount: ownerCount,
          hasDirectSupplier: true,
          supplierLabel: index._supplierLabels[pair.row.nodeId]!,
          hasNamedSupplier: pair.row.supplierName != null,
          bomLabel: '',
          variantCount: 0,
          occurrenceKey: key,
          pairNode: pair,
        ),
      );
    }

    void collectComponents(
      Iterable<SuppliersByItemLayoutRow> siblings,
      List<SuppliersByItemNode> trail,
      List<String> labels,
    ) {
      final branches = siblings.where((row) {
        final kind = row.node.row.kind;
        return kind == SuppliersByItemRowKind.bom ||
            kind == SuppliersByItemRowKind.component ||
            (kind == SuppliersByItemRowKind.item && row.node.row.isComponent);
      });
      String labelOf(SuppliersByItemLayoutRow row) =>
          row.node.row.kind == SuppliersByItemRowKind.bom
          ? row.bomLabel
          : row.node.row.itemTitle;
      final counts = <String, int>{};
      for (final row in branches) {
        counts.update(labelOf(row), (count) => count + 1, ifAbsent: () => 1);
      }
      for (final (indexInSource, row) in branches.indexed) {
        final label = labelOf(row);
        final path = [...trail, row.node];
        final pathLabels = [
          ...labels,
          counts[label]! > 1 ? '$label (line ${indexInSource + 1})' : label,
        ];
        if (row.node.row.kind != SuppliersByItemRowKind.bom) {
          for (final pair in _directSuppliers(row.node)) {
            final group = groupFor(pair);
            final key = (
              group.key,
              SuppliersByItemOccurrence.componentMatch,
              ownerId,
              row.sourceKey.nodeId,
              pair.row.nodeId,
            );
            group.components.add(
              SuppliersByItemLayoutRow._(
                node: row.node,
                ancestorKeys: List.unmodifiable([group.key]),
                ownerKey: ownerKey,
                ownerNode: owner,
                children: const [],
                templateNode: null,
                directSupplierCount: row.directSupplierCount,
                hasDirectSupplier: row.hasDirectSupplier,
                supplierLabel: index._supplierLabels[pair.row.nodeId]!,
                hasNamedSupplier: pair.row.supplierName != null,
                bomLabel: '',
                variantCount: 0,
                occurrenceKey: key,
                pairNode: pair,
                componentTrail: List.unmodifiable(path),
                componentPath: pathLabels.join(' › '),
                parentOutputUom: row.parentOutputUom,
              ),
            );
          }
        }
        collectComponents(row.children, path, pathLabels);
      }
    }

    collectComponents(boms, const [], [owner.row.itemTitle]);
  }

  final byLabel = <String, int>{};
  other.sort(
    (a, b) => index._sourceOrdinals[a.sourceKey.nodeId]!.compareTo(
      index._sourceOrdinals[b.sourceKey.nodeId]!,
    ),
  );
  final ranked = groups.values.toList()
    ..sort((a, b) {
      final byName = a.label.toLowerCase().compareTo(b.label.toLowerCase());
      return byName == 0 ? a.id.compareTo(b.id) : byName;
    });
  for (final group in ranked) {
    byLabel.update(group.label, (count) => count + 1, ifAbsent: () => 1);
  }
  return List.unmodifiable([
    for (final group in ranked) group.build(byLabel[group.label]! > 1),
    if (unsupplied.isNotEmpty)
      _groupRow(
        _noDirectGroup,
        unsupplied,
        SuppliersByItemSupplierGroup._(
          label: SuppliersByItemField.summaryNoDirectCount.label,
          directItemCount: unsupplied.length,
          isNoDirect: true,
        ),
      ),
    if (other.isNotEmpty)
      _groupRow(
        _otherRows,
        [
          for (final row in other)
            _copyBranch(row, _otherRows, const [_otherRows]),
        ],
        const SuppliersByItemSupplierGroup._(
          label: 'Other report rows',
          isOther: true,
        ),
      ),
  ]);
}

List<SuppliersByItemLayoutRow> _supplierViewOf(
  SuppliersByItemIndex index,
  bool showPlaceholders,
) => showPlaceholders
    ? index._supplierView
    : index._supplierViewWithoutPlaceholders;

List<SuppliersByItemLayoutRow> buildSupplierView(
  SuppliersByItemIndex index, {
  bool showPlaceholders = true,
  SuppliersByItemView view = const SuppliersByItemView(),
}) => List.unmodifiable([
  for (final row in _supplierViewOf(index, showPlaceholders))
    if (row.group!.isOther)
      row
    else
      row._withChildren([
        ...sortSiblings(
          row.children.where((child) => !child.isComponentMatch),
          view.sortField,
          view.sortDirection,
        ),
        ...sortSiblings(
          row.children.where((child) => child.isComponentMatch),
          view.sortField,
          view.sortDirection,
        ),
      ]),
]);

({String? uom, num value})? _sortValue(
  SuppliersByItemLayoutRow entry,
  SuppliersByItemSortField field,
) {
  switch (field) {
    case SuppliersByItemSortField.stock:
      final row = entry.node.row;
      final unit = row.stockUom;
      final balance = row.balanceQty;
      if (unit == null || balance == null) return null;
      if (row.kind == SuppliersByItemRowKind.template &&
          (entry.variantCount == 0 ||
              _variants(entry.node).any((node) => node.row.stockUom != unit))) {
        return null;
      }
      return (uom: unit, value: balance);
    case SuppliersByItemSortField.supplierCount:
      final count = entry.directSupplierCount;
      return count == null ? null : (uom: null, value: count);
    case SuppliersByItemSortField.lastPurchase:
      final pair = entry.pairNode;
      final links = pair == null ? entry._sortLinks ?? const [] : [pair];
      DateTime? latest;
      for (final supplier in links) {
        final date = strictReportDate(supplier.row.lastPurchaseDate);
        if (date != null && (latest == null || date.isAfter(latest))) {
          latest = date;
        }
      }
      return latest == null
          ? null
          : (uom: null, value: latest.millisecondsSinceEpoch);
  }
}

String _sortCode(SuppliersByItemLayoutRow entry) {
  final row = entry.node.row;
  return (row.kind == SuppliersByItemRowKind.template
          ? row.template
          : row.itemCode) ??
      '';
}

List<SuppliersByItemLayoutRow> sortSiblings(
  Iterable<SuppliersByItemLayoutRow> entries,
  SuppliersByItemSortField field,
  SuppliersByItemSortDirection direction,
) {
  final ranked = [
    for (final (ordinal, row) in entries.indexed)
      (row: row, ordinal: ordinal, key: _sortValue(row, field)),
  ];
  ranked.sort((a, b) {
    final keyA = a.key;
    final keyB = b.key;
    if (keyA != null && keyB == null) return -1;
    if (keyA == null && keyB != null) return 1;
    if (keyA != null && keyB != null) {
      if (keyA.uom case final unit?) {
        final byUnit = unit.compareTo(keyB.uom!);
        if (byUnit != 0) return byUnit;
      }
      if (keyA.value != keyB.value) {
        final byValue = keyA.value.compareTo(keyB.value);
        return direction == SuppliersByItemSortDirection.asc
            ? byValue
            : -byValue;
      }
    }
    final byCode = _sortCode(a.row).compareTo(_sortCode(b.row));
    if (byCode != 0) return byCode;
    final byOwner = (a.row.ownerNode?.row.itemCode ?? '').compareTo(
      b.row.ownerNode?.row.itemCode ?? '',
    );
    if (byOwner != 0) return byOwner;
    final byPath = a.row.sourceKey.nodeId.compareTo(b.row.sourceKey.nodeId);
    if (byPath != 0) return byPath;
    final byPair = (a.row.pairKey?.nodeId ?? '').compareTo(
      b.row.pairKey?.nodeId ?? '',
    );
    return byPair == 0 ? a.ordinal.compareTo(b.ordinal) : byPair;
  });
  return List.unmodifiable(ranked.map((entry) => entry.row));
}

class SuppliersByItemSummary {
  const SuppliersByItemSummary._({
    required this.itemCount,
    required this.supplierCount,
    required this.noDirectCount,
    required this.totalsByUom,
    required this.hasUnknownStockUom,
  });

  final int itemCount;
  final int supplierCount;
  final int noDirectCount;
  final Map<String, SuppliersByItemQuantityTotals> totalsByUom;
  final bool hasUnknownStockUom;
}

SuppliersByItemSummary summarize(SuppliersByItemIndex index) => index._summary;

SuppliersByItemSummary _summarize(SuppliersByItemIndex index) {
  final suppliers = index._linksByOwner.values
      .expand((links) => links)
      .map((supplier) => supplier.row.supplier)
      .nonNulls
      .toSet();
  final canonical = index.canonicalItems.values;
  return SuppliersByItemSummary._(
    itemCount: canonical.length,
    supplierCount: suppliers.length,
    noDirectCount: canonical
        .where(
          (node) =>
              (node.row.supplierCount ?? 0) <= 0 &&
              index._linksByOwner[_keyOf(node)]!.isEmpty,
        )
        .length,
    totalsByUom: Map.unmodifiable(
      SuppliersByItemNode.quantityTotalsByUom(index.roots),
    ),
    hasUnknownStockUom: canonical.any(
      (node) => node.row.stockUom == null && node.row.hasStockQuantities,
    ),
  );
}

class SuppliersByItemSearch {
  const SuppliersByItemSearch._({
    required this.isActive,
    this.matchingItemIds = const {},
    this.matchingOtherIds = const {},
    this.forcedOpen = const {},
    Set<SuppliersByItemRowKey> otherOccurrenceKeys = const {},
  }) : _otherOccurrenceKeys = otherOccurrenceKeys;

  final bool isActive;
  final Set<SuppliersByItemRowKey> matchingItemIds;
  final Set<SuppliersByItemRowKey> matchingOtherIds;
  final Set<SuppliersByItemRowKey> forcedOpen;
  final Set<SuppliersByItemRowKey> _otherOccurrenceKeys;
}

final _combiningMarksAndTatweel = RegExp(r'[\p{M}\u0640]', unicode: true);
final _whitespace = RegExp(r'\s+');

// Composed Latin letters with Latin base letters and combining accents.
const _latinAccents = {
  'a': 'àáâãäåāăąǎǟǡǻȁȃȧḁẚạảấầẩẫậắằẳẵặ',
  'b': 'ḃḅḇ',
  'c': 'çćĉċčḉ',
  'd': 'ďḋḍḏḑḓ',
  'e': 'èéêëēĕėęěȅȇȩḕḗḙḛḝẹẻẽếềểễệ',
  'f': 'ḟ',
  'g': 'ĝğġģǧǵḡ',
  'h': 'ĥȟḣḥḧḩḫẖ',
  'i': 'ìíîïĩīĭįǐȉȋḭḯỉị',
  'j': 'ĵǰ',
  'k': 'ķǩḱḳḵ',
  'l': 'ĺļľḷḹḻḽ',
  'm': 'ḿṁṃ',
  'n': 'ñńņňǹṅṇṉṋ',
  'o': 'òóôõöōŏőǒǫǭȍȏȫȭȯȱṍṏṑṓọỏốồổỗộớờởỡợ',
  'p': 'ṕṗ',
  'r': 'ŕŗřȑȓṙṛṝṟ',
  's': 'śŝşšșṡṣṥṧṩ',
  't': 'ţťțṫṭṯṱẗ',
  'u': 'ùúûüũūŭůűųǔǖǘǚǜȕȗṳṵṷṹṻụủứừửữự',
  'v': 'ṽṿ',
  'w': 'ŵẁẃẅẇẉẘ',
  'x': 'ẋẍ',
  'y': 'ýÿŷȳẏẙỳỵỷỹ',
  'z': 'źżžẑẓẕ',
};

final _accentBase = <int, int>{
  for (final entry in _latinAccents.entries)
    for (final accent in entry.value.runes) accent: entry.key.codeUnitAt(0),
};

String _fold(String value) => String.fromCharCodes(
  value.toLowerCase().runes.map((rune) => _accentBase[rune] ?? rune),
).replaceAll(_combiningMarksAndTatweel, '').trim().replaceAll(_whitespace, ' ');

Iterable<String?> _identityFields(SuppliersByItemLayoutRow entry) {
  final row = entry.node.row;
  return switch (row.kind) {
    SuppliersByItemRowKind.template => [row.itemTitle, row.distinctItemName],
    SuppliersByItemRowKind.item ||
    SuppliersByItemRowKind.component => [row.itemTitle, row.distinctItemName],
    SuppliersByItemRowKind.bom => [entry.bomLabel],
    SuppliersByItemRowKind.supplier => [_supplierName(row), row.supplier],
    SuppliersByItemRowKind.placeholder => const [],
  };
}

SuppliersByItemSearch searchIndex(
  SuppliersByItemIndex index,
  String query, {
  SuppliersByItemGroup group = SuppliersByItemGroup.template,
  bool showPlaceholders = true,
}) {
  if (query.trim().isEmpty) {
    return const SuppliersByItemSearch._(isActive: false);
  }
  final normalized = _fold(query);
  if (normalized.isEmpty) return const SuppliersByItemSearch._(isActive: true);
  final tokens = normalized.split(' ');
  final owners = <SuppliersByItemRowKey>{};
  final others = <SuppliersByItemRowKey>{};
  final forcedOpen = <SuppliersByItemRowKey>{};
  final ownerHits = <SuppliersByItemRowKey>{};
  final sourceHits = <SuppliersByItemSourceKey, SuppliersByItemLayoutRow>{};

  bool matches(List<String> trail) =>
      tokens.every((token) => trail.any((field) => field.contains(token)));

  void visit(
    SuppliersByItemLayoutRow row,
    List<String> inherited,
    SuppliersByItemRowKey root,
  ) {
    final trail = [
      ...inherited,
      ..._identityFields(row).whereType<String>().map(_fold),
    ];
    if (!matches(trail)) {
      for (final child in row.children) {
        visit(child, trail, root);
      }
      return;
    }
    forcedOpen.addAll(row.ancestorKeys);
    if (row.ownerKey case final owner?) {
      owners.add(owner);
      if (index._sourceOwners.contains(row.node)) {
        ownerHits.add(owner);
      } else {
        sourceHits[row.sourceKey] = row;
      }
    } else if (row.node.row.kind == SuppliersByItemRowKind.template &&
        row.variantCount > 0) {
      final variants = row.children.map((child) => child.ownerKey).nonNulls;
      owners.addAll(variants);
      ownerHits.addAll(variants);
      forcedOpen.add(row.key);
    } else {
      others.add(root);
      sourceHits[row.sourceKey] = row;
    }
  }

  for (final row in buildTemplateView(index)) {
    final template = row.templateNode;
    final context = [
      if (template != null) ...[
        _fold(template.row.itemTitle),
        if (template.row.distinctItemName case final name?) _fold(name),
      ],
    ];
    if (template != null && matches(context)) {
      owners.add(row.ownerKey!);
      ownerHits.add(row.ownerKey!);
    } else {
      visit(row, context, row.key);
    }
  }
  final trails = group == SuppliersByItemGroup.template
      ? null
      : _supplierSearchTrails(
          index,
          _supplierViewOf(index, showPlaceholders),
          ownerHits,
          sourceHits,
        );
  return SuppliersByItemSearch._(
    isActive: true,
    matchingItemIds: Set.unmodifiable(owners),
    matchingOtherIds: Set.unmodifiable(others),
    forcedOpen: Set.unmodifiable(trails?.forced ?? forcedOpen),
    otherOccurrenceKeys: Set.unmodifiable(trails?.otherOccurrenceKeys ?? {}),
  );
}

({
  Set<SuppliersByItemRowKey> forced,
  Set<SuppliersByItemRowKey> otherOccurrenceKeys,
})
_supplierSearchTrails(
  SuppliersByItemIndex index,
  List<SuppliersByItemLayoutRow> groups,
  Set<SuppliersByItemRowKey> ownerHits,
  Map<SuppliersByItemSourceKey, SuppliersByItemLayoutRow> sourceHits,
) {
  final forced = <SuppliersByItemRowKey>{};
  final otherOccurrenceKeys = <SuppliersByItemRowKey>{};
  final revealed = <SuppliersByItemSourceKey>{};
  final directHits =
      <
        (SuppliersByItemRowKey, SuppliersByItemSourceKey),
        List<SuppliersByItemSourceKey>
      >{};
  for (final hit in sourceHits.values) {
    final pair = hit.pairNode;
    final owner = hit.ownerKey;
    if (pair == null || owner == null) continue;
    if (index._sourceOwners.contains(index.nodesById[pair.row.parentId])) {
      final membership = (_supplierGroupKey(pair), owner);
      (directHits[membership] ??= []).add(hit.sourceKey);
    }
  }

  for (final group in groups) {
    for (final row in group.children) {
      if (!row.isComponentMatch) {
        final owner = row.ownerKey;
        if (owner == null) continue;
        if (ownerHits.contains(owner)) forced.add(group.key);
        if (directHits[(group.key, owner)] case final pairs?) {
          forced.add(group.key);
          revealed.addAll(pairs);
        }
        continue;
      }

      if (row.pairKey case final pair? when sourceHits.containsKey(pair)) {
        forced.add(group.key);
        revealed.add(pair);
      }
      if (sourceHits.containsKey(row.sourceKey)) {
        forced.add(group.key);
        revealed.add(row.sourceKey);
      }
    }
  }

  // A source hit with no supplier membership still has its original branch.
  final remaining = sourceHits.keys.toSet().difference(revealed);
  void revealOriginal(
    SuppliersByItemLayoutRow row,
    SuppliersByItemRowKey? otherRoot,
  ) {
    if (remaining.remove(row.sourceKey)) {
      forced.addAll(row.ancestorKeys);
      if (otherRoot != null) otherOccurrenceKeys.add(otherRoot);
    }
    for (final child in row.children) {
      if (remaining.isEmpty) return;
      revealOriginal(child, otherRoot);
    }
  }

  for (final group in groups) {
    for (final row in group.children) {
      if (remaining.isEmpty) break;
      if (!row.isComponentMatch) {
        revealOriginal(row, group.group!.isOther ? row.key : null);
      }
    }
  }
  return (forced: forced, otherOccurrenceKeys: otherOccurrenceKeys);
}

class SuppliersByItemVisibleRows {
  const SuppliersByItemVisibleRows._(this.rows, this.indexByKey);

  final List<SuppliersByItemLayoutRow> rows;
  final Map<SuppliersByItemRowKey, int> indexByKey;
}

bool _retainsBranch(
  SuppliersByItemLayoutRow row,
  SuppliersByItemSearch search,
) =>
    search._otherOccurrenceKeys.contains(row.key) ||
    (row.group == null &&
        row.ownerKey == null &&
        search.matchingOtherIds.contains(row.sourceKey)) ||
    search.matchingItemIds.contains(row.ownerKey);

bool _retainsRow(SuppliersByItemLayoutRow row, SuppliersByItemSearch search) =>
    _retainsBranch(row, search) ||
    row.children.any((child) => _retainsRow(child, search));

SuppliersByItemVisibleRows flattenTemplateView(
  List<SuppliersByItemLayoutRow> projection,
  Set<SuppliersByItemRowKey> open, {
  SuppliersByItemSearch? search,
}) {
  final active = search?.isActive == true ? search : null;
  final rows = <SuppliersByItemLayoutRow>[];
  final indexByKey = <SuppliersByItemRowKey, int>{};

  void visit(List<SuppliersByItemLayoutRow> candidates, bool keepBranch) {
    for (var row in candidates) {
      if (active != null && !keepBranch) {
        final group = row.group;
        if (group != null && !group.isOther) {
          final retained = <SuppliersByItemLayoutRow>[];
          var components = 0;
          // Each supplier entry retains the whole branch of its matched owner.
          for (final child in row.children) {
            if (!active.matchingItemIds.contains(child.ownerKey)) continue;
            retained.add(child);
            if (child.isComponentMatch) components++;
          }
          if (retained.isEmpty) continue;
          row = row._withChildren(
            retained,
            group: group._withRetainedCounts(
              retained.length - components,
              components,
            ),
          );
        } else if (!_retainsRow(row, active)) {
          continue;
        }
      }
      indexByKey[row.key] = rows.length;
      rows.add(row);
      if (open.contains(row.key) ||
          active?.forcedOpen.contains(row.key) == true) {
        visit(
          row.children,
          keepBranch || (active != null && _retainsBranch(row, active)),
        );
      }
    }
  }

  visit(projection, false);
  return SuppliersByItemVisibleRows._(
    List.unmodifiable(rows),
    Map.unmodifiable(indexByKey),
  );
}

Set<SuppliersByItemRowKey> structuralKeys(
  List<SuppliersByItemLayoutRow> projection, {
  SuppliersByItemSearch? search,
}) {
  final active = search?.isActive == true ? search : null;
  final keys = <SuppliersByItemRowKey>{};

  void visit(List<SuppliersByItemLayoutRow> rows, bool keepBranch) {
    for (final row in rows) {
      if (row.children.isEmpty ||
          (active != null && !keepBranch && !_retainsRow(row, active))) {
        continue;
      }
      keys.add(row.key);
      visit(
        row.children,
        keepBranch || (active != null && _retainsBranch(row, active)),
      );
    }
  }

  visit(projection, false);
  return Set.unmodifiable(keys);
}

Set<SuppliersByItemRowKey> defaultExpansion(
  SuppliersByItemIndex index,
  List<SuppliersByItemLayoutRow> projection, {
  SuppliersByItemGroup group = SuppliersByItemGroup.template,
}) => group == SuppliersByItemGroup.supplier
    ? Set.unmodifiable({if (projection.isNotEmpty) projection.first.key})
    : Set.unmodifiable({
        for (final row in projection)
          if (row.children.isNotEmpty && row.variantCount >= 2) row.key,
        if (index.canonicalItems.length == 1)
          for (final row in projection)
            if (row.children.isNotEmpty && row.key == row.ownerKey) row.key,
      });

final _dateOnly = RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$');

DateTime? strictReportDate(String? value) {
  if (value == null || !_dateOnly.hasMatch(value)) return null;
  final year = int.parse(value.substring(0, 4));
  final month = int.parse(value.substring(5, 7));
  final day = int.parse(value.substring(8, 10));
  final date = DateTime.utc(year, month, day);
  return year > 0 && date.year == year && date.month == month && date.day == day
      ? date
      : null;
}
