import 'dart:convert';

enum RackSide {
  source('source warehouse'),
  target('target warehouse'),
  outbound('warehouse');

  const RackSide(this.label);
  final String label;
}

enum RackPairIssue {
  mismatch,
  notFound,
  invalidWarehouse,
  unavailable,
  inapplicable,
  warehouseRequired,
}

class RackPairVerdict {
  const RackPairVerdict({
    required this.rack,
    required this.side,
    this.warehouse,
    this.rowWarehouse,
    this.issue,
  });

  final String rack;
  final RackSide side;
  final String? warehouse;
  final String? rowWarehouse;
  final RackPairIssue? issue;

  bool get isValid => issue == null;

  String get message => switch (issue) {
    null => '',
    RackPairIssue.mismatch =>
      'Rack $rack belongs to $warehouse. This row’s ${side.label} is $rowWarehouse.',
    RackPairIssue.notFound =>
      'Rack $rack was not found. Scan or choose a Rack.',
    RackPairIssue.invalidWarehouse =>
      'Rack $rack has no valid warehouse. Choose another rack or ask your supervisor to update the Rack.',
    RackPairIssue.unavailable =>
      'Could not check the warehouse for rack $rack. Retry or choose another rack.',
    RackPairIssue.inapplicable =>
      'This row has no ${side.label}. Clear rack $rack.',
    RackPairIssue.warehouseRequired =>
      'Choose a ${side.label} to check rack $rack.',
  };

  String get savedMessage => switch (issue) {
    null => '',
    RackPairIssue.mismatch =>
      'Saved rack $rack belongs to $warehouse. This row’s ${side.label} is $rowWarehouse.',
    _ =>
      'Could not verify saved rack $rack. Check the rack and warehouse before submitting.',
  };
}

class RackWarehouse {
  const RackWarehouse({
    required this.name,
    required this.warehouseName,
    required this.company,
    this.isGroup = false,
    this.disabled = false,
  });

  final String name;
  final String warehouseName;
  final String company;
  final bool isGroup;
  final bool disabled;

  bool isActiveLeaf(String documentCompany) =>
      company == documentCompany && !isGroup && !disabled;
}

String? warehouseValue(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// The only accepted alternate to an exact Rack document name.
String? rackAlias(String rack, String? abbreviation) {
  final abbr = warehouseValue(abbreviation);
  if (abbr == null) return null;
  final suffix = ' - $abbr';
  if (!rack.endsWith(suffix)) return null;
  return warehouseValue(rack.substring(0, rack.length - suffix.length));
}

/// A linked but invalid Warehouse never falls back to this name rule.
String? warehouseFromRackPrefix({
  required String rack,
  required String company,
  required String abbreviation,
  required Iterable<RackWarehouse> warehouses,
}) {
  if (abbreviation.trim().isEmpty) return null;
  var longest = 0;
  final matches = <String>{};
  for (final warehouse in warehouses) {
    if (!warehouse.isActiveLeaf(company) ||
        warehouse.warehouseName.trim().isEmpty) {
      continue;
    }
    final prefix = '$abbreviation-${warehouse.warehouseName}-';
    if (prefix.length < longest ||
        !rack.startsWith(prefix) ||
        rack.substring(prefix.length).trim().isEmpty) {
      continue;
    }
    if (prefix.length > longest) {
      longest = prefix.length;
      matches.clear();
    }
    matches.add(warehouse.name);
  }
  return matches.length == 1 ? matches.single : null;
}

RackPairVerdict evaluateRackPair({
  required String rack,
  required RackSide side,
  String? rackWarehouse,
  String? rowWarehouse,
  bool applicable = true,
  bool initializeWarehouse = false,
  RackPairIssue? lookupIssue,
}) {
  final row = warehouseValue(rowWarehouse);
  final warehouse = warehouseValue(rackWarehouse);
  final issue = switch ((
    rack.isEmpty,
    applicable,
    lookupIssue,
    warehouse,
    row,
  )) {
    (true, _, _, _, _) => null,
    (_, false, _, _, _) => RackPairIssue.inapplicable,
    (_, _, final RackPairIssue issue, _, _) => issue,
    (_, _, _, null, _) => RackPairIssue.invalidWarehouse,
    (_, _, _, _, _) when initializeWarehouse => null,
    (_, _, _, _, null) => RackPairIssue.warehouseRequired,
    (_, _, _, _, _) when row != warehouse => RackPairIssue.mismatch,
    _ => null,
  };
  return RackPairVerdict(
    rack: rack,
    side: side,
    warehouse: warehouse,
    rowWarehouse: issue == null && initializeWarehouse ? warehouse : row,
    issue: issue,
  );
}

class WarehouseDivergence {
  WarehouseDivergence({
    required this.side,
    required String? warehouse,
    String? header,
    Iterable<String?> peers = const [],
    String? soWarehouse,
    String? soLine,
  }) : warehouse = warehouseValue(warehouse),
       header = warehouseValue(header),
       peers = (peers.map(warehouseValue).nonNulls.toSet().toList()..sort()),
       soWarehouse = warehouseValue(soWarehouse),
       soLine = warehouseValue(soLine);

  final RackSide side;
  final String? warehouse;
  final String? header;
  final List<String> peers;
  final String? soWarehouse;
  final String? soLine;

  String get key =>
      jsonEncode([side.name, warehouse, header, soWarehouse, peers]);

  List<String> get messages {
    if (warehouse == null) return const [];
    final distinctOthers = peers.where((peer) => peer != warehouse).toList();
    final row = 'This row’s ${side.label} is $warehouse.';
    return [
      if (header != null && header != warehouse)
        '$row The document default is $header.',
      if (distinctOthers.isNotEmpty)
        '$row Other rows use ${distinctOthers.join(', ')}.',
      if (soWarehouse != null && soWarehouse != warehouse)
        '$row ${soLine == null ? 'The Sales Order line' : 'Sales Order line $soLine'} uses $soWarehouse.',
    ];
  }
}

/// Immutable saved/candidate snapshot used to detect changes that need repair.
class RackRowSnapshot {
  const RackRowSnapshot({
    this.item,
    this.batch,
    this.warehouse,
    this.rack,
    required this.applies,
    required this.quantity,
  });

  final String? item;
  final String? batch;
  final String? warehouse;
  final String? rack;
  final bool applies;
  final double quantity;

  bool canRetain(RackRowSnapshot current, {bool submitting = false}) =>
      !submitting &&
      item == current.item &&
      warehouseValue(batch) == warehouseValue(current.batch) &&
      warehouseValue(warehouse) == warehouseValue(current.warehouse) &&
      warehouseValue(rack) == warehouseValue(current.rack) &&
      applies == current.applies &&
      quantity * current.quantity >= 0 &&
      current.quantity.abs() <= quantity.abs();
}
