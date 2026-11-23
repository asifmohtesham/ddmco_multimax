/// Outcome of resolving a Rack document's `warehouse` field.
enum RackLookupStatus {
  /// Rack document exists; [RackWarehouseLookup.warehouse] holds its
  /// warehouse link (null when the field is unset on the doc).
  found,

  /// Server answered 404 — the rack does not exist.
  notFound,

  /// Network / timeout / unexpected failure — existence unknown.
  error,
}

/// Result wrapper for `ApiProvider.getRackWarehouse`.
class RackWarehouseLookup {
  final RackLookupStatus status;
  final String? warehouse;
  final String? name;

  const RackWarehouseLookup.found(this.warehouse, {this.name})
      : status = RackLookupStatus.found;

  const RackWarehouseLookup.notFound()
      : status = RackLookupStatus.notFound,
        warehouse = null,
        name = null;

  const RackWarehouseLookup.error()
      : status = RackLookupStatus.error,
        warehouse = null,
        name = null;
}
