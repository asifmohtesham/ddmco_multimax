import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'package:multimax/app/data/providers/api_provider.dart';
import 'rack_location.dart';

// ── SufficiencyStatus ─────────────────────────────────────────────────────────

/// Represents how well a rack's available quantity covers the requested qty.
enum SufficiencyStatus {
  /// `availableQty >= requestedQty > 0` — rack can fully satisfy the request.
  sufficient,

  /// `0 < availableQty < requestedQty` — rack has stock but not enough.
  low,

  /// `availableQty <= 0` — rack is empty for this item/batch.
  empty,

  /// `requestedQty == 0` — qty field is blank; sufficiency is indeterminate.
  unknown,
}

// ── RackPickerEntry ──────────────────────────────────────────────────────────

/// Immutable data record for a single row in [RackPickerSheet].
///
/// [location] may be `null` when the rack name does not conform to the
/// expected 4-part pattern; callers fall back to [rackName] in that case.
@immutable
class RackPickerEntry {
  /// Raw rack asset-code name, e.g. `'KA-WH-DXB1-101A'`.
  final String rackName;

  /// Structured location decoded from [rackName]. `null` if unparseable.
  final RackLocation? location;

  /// Available quantity for the current item + batch in this rack.
  final double availableQty;

  /// Quantity the operator is trying to pick (from the qty field).
  final double requestedQty;

  const RackPickerEntry({
    required this.rackName,
    required this.location,
    required this.availableQty,
    required this.requestedQty,
  });

  // ── Derived ───────────────────────────────────────────────────────────────

  SufficiencyStatus get status {
    if (requestedQty <= 0)            return SufficiencyStatus.unknown;
    if (availableQty <= 0)            return SufficiencyStatus.empty;
    if (availableQty >= requestedQty) return SufficiencyStatus.sufficient;
    return SufficiencyStatus.low;
  }

  bool get isSufficient => status == SufficiencyStatus.sufficient;

  /// Warehouse name derived locally from the rack asset code.
  /// Falls back to an empty string when [location] is null.
  String get warehouseName => location?.warehouseName ?? '';

  /// Human-readable physical location label (e.g. `'Aisle 101 · Shelf A'`).
  /// Falls back to [rackName] when [location] is null.
  String get displayLabel => location?.displayLabel ?? rackName;

  /// Compact shelf identifier (e.g. `'101A'`).
  String get shortLabel => location?.shortLabel ?? rackName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RackPickerEntry &&
          runtimeType == other.runtimeType &&
          rackName == other.rackName;

  @override
  int get hashCode => rackName.hashCode;
}

// ── RackPickerController ───────────────────────────────────────────────────────

/// On-demand GetX controller that fetches and sorts rack availability data
/// for display in [RackPickerSheet].
///
/// ## Data source
/// Uses [ApiProvider.getStockBalanceWithDimension] (Stock Balance report)
/// which returns per-rack qty rows for a given item + warehouse + batch.
/// Falls back to [fallbackMap] (pre-loaded rackStockMap from the item sheet)
/// if the live fetch returns empty.
///
/// ## Instantiation
/// Created by the picker button in [ValidatedRackField] via `Get.put()`
/// with a unique tag so multiple sheets (source + target in SE) can coexist:
/// ```dart
/// Get.put(RackPickerController(), tag: 'source_rack');
/// ```
/// Deleted when the picker sheet closes:
/// ```dart
/// Get.delete<RackPickerController>(tag: 'source_rack');
/// ```
///
/// ## Usage
/// ```dart
/// final ctrl = Get.put(RackPickerController(), tag: tag);
/// ctrl.load(
///   itemCode:     'ITEM-001',
///   batchNo:      'BATCH-001',
///   warehouse:    'WH-DXB1 - KA',
///   requestedQty: 5.0,
///   currentRack:  'KA-WH-DXB1-101A',
///   fallbackMap:  rackStockMap,         // from ItemSheetControllerBase
/// );
/// ```
class RackPickerController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  // ── Observable state ─────────────────────────────────────────────────────

  /// Whether a Stock Balance fetch is in progress.
  var isLoading = false.obs;

  /// Full sorted list of rack entries (all warehouses).
  /// The sheet displays [visibleEntries] which may be a filtered subset.
  var entries = <RackPickerEntry>[].obs;

  /// The rack currently written into the rack field (may be empty).
  var selectedRack = ''.obs;

  /// Non-null when the Stock Balance fetch failed and the picker fell back
  /// to [fallbackMap]. Shown as a subtle info banner in the sheet.
  var usedFallback = false.obs;

  /// Whether to restrict the visible list to racks whose warehouse matches
  /// the document-level [warehouse]. Defaults to `true` (On).
  /// Disabled automatically when [warehouse] is empty.
  var filterByWarehouse = true.obs;

  // ── Input context (set by load()) ────────────────────────────────────

  String _itemCode     = '';
  String _batchNo      = '';
  String _warehouse    = '';
  double _requestedQty = 0.0;

  String get itemCode     => _itemCode;
  String get batchNo      => _batchNo;
  String get warehouse    => _warehouse;
  double get requestedQty => _requestedQty;

  // ── Derived / filtered list ───────────────────────────────────────────────

  /// Subset of [entries] shown in the sheet.
  ///
  /// When [filterByWarehouse] is `true` **and** [warehouse] is non-empty,
  /// only entries whose [RackPickerEntry.warehouseName] matches [warehouse]
  /// are returned. Otherwise the full [entries] list is returned.
  List<RackPickerEntry> get visibleEntries {
    if (filterByWarehouse.value && _warehouse.isNotEmpty) {
      return entries
          .where((e) => e.warehouseName == _warehouse)
          .toList();
    }
    return entries;
  }

  /// Count of sufficient-stock racks in the **visible** list.
  int get visibleSufficientCount =>
      visibleEntries.where((e) => e.isSufficient).length;

  // ── load() ─────────────────────────────────────────────────────────────────

  /// Fetches rack availability from the Stock Balance report and populates
  /// [entries].
  ///
  /// Call this immediately after `Get.put()` without awaiting — the sheet
  /// opens immediately and its [isLoading] spinner resolves when the fetch
  /// completes.
  ///
  /// Parameters:
  /// - [itemCode]    : ERPNext item code.
  /// - [batchNo]     : Active batch number; may be empty for non-batch items.
  /// - [warehouse]   : Resolved warehouse name (e.g. `'WH-DXB1 - KA'`).
  /// - [requestedQty]: Value from the qty field; used for sufficiency bars.
  /// - [currentRack] : Rack already written into the rack field; shown as
  ///                   selected (highlighted) in the picker list.
  /// - [fallbackMap] : [ItemSheetControllerBase.rackStockMap] — used when
  ///                   the Stock Balance report returns an empty result.
  Future<void> load({
    required String              itemCode,
    required String              batchNo,
    required String              warehouse,
    required double              requestedQty,
    required String              currentRack,
    required Map<String, double> fallbackMap,
  }) async {
    _itemCode     = itemCode;
    _batchNo      = batchNo;
    _warehouse    = warehouse;
    _requestedQty = requestedQty;
    selectedRack.value      = currentRack;
    usedFallback.value      = false;
    filterByWarehouse.value = true;   // reset to On on every fresh load
    isLoading.value         = true;

    try {
      // ── 1. Primary: Stock Balance with Dimension (per-rack qty) ──────────
      // Returns rows: [{custom_rack: 'KA-WH-DXB1-101A', qty: 12.0}, ...]
      // Filtered by itemCode + warehouse + batchNo (if present).
      final rows = await _api.getStockBalanceWithDimension(
        itemCode:  itemCode,
        warehouse: warehouse.isNotEmpty ? warehouse : null,
        batchNo:   batchNo.isNotEmpty   ? batchNo   : null,
      );

      // Collapse rows into a {rackId → qty} map (sum duplicate rack entries).
      final liveMap = <String, double>{};
      for (final row in rows) {
        final rack = (row['custom_rack'] ?? '').toString().trim();
        if (rack.isEmpty) continue;
        final qty = (row['qty'] as num?)?.toDouble() ?? 0.0;
        liveMap[rack] = (liveMap[rack] ?? 0.0) + qty;
      }

      // ── 2. Merge / fallback ───────────────────────────────────────────────
      // If live fetch returned nothing, fall back to the pre-loaded
      // rackStockMap (already fetched by preloadRackStockMap via
      // getStockBalanceWithDimension, so data shape is identical).
      Map<String, double> stockMap;
      if (liveMap.isEmpty) {
        usedFallback.value = true;
        stockMap = Map<String, double>.from(fallbackMap);
      } else {
        // Start with fallback (broader coverage), overwrite with live data.
        stockMap = Map<String, double>.from(fallbackMap)..addAll(liveMap);
      }

      // ── 3. Build + sort entries ───────────────────────────────────────────
      final built = stockMap.entries.map((e) {
        return RackPickerEntry(
          rackName:     e.key,
          location:     RackLocation.tryParse(e.key),
          availableQty: e.value,
          requestedQty: requestedQty,
        );
      }).toList();

      built.sort(_compareEntries);
      entries.assignAll(built);
    } catch (_) {
      // On any error, surface fallback data so the sheet is never fully empty.
      usedFallback.value = true;
      final built = fallbackMap.entries.map((e) {
        return RackPickerEntry(
          rackName:     e.key,
          location:     RackLocation.tryParse(e.key),
          availableQty: e.value,
          requestedQty: requestedQty,
        );
      }).toList();
      built.sort(_compareEntries);
      entries.assignAll(built);
    } finally {
      isLoading.value = false;
    }
  }

  // ── Sorting ─────────────────────────────────────────────────────────────────

  /// Sort order:
  /// 1. Sufficient racks before insufficient/empty racks.
  /// 2. Within each group: descending available qty.
  /// 3. Ties: ascending aisle number then ascending shelf letter,
  ///    preserving physical adjacency in the list.
  static int _compareEntries(RackPickerEntry a, RackPickerEntry b) {
    // ── Group: sufficient first ──
    final aSuf = a.isSufficient ? 0 : 1;
    final bSuf = b.isSufficient ? 0 : 1;
    if (aSuf != bSuf) return aSuf.compareTo(bSuf);

    // ── Within group: higher qty first ──
    final qtyComp = b.availableQty.compareTo(a.availableQty);
    if (qtyComp != 0) return qtyComp;

    // ── Tie-break: physical location (aisle asc, shelf asc) ──
    final aAisle = a.location?.aisleNumber ?? 9999;
    final bAisle = b.location?.aisleNumber ?? 9999;
    final aisleComp = aAisle.compareTo(bAisle);
    if (aisleComp != 0) return aisleComp;

    final aShelf = a.location?.shelfLetter ?? 'Z';
    final bShelf = b.location?.shelfLetter ?? 'Z';
    return aShelf.compareTo(bShelf);
  }

  // ── Selection ─────────────────────────────────────────────────────────────────

  /// Mark [rack] as selected. Called from [RackPickerSheet] when the user
  /// taps a tile. The sheet's [onSelected] callback fires immediately after.
  void selectRack(String rack) {
    selectedRack.value = rack;
  }

  // ── Helpers for the sheet UI ──────────────────────────────────────────────

  /// Count of sufficient-stock racks in the full (unfiltered) list.
  int get sufficientCount =>
      entries.where((e) => e.isSufficient).length;

  /// Count of racks with any stock (including low) in the full list.
  int get withStockCount =>
      entries.where((e) => e.availableQty > 0).length;
}
