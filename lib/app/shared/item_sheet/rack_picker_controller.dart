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
    if (requestedQty <= 0)          return SufficiencyStatus.unknown;
    if (availableQty <= 0)          return SufficiencyStatus.empty;
    if (availableQty >= requestedQty) return SufficiencyStatus.sufficient;
    return SufficiencyStatus.low;
  }

  bool get isSufficient => status == SufficiencyStatus.sufficient;

  /// Warehouse name derived locally from the rack asset code.
  /// Falls back to an empty string when [location] is null.
  String get warehouseName => location?.warehouseName ?? '';

  /// Human-readable physical location label (e.g. `'Aisle 101 \u00b7 Shelf A'`).
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
/// await ctrl.load(
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

  /// Whether a Stock Ledger fetch is in progress.
  var isLoading = false.obs;

  /// Sorted list of rack entries for the picker list.
  var entries = <RackPickerEntry>[].obs;

  /// The rack currently written into the rack field (may be empty).
  var selectedRack = ''.obs;

  /// Non-null when the Stock Ledger fetch failed and the picker fell back
  /// to [rackStockMap]. Shown as a subtle info banner in the sheet.
  var usedFallback = false.obs;

  // ── Input context (set by load()) ────────────────────────────────────

  String _itemCode    = '';
  String _batchNo     = '';
  String _warehouse   = '';
  double _requestedQty = 0.0;

  String get itemCode     => _itemCode;
  String get batchNo      => _batchNo;
  String get warehouse    => _warehouse;
  double get requestedQty => _requestedQty;

  // ── load() ─────────────────────────────────────────────────────────────────

  /// Fetches rack availability data and populates [entries].
  ///
  /// Call this immediately after `Get.put()`, before showing the sheet.
  ///
  /// Parameters:
  /// - [itemCode]    : ERPNext item code.
  /// - [batchNo]     : Active batch number; may be empty for non-batch items.
  /// - [warehouse]   : Resolved warehouse name (e.g. `'WH-DXB1 - KA'`).
  /// - [requestedQty]: Value from the qty field; used for sufficiency bars.
  /// - [currentRack] : Rack already written into the rack field; shown as
  ///                   selected (highlighted) in the picker list.
  /// - [fallbackMap] : [ItemSheetControllerBase.rackStockMap] — used when
  ///                   Stock Ledger returns an empty map.
  Future<void> load({
    required String             itemCode,
    required String             batchNo,
    required String             warehouse,
    required double             requestedQty,
    required String             currentRack,
    required Map<String, double> fallbackMap,
  }) async {
    _itemCode     = itemCode;
    _batchNo      = batchNo;
    _warehouse    = warehouse;
    _requestedQty = requestedQty;
    selectedRack.value = currentRack;
    usedFallback.value = false;
    isLoading.value    = true;

    try {
      // ── 1. Primary: Stock Ledger (per-batch per-rack) ───────────────────
      Map<String, double> stockMap = {};

      if (batchNo.isNotEmpty) {
        stockMap = await _api.getRackBatchStock(
          itemCode:  itemCode,
          batchNo:   batchNo,
          warehouse: warehouse,
        );
      }

      // ── 2. Fallback: rackStockMap (Stock Balance, already loaded) ───────
      // Merge strategy: fallbackMap fills the base, stockMap overwrites
      // where present — giving the most accurate per-batch value per rack.
      if (stockMap.isEmpty) {
        usedFallback.value = true;
        stockMap = Map<String, double>.from(fallbackMap);
      } else {
        // Merge: start with fallback (broader), overwrite with ledger data.
        final merged = Map<String, double>.from(fallbackMap);
        merged.addAll(stockMap);
        stockMap = merged;
      }

      // ── 3. Build + sort entries ────────────────────────────────────────────
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

  /// Count of sufficient-stock racks.
  int get sufficientCount =>
      entries.where((e) => e.isSufficient).length;

  /// Count of racks with any stock (including low).
  int get withStockCount =>
      entries.where((e) => e.availableQty > 0).length;
}
