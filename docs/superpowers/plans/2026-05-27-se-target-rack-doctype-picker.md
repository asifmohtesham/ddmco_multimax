# SE Target Rack DocType Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Stock Balance API call in the target rack picker with a direct Rack DocType query so the sheet lists all racks for the target warehouse rather than only racks that already hold the scanned item.

**Architecture:** Add `ApiProvider.parseRacksByWarehouseResponse` (static, testable) and `getRacksByWarehouse` (HTTP), then add `isTargetMode: RxBool` and `loadForTarget()` to `RackPickerController`. Adapt `RackPickerSheet` to suppress stock-centric UI when `isTargetMode` is true. Switch `TargetRackFieldAdapter.browseRacks()` to call `loadForTarget()` instead of `load()`.

**Tech Stack:** Flutter / Dart, GetX, Dio, `flutter_test`

---

## Files

| Action | Path | What changes |
|--------|------|-------------|
| Modify | `lib/app/data/providers/api_provider.dart` | Add `parseRacksByWarehouseResponse` (static) + `getRacksByWarehouse` |
| Modify | `lib/app/shared/item_sheet/rack_picker_controller.dart` | Add `isTargetMode`, `loadForTarget`, `_compareEntriesByLocation` |
| Modify | `lib/app/shared/item_sheet/rack_picker_sheet.dart` | `isTargetMode` awareness in tile, empty state, summary badge |
| Modify | `lib/app/shared/item_sheet/dual_rack_adapters.dart` | `TargetRackFieldAdapter.browseRacks()` calls `loadForTarget` |
| Create | `test/unit/get_racks_by_warehouse_response_test.dart` | Unit tests for `parseRacksByWarehouseResponse` |
| Create | `test/unit/rack_picker_controller_target_mode_test.dart` | Unit tests for `loadForTarget` on the controller |

---

## Task 1: `ApiProvider.parseRacksByWarehouseResponse` + `getRacksByWarehouse` + unit tests

**Files:**
- Modify: `lib/app/data/providers/api_provider.dart` (after the `getListSimple` method, ~line 279)
- Create: `test/unit/get_racks_by_warehouse_response_test.dart`

`parseRacksByWarehouseResponse` is a static method, just like `parseUploadFileResponse` and `parseItemVariantDetailsResponse` already in `ApiProvider`. Write tests first, then implement.

- [ ] **Step 1: Create the test file**

```dart
// test/unit/get_racks_by_warehouse_response_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.parseRacksByWarehouseResponse', () {
    test('T-1: returns empty list when data is null', () {
      expect(ApiProvider.parseRacksByWarehouseResponse(null), isEmpty);
    });

    test('T-2: returns empty list when data["data"] key is absent', () {
      expect(
        ApiProvider.parseRacksByWarehouseResponse(<String, dynamic>{'other': 'value'}),
        isEmpty,
      );
    });

    test('T-3: returns empty list when data["data"] is an empty list', () {
      expect(
        ApiProvider.parseRacksByWarehouseResponse(<String, dynamic>{'data': []}),
        isEmpty,
      );
    });

    test('T-4: extracts name strings from a well-formed response', () {
      final data = <String, dynamic>{
        'data': [
          {'name': 'KA-WH-DXB1-101A'},
          {'name': 'KA-WH-DXB1-101B'},
          {'name': 'KA-WH-DXB1-102A'},
        ],
      };
      expect(
        ApiProvider.parseRacksByWarehouseResponse(data),
        equals(['KA-WH-DXB1-101A', 'KA-WH-DXB1-101B', 'KA-WH-DXB1-102A']),
      );
    });

    test('T-5: skips entries where name is null', () {
      final data = <String, dynamic>{
        'data': [
          {'name': 'KA-WH-DXB1-101A'},
          {'name': null},
          {'name': 'KA-WH-DXB1-102A'},
        ],
      };
      expect(
        ApiProvider.parseRacksByWarehouseResponse(data),
        equals(['KA-WH-DXB1-101A', 'KA-WH-DXB1-102A']),
      );
    });

    test('T-6: skips entries where name is an empty string', () {
      final data = <String, dynamic>{
        'data': [
          {'name': 'KA-WH-DXB1-101A'},
          {'name': ''},
          {'name': 'KA-WH-DXB1-102A'},
        ],
      };
      expect(
        ApiProvider.parseRacksByWarehouseResponse(data),
        equals(['KA-WH-DXB1-101A', 'KA-WH-DXB1-102A']),
      );
    });

    test('T-7: skips null and non-Map entries in the data list', () {
      final data = <String, dynamic>{
        'data': [
          {'name': 'KA-WH-DXB1-101A'},
          null,
          42,
          {'name': 'KA-WH-DXB1-102A'},
        ],
      };
      expect(
        ApiProvider.parseRacksByWarehouseResponse(data),
        equals(['KA-WH-DXB1-101A', 'KA-WH-DXB1-102A']),
      );
    });

    test('T-8: returns empty list when data["data"] is not a List', () {
      final data = <String, dynamic>{'data': 'not-a-list'};
      expect(ApiProvider.parseRacksByWarehouseResponse(data), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests — expect failure** (method does not exist yet)

```
flutter test test/unit/get_racks_by_warehouse_response_test.dart --reporter expanded
```

Expected: compilation error — `parseRacksByWarehouseResponse` is not defined.

- [ ] **Step 3: Add `parseRacksByWarehouseResponse` and `getRacksByWarehouse` to `ApiProvider`**

File: `lib/app/data/providers/api_provider.dart`

Locate the end of `getListSimple` (the method that returns `List<String>` by name, ending with `return [];`). Insert the two new methods immediately after it and before `getReport`.

Find:
```dart
  Future<Response> getReport(String reportName, {Map<String, dynamic>? filters}) async {
```

Replace with:
```dart
  /// Parses a Frappe `/api/resource/Rack` response into rack name strings.
  ///
  /// Expects `data['data']` to be a `List` of maps each with a `'name'` key.
  /// Skips null entries, non-Map entries, and entries with a null or empty name.
  /// Returns an empty list on any shape mismatch or null input.
  static List<String> parseRacksByWarehouseResponse(dynamic data) {
    if (data == null) return [];
    final rawList = data['data'];
    if (rawList is! List) return [];
    final result = <String>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final name = item['name'];
      if (name is String && name.isNotEmpty) {
        result.add(name);
      }
    }
    return result;
  }

  /// Fetches all rack names in [warehouse] from the Rack DocType API.
  ///
  /// Calls `GET /api/resource/Rack?filters=[["warehouse","=",wh]]&fields=["name"]&limit_page_length=0`.
  /// Returns an empty list when [warehouse] is empty or on any API error.
  Future<List<String>> getRacksByWarehouse(String warehouse) async {
    if (warehouse.isEmpty) return [];
    try {
      if (!_dioInitialised) await _initDio();
      final response = await _dio.get('/api/resource/Rack', queryParameters: {
        'fields':            json.encode(['name']),
        'filters':           json.encode([['warehouse', '=', warehouse]]),
        'limit_page_length': 0,
        'order_by':          'name asc',
      });
      return parseRacksByWarehouseResponse(response.data);
    } catch (_) {
      return [];
    }
  }

  Future<Response> getReport(String reportName, {Map<String, dynamic>? filters}) async {
```

- [ ] **Step 4: Run the tests — expect all to pass**

```
flutter test test/unit/get_racks_by_warehouse_response_test.dart --reporter expanded
```

Expected: 8 tests pass.

- [ ] **Step 5: Run the full unit suite**

```
flutter test test/unit/ --reporter expanded
```

Expected: all existing tests still pass.

- [ ] **Step 6: Commit**

```
git add lib/app/data/providers/api_provider.dart test/unit/get_racks_by_warehouse_response_test.dart
git commit -m "feat(api): add getRacksByWarehouse and parseRacksByWarehouseResponse"
```

---

## Task 2: `RackPickerController` — `isTargetMode`, `loadForTarget`, `_compareEntriesByLocation` + unit tests

**Files:**
- Modify: `lib/app/shared/item_sheet/rack_picker_controller.dart`
- Create: `test/unit/rack_picker_controller_target_mode_test.dart`

`RackPickerController` finds `ApiProvider` via `Get.find<ApiProvider>()` at construction time. In tests we register a fake first, then put the controller, so `Get.find` resolves to our fake. The `tearDown` clears GetX between tests.

- [ ] **Step 1: Create the unit test file**

```dart
// test/unit/rack_picker_controller_target_mode_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';

class _FakeApiProvider extends ApiProvider {
  final List<String> racks;
  _FakeApiProvider(this.racks);

  @override
  Future<List<String>> getRacksByWarehouse(String warehouse) async => racks;
}

class _ThrowingApiProvider extends ApiProvider {
  @override
  Future<List<String>> getRacksByWarehouse(String warehouse) async =>
      throw Exception('network error');
}

void main() {
  tearDown(() => Get.deleteAll(force: true));

  group('RackPickerController.loadForTarget', () {
    test('sets isTargetMode to true', () async {
      Get.put<ApiProvider>(_FakeApiProvider(['KA-WH-DXB1-101A']));
      final ctrl = Get.put(RackPickerController());
      await ctrl.loadForTarget(warehouse: 'WH-DXB1 - KA', currentRack: '');
      expect(ctrl.isTargetMode.value, isTrue);
    });

    test('all entries have requestedQty == 0', () async {
      Get.put<ApiProvider>(_FakeApiProvider([
        'KA-WH-DXB1-101A',
        'KA-WH-DXB1-102A',
      ]));
      final ctrl = Get.put(RackPickerController());
      await ctrl.loadForTarget(warehouse: 'WH-DXB1 - KA', currentRack: '');
      expect(ctrl.entries.every((e) => e.requestedQty == 0.0), isTrue);
    });

    test('all entries have SufficiencyStatus.unknown', () async {
      Get.put<ApiProvider>(_FakeApiProvider(['KA-WH-DXB1-101A', 'KA-WH-DXB1-101B']));
      final ctrl = Get.put(RackPickerController());
      await ctrl.loadForTarget(warehouse: 'WH-DXB1 - KA', currentRack: '');
      expect(
        ctrl.entries.every((e) => e.status == SufficiencyStatus.unknown),
        isTrue,
      );
    });

    test('entries are sorted aisle-ascending then shelf-ascending', () async {
      Get.put<ApiProvider>(_FakeApiProvider([
        'KA-WH-DXB1-102B',
        'KA-WH-DXB1-101A',
        'KA-WH-DXB1-102A',
        'KA-WH-DXB1-101B',
      ]));
      final ctrl = Get.put(RackPickerController());
      await ctrl.loadForTarget(warehouse: 'WH-DXB1 - KA', currentRack: '');
      expect(
        ctrl.entries.map((e) => e.rackName).toList(),
        equals([
          'KA-WH-DXB1-101A',
          'KA-WH-DXB1-101B',
          'KA-WH-DXB1-102A',
          'KA-WH-DXB1-102B',
        ]),
      );
    });

    test('entries are empty and isLoading is false when warehouse is empty', () async {
      Get.put<ApiProvider>(_FakeApiProvider(['KA-WH-DXB1-101A']));
      final ctrl = Get.put(RackPickerController());
      await ctrl.loadForTarget(warehouse: '', currentRack: '');
      expect(ctrl.entries, isEmpty);
      expect(ctrl.isLoading.value, isFalse);
    });

    test('sets selectedRack to currentRack', () async {
      Get.put<ApiProvider>(_FakeApiProvider(['KA-WH-DXB1-101A']));
      final ctrl = Get.put(RackPickerController());
      await ctrl.loadForTarget(
        warehouse:   'WH-DXB1 - KA',
        currentRack: 'KA-WH-DXB1-101A',
      );
      expect(ctrl.selectedRack.value, equals('KA-WH-DXB1-101A'));
    });

    test('entries are empty and isLoading is false when API throws', () async {
      Get.put<ApiProvider>(_ThrowingApiProvider());
      final ctrl = Get.put(RackPickerController());
      await ctrl.loadForTarget(warehouse: 'WH-DXB1 - KA', currentRack: '');
      expect(ctrl.entries, isEmpty);
      expect(ctrl.isLoading.value, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run tests — expect failure** (fields and method not yet defined)

```
flutter test test/unit/rack_picker_controller_target_mode_test.dart --reporter expanded
```

Expected: compilation error — `isTargetMode` and `loadForTarget` are undefined.

- [ ] **Step 3: Add `isTargetMode` field to `RackPickerController`**

File: `lib/app/shared/item_sheet/rack_picker_controller.dart`

Find:
```dart
  /// Whether to restrict the visible list to racks whose warehouse matches
  /// the document-level [warehouse]. Defaults to `true` (On).
  /// Disabled automatically when [warehouse] is empty.
  var filterByWarehouse = true.obs;
```

Replace with:
```dart
  /// Whether to restrict the visible list to racks whose warehouse matches
  /// the document-level [warehouse]. Defaults to `true` (On).
  /// Disabled automatically when [warehouse] is empty.
  var filterByWarehouse = true.obs;

  /// `true` when the picker was opened for a target (destination) rack via
  /// [loadForTarget]. Drives UI changes in [RackPickerSheet]: hides the
  /// sufficiency bar, changes the empty-state message, and replaces the
  /// sufficiency badge with a simple rack count.
  var isTargetMode = false.obs;
```

- [ ] **Step 4: Add `_compareEntriesByLocation` static method**

Find the `// ── Selection` divider that immediately follows the closing `}` of `_compareEntries`:

```dart
  // ── Selection ─────────────────────────────────────────────────────────────────
```

Replace with:
```dart
  /// Sort order for target mode: aisle number ascending, then shelf letter
  /// ascending. Used by [loadForTarget] where sufficiency and qty are irrelevant.
  static int _compareEntriesByLocation(RackPickerEntry a, RackPickerEntry b) {
    final aAisle = a.location?.aisleNumber ?? 9999;
    final bAisle = b.location?.aisleNumber ?? 9999;
    final aisleComp = aAisle.compareTo(bAisle);
    if (aisleComp != 0) return aisleComp;

    final aShelf = a.location?.shelfLetter ?? 'Z';
    final bShelf = b.location?.shelfLetter ?? 'Z';
    return aShelf.compareTo(bShelf);
  }

  // ── Selection ─────────────────────────────────────────────────────────────────
```

- [ ] **Step 5: Add `loadForTarget` method**

Find the `// ── Sorting` divider that immediately follows the closing `}` of `load()`:

```dart
  // ── Sorting ─────────────────────────────────────────────────────────────────
```

Replace with:
```dart
  /// Fetches all rack names in [warehouse] from the Rack DocType API and
  /// populates [entries] with zero-qty entries (all [SufficiencyStatus.unknown],
  /// all tappable). Sets [isTargetMode] to `true`.
  ///
  /// If [warehouse] is empty, [entries] is cleared immediately with no API call.
  /// On any API error, [entries] is cleared and [isLoading] is reset.
  Future<void> loadForTarget({
    required String warehouse,
    required String currentRack,
  }) async {
    isTargetMode.value      = true;
    _warehouse              = warehouse;
    _itemCode               = '';
    _batchNo                = '';
    _requestedQty           = 0.0;
    selectedRack.value      = currentRack;
    filterByWarehouse.value = true;
    usedFallback.value      = false;

    if (warehouse.isEmpty) {
      entries.clear();
      return;
    }

    isLoading.value = true;
    try {
      final names = await _api.getRacksByWarehouse(warehouse);
      final built = names.map((name) {
        return RackPickerEntry(
          rackName:     name,
          location:     RackLocation.tryParse(name),
          availableQty: 0.0,
          requestedQty: 0.0,
        );
      }).toList();
      built.sort(_compareEntriesByLocation);
      entries.assignAll(built);
    } catch (_) {
      entries.clear();
    } finally {
      isLoading.value = false;
    }
  }

  // ── Sorting ─────────────────────────────────────────────────────────────────
```

- [ ] **Step 6: Run the controller tests — expect all to pass**

```
flutter test test/unit/rack_picker_controller_target_mode_test.dart --reporter expanded
```

Expected: 7 tests pass.

- [ ] **Step 7: Run the full unit suite**

```
flutter test test/unit/ --reporter expanded
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```
git add lib/app/shared/item_sheet/rack_picker_controller.dart test/unit/rack_picker_controller_target_mode_test.dart
git commit -m "feat(rack-picker): add isTargetMode, loadForTarget, _compareEntriesByLocation"
```

---

## Task 3: `RackPickerSheet` — adapt for target mode

**Files:**
- Modify: `lib/app/shared/item_sheet/rack_picker_sheet.dart`

Three changes:
1. `_RackPickerTile` — add `isTargetMode` parameter; use it to keep all tiles tappable and to hide `_SufficiencyBar`.
2. Empty-state text — `'No racks found'` when `isTargetMode`, else `'No racks found with stock'`.
3. Summary badge — `'N racks'` when `isTargetMode`, else `'X/N sufficient'`.

No new tests — UI-only code; manual smoke test is Task 5.

- [ ] **Step 1: Replace the entire `_RackPickerTile` class**

Find the entire `_RackPickerTile` class (from `class _RackPickerTile extends StatelessWidget {` through its closing `}`). Replace it with:

```dart
class _RackPickerTile extends StatelessWidget {
  final RackPickerEntry entry;
  final bool isSelected;
  final bool isTargetMode;
  final VoidCallback onTap;

  const _RackPickerTile({
    required this.entry,
    required this.isSelected,
    required this.isTargetMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final cs          = theme.colorScheme;
    final statusColor = _statusColor(entry.status);
    final isDisabled  = isTargetMode ? false : entry.status == SufficiencyStatus.empty;

    final bgColor = isSelected
        ? cs.primary.withOpacity(0.08)
        : isDisabled
            ? cs.surfaceContainerHighest.withOpacity(0.5)
            : cs.surface;

    final borderColor = isSelected
        ? cs.primary.withOpacity(0.5)
        : cs.outlineVariant.withOpacity(0.5);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isDisabled ? null : onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _SufficiencyDot(status: entry.status),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.rackName,
                        style: TextStyle(
                          fontFamily: 'ShureTechMono',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDisabled
                              ? cs.onSurface.withOpacity(0.4)
                              : cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (entry.displayLabel != entry.rackName) ...[
                        Text(
                          entry.displayLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDisabled
                                ? cs.onSurfaceVariant.withOpacity(0.4)
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (entry.warehouseName.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: statusColor.withOpacity(0.2)),
                          ),
                          child: Text(
                            entry.warehouseName,
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'ShureTechMono',
                              color: isDisabled
                                  ? statusColor.withOpacity(0.4)
                                  : statusColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (!isTargetMode)
                  _SufficiencyBar(
                    availableQty: entry.availableQty,
                    requestedQty: entry.requestedQty,
                    status: entry.status,
                  ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle, color: cs.primary, size: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Fix the globally-empty state text**

This change is inside the `Obx` block in `RackPickerSheet.build()`, where `ctrl` is already in scope.

Find:
```dart
                      Text(
                        'No racks found with stock',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
```

Replace with:
```dart
                      Text(
                        ctrl.isTargetMode.value
                            ? 'No racks found'
                            : 'No racks found with stock',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
```

- [ ] **Step 3: Add `isTargetMode` local variable to the resolved-display-values block**

Find:
```dart
              // ── Resolved display values ───────────────────────────────────
              final visible      = ctrl.visibleEntries;
              final selectedRack = ctrl.selectedRack.value;
              final filterOn     = ctrl.filterByWarehouse.value;
              final hasWarehouse = ctrl.warehouse.isNotEmpty;
              final suf          = ctrl.visibleSufficientCount;
              final tot          = visible.length;
```

Replace with:
```dart
              // ── Resolved display values ───────────────────────────────────
              final visible      = ctrl.visibleEntries;
              final selectedRack = ctrl.selectedRack.value;
              final filterOn     = ctrl.filterByWarehouse.value;
              final hasWarehouse = ctrl.warehouse.isNotEmpty;
              final suf          = ctrl.visibleSufficientCount;
              final tot          = visible.length;
              final isTargetMode = ctrl.isTargetMode.value;
```

- [ ] **Step 4: Replace the sufficiency badge with a mode-aware badge**

Find:
```dart
                          // Sufficient badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: suf > 0
                                  ? Colors.green.shade600
                                      .withOpacity(0.1)
                                  : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$suf / $tot sufficient',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: suf > 0
                                    ? Colors.green.shade700
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
```

Replace with:
```dart
                          // Sufficient badge (source) / rack count (target)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isTargetMode
                                  ? cs.surfaceContainerHighest
                                  : suf > 0
                                      ? Colors.green.shade600.withOpacity(0.1)
                                      : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isTargetMode
                                  ? '$tot racks'
                                  : '$suf / $tot sufficient',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: !isTargetMode && suf > 0
                                    ? Colors.green.shade700
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
```

- [ ] **Step 5: Pass `isTargetMode` when constructing `_RackPickerTile`**

Find:
```dart
                          return _RackPickerTile(
                            entry:      entry,
                            isSelected: isSelected,
                            onTap: () {
                              ctrl.selectRack(entry.rackName);
                              onSelected(entry.rackName);
                              Navigator.of(context).pop();
                            },
                          );
```

Replace with:
```dart
                          return _RackPickerTile(
                            entry:        entry,
                            isSelected:   isSelected,
                            isTargetMode: isTargetMode,
                            onTap: () {
                              ctrl.selectRack(entry.rackName);
                              onSelected(entry.rackName);
                              Navigator.of(context).pop();
                            },
                          );
```

- [ ] **Step 6: Run the full unit suite**

```
flutter test test/unit/ --reporter expanded
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```
git add lib/app/shared/item_sheet/rack_picker_sheet.dart
git commit -m "feat(rack-picker-sheet): suppress stock UI in target mode"
```

---

## Task 4: `TargetRackFieldAdapter.browseRacks()` — switch to `loadForTarget`

**Files:**
- Modify: `lib/app/shared/item_sheet/dual_rack_adapters.dart` (the `browseRacks` method of `TargetRackFieldAdapter`, ~lines 300–341)

- [ ] **Step 1: Replace `browseRacks()` in `TargetRackFieldAdapter`**

Find the `browseRacks()` method in `TargetRackFieldAdapter` (starting with the doc comment `/// Opens the rack picker scoped to [_d.targetRackWarehouse].`):

```dart
  /// Opens the rack picker scoped to [_d.targetRackWarehouse].
  /// See [SourceRackFieldAdapter.browseRacks] for the full rationale.
  @override
  Future<RackPickerResult?> browseRacks() async {
    if (!canBrowseRacks) return null;

    final warehouse = _d.targetRackWarehouse?.value ?? '';
    final tag       = 'tgt_rack_${DateTime.now().microsecondsSinceEpoch}';
    final ctrl      = Get.put(RackPickerController(), tag: tag);

    unawaited(ctrl.load(
      itemCode:     _d.itemCode.value,
      batchNo:      _d.batchController.text.trim(),
      warehouse:    warehouse,
      requestedQty: double.tryParse(_d.qtyController.text) ?? 0.0,
      currentRack:  _d.targetRackController.text.trim(),
      fallbackMap:  const {},
    ));

    RackPickerResult? result;

    await Get.bottomSheet(
      RackPickerSheet(
        pickerTag:  tag,
        onSelected: (rack) {
          result = RackPickerResult(rackId: rack, availableQty: 0.0);
        },
      ),
      isScrollControlled: true,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Get.isRegistered<RackPickerController>(tag: tag)) {
        Get.delete<RackPickerController>(tag: tag);
      }
    });

    return result;
  }
```

Replace with:
```dart
  /// Opens the rack picker for a target (destination) rack.
  ///
  /// Uses [RackPickerController.loadForTarget] to fetch all Rack DocType
  /// records in [_d.targetRackWarehouse] from the Frappe API, rather than
  /// querying the Stock Balance report. Sets [isTargetMode] on the controller
  /// so [RackPickerSheet] suppresses the sufficiency bar and replaces the
  /// sufficiency badge with a simple rack count.
  @override
  Future<RackPickerResult?> browseRacks() async {
    if (!canBrowseRacks) return null;

    final warehouse = _d.targetRackWarehouse?.value ?? '';
    final tag       = 'tgt_rack_${DateTime.now().microsecondsSinceEpoch}';
    final ctrl      = Get.put(RackPickerController(), tag: tag);

    unawaited(ctrl.loadForTarget(
      warehouse:   warehouse,
      currentRack: _d.targetRackController.text.trim(),
    ));

    RackPickerResult? result;

    await Get.bottomSheet(
      RackPickerSheet(
        pickerTag:  tag,
        onSelected: (rack) {
          result = RackPickerResult(rackId: rack, availableQty: 0.0);
        },
      ),
      isScrollControlled: true,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Get.isRegistered<RackPickerController>(tag: tag)) {
        Get.delete<RackPickerController>(tag: tag);
      }
    });

    return result;
  }
```

- [ ] **Step 2: Run the full unit suite**

```
flutter test test/unit/ --reporter expanded
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```
git add lib/app/shared/item_sheet/dual_rack_adapters.dart
git commit -m "feat(se-item-form): target rack picker uses DocType API via loadForTarget"
```

---

## Task 5: Smoke test on device

Manual verification on a physical device with DataWedge and a live ERPNext instance.

- [ ] **Scenario A — Target rack picker lists all DocType racks (not stock-based)**
  1. Open a Material Transfer Stock Entry form.
  2. Scan an item → item sheet opens.
  3. Tap the browse icon (list icon) on the **target** rack field.
  4. Verify the sheet shows all racks for the target warehouse — including racks that don't hold this item.
  5. Verify all tiles are **tappable** (no greyed-out disabled tiles).
  6. Verify the `_SufficiencyBar` (the qty number + progress bar on the right) is absent from every tile.
  7. Verify the summary row shows `N racks` (e.g., `12 racks`) instead of `X/N sufficient`.

- [ ] **Scenario B — Empty warehouse → empty state with correct message**
  1. Open a form where no target warehouse is configured for the item.
  2. Tap the browse icon on the target rack field (if `canBrowseRacks` is false, the button will be absent — verify absence rather than force-opening).
  3. If the picker opens with an empty list: verify it shows `No racks found` (not `No racks found with stock`).

- [ ] **Scenario C — Source rack picker is unchanged**
  1. Open any Stock Entry form, scan an item, tap the browse icon on the **source** rack field.
  2. Verify the source picker still shows `_SufficiencyBar` on tiles, the `X/N sufficient` badge, and greyed-out empty-stock tiles (source mode unchanged).

- [ ] **Scenario D — Picking a target rack still triggers warehouse derivation**
  1. Open a Material Transfer form, scan an item.
  2. Tap browse on the target rack, pick any rack from the list.
  3. Verify the target rack field is populated.
  4. Verify the `DerivedWarehouseLabel` below the target rack shows `(auto from rack)` — confirming `validateDualRack` still fires post-pick and writes `itemTargetWarehouse`.
