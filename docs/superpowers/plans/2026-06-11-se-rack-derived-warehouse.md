# Stock Entry Rack-Derived Item Warehouses — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stock Entry item rows get their `s_warehouse`/`t_warehouse` from the scanned rack's authoritative warehouse (Rack DocType `warehouse` field), falling back to the document default — matching ERPNext v15 row-precedence semantics.

**Architecture:** A new `ApiProvider.getRackWarehouse()` fetches the Rack doc and classifies the outcome (found / notFound / error). The SE item-sheet controller gains `resolveRackWarehouse()` which sets `itemSourceWarehouse`/`itemTargetWarehouse` optimistically from the rack-name parse, then overwrites with the API truth. `validateDualRack()` awaits that resolution *before* fetching balances, and `resolvedWarehouse` becomes the cascade `itemSourceWarehouse ?? parent.fromWarehouse` so all balance lookups scope to the rack's own warehouse. An `ever()` worker re-fetches batch balance when the warehouse resolves after the batch (batch-first scan order).

**Tech Stack:** Flutter, GetX (controllers/observables/workers), Dio via `ApiProvider`, `flutter_test` (no mocking library — tests use pure parsers and an injectable fetcher function).

**Spec:** `docs/superpowers/specs/2026-06-11-se-rack-derived-warehouse-design.md`

**Key context for a zero-context engineer:**
- `StockEntryItemFormController` (`lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart`) is the bottom-sheet controller for one SE item. Its `_parent` (a `StockEntryFormController`) is `late` and only set via `initialise(parent: …)` — **unit tests must not touch any code path that reads `_parent`** (e.g. `validateSheet()`, `showSourceRack`, `submit()`), or they crash with `LateInitializationError`. That is why tests target the new `resolveRackWarehouse()` directly instead of `validateDualRack()`.
- `submit()` already implements the final cascade (`itemSourceWarehouse ?? _parent.fromWarehouse`) — it is NOT modified by this plan. We only fix what feeds `itemSourceWarehouse`/`itemTargetWarehouse`.
- Existing test conventions: see `test/unit/get_racks_by_warehouse_response_test.dart` (static parser tests) and `test/unit/dn_item_form_controller_warehouse_test.dart` (controller test with the `path_provider` channel stub). Follow them.
- All `flutter` commands run from the repo root `C:\Users\asifm\StudioProjects\ddmco_multimax`.

---

### Task 1: `RackWarehouseLookup` model + `ApiProvider.getRackWarehouse`

**Files:**
- Create: `lib/app/data/models/rack_warehouse_lookup.dart`
- Modify: `lib/app/data/providers/api_provider.dart` (add two members near `getRacksByWarehouse`, ~line 400)
- Test: `test/unit/rack_warehouse_lookup_response_test.dart`

- [ ] **Step 1: Write the failing parser test**

Create `test/unit/rack_warehouse_lookup_response_test.dart`:

```dart
// test/unit/rack_warehouse_lookup_response_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.parseRackWarehouseResponse', () {
    test('T-1: extracts warehouse from a well-formed Rack doc response', () {
      final data = {
        'data': {'name': 'KA-WH-DXB1-101A', 'warehouse': 'WH-DXB1 - KA'},
      };
      expect(ApiProvider.parseRackWarehouseResponse(data),
          equals('WH-DXB1 - KA'));
    });

    test('T-2: returns null when warehouse field is missing', () {
      final data = {
        'data': {'name': 'KA-WH-DXB1-101A'},
      };
      expect(ApiProvider.parseRackWarehouseResponse(data), isNull);
    });

    test('T-3: returns null when warehouse field is empty', () {
      final data = {
        'data': {'name': 'KA-WH-DXB1-101A', 'warehouse': ''},
      };
      expect(ApiProvider.parseRackWarehouseResponse(data), isNull);
    });

    test('T-4: returns null on null input', () {
      expect(ApiProvider.parseRackWarehouseResponse(null), isNull);
    });

    test('T-5: returns null when data key is not a Map', () {
      expect(ApiProvider.parseRackWarehouseResponse({'data': []}), isNull);
      expect(ApiProvider.parseRackWarehouseResponse({'data': 'x'}), isNull);
    });

    test('T-6: returns null when warehouse is not a String', () {
      final data = {
        'data': {'warehouse': 42},
      };
      expect(ApiProvider.parseRackWarehouseResponse(data), isNull);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/unit/rack_warehouse_lookup_response_test.dart`
Expected: FAIL to compile — `parseRackWarehouseResponse` is not defined.

- [ ] **Step 3: Create the lookup model**

Create `lib/app/data/models/rack_warehouse_lookup.dart`:

```dart
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

  const RackWarehouseLookup.found(this.warehouse)
      : status = RackLookupStatus.found;

  const RackWarehouseLookup.notFound()
      : status = RackLookupStatus.notFound,
        warehouse = null;

  const RackWarehouseLookup.error()
      : status = RackLookupStatus.error,
        warehouse = null;
}
```

- [ ] **Step 4: Add parser + fetch method to ApiProvider**

In `lib/app/data/providers/api_provider.dart`, add the import at the top with the other model imports:

```dart
import 'package:multimax/app/data/models/rack_warehouse_lookup.dart';
```

Then insert directly after the `getRacksByWarehouse` method (after its closing `}` around line 418):

```dart
  /// Extracts the `warehouse` link from a `GET /api/resource/Rack/{name}`
  /// response body. Returns null on any shape mismatch or empty value.
  static String? parseRackWarehouseResponse(dynamic data) {
    if (data is! Map) return null;
    final doc = data['data'];
    if (doc is! Map) return null;
    final wh = doc['warehouse'];
    return (wh is String && wh.isNotEmpty) ? wh : null;
  }

  /// Resolves the authoritative warehouse of [rack] from the Rack DocType.
  ///
  /// Distinguishes "rack does not exist" (404 → notFound) from transient
  /// failures (error) so callers can reject invalid racks while degrading
  /// gracefully offline.
  Future<RackWarehouseLookup> getRackWarehouse(String rack) async {
    try {
      final response = await getDocument('Rack', rack);
      if (response.statusCode == 200 && response.data != null) {
        return RackWarehouseLookup.found(
            parseRackWarehouseResponse(response.data));
      }
      return const RackWarehouseLookup.error();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const RackWarehouseLookup.notFound();
      }
      return const RackWarehouseLookup.error();
    } catch (_) {
      return const RackWarehouseLookup.error();
    }
  }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/unit/rack_warehouse_lookup_response_test.dart`
Expected: 6 tests PASS.

- [ ] **Step 6: Analyze**

Run: `flutter analyze`
Expected: No new issues (pre-existing infos/warnings unrelated to these files are acceptable).

- [ ] **Step 7: Commit**

```bash
git add lib/app/data/models/rack_warehouse_lookup.dart lib/app/data/providers/api_provider.dart test/unit/rack_warehouse_lookup_response_test.dart
git commit -m "feat(api): add Rack warehouse lookup with 404/error classification"
```

---

### Task 2: `resolveRackWarehouse` on the SE item-sheet controller

**Files:**
- Modify: `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart`
- Test: `test/unit/se_item_rack_warehouse_resolution_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/unit/se_item_rack_warehouse_resolution_test.dart`:

```dart
// test/unit/se_item_rack_warehouse_resolution_test.dart
//
// Tests resolveRackWarehouse() in isolation. It must NOT touch the late
// _parent field, so the controller can be constructed bare via Get.put.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/rack_warehouse_lookup.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_item_form_controller.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Stub path_provider so ApiProvider._initDio() does not throw in
    // the headless test environment (no platform plugins available).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => '/tmp/test_cookies',
    );
  });

  tearDown(() => Get.deleteAll(force: true));

  StockEntryItemFormController makeController(
      Future<RackWarehouseLookup> Function(String) fetcher) {
    final ctrl = Get.put(StockEntryItemFormController());
    ctrl.rackWarehouseFetcher = fetcher;
    return ctrl;
  }

  group('StockEntryItemFormController.resolveRackWarehouse — source side', () {
    test('T-1: Rack API warehouse overwrites the name-parse value', () async {
      final ctrl = makeController(
          (_) async => const RackWarehouseLookup.found('WH-DXB9 - KA'));
      final ok = await ctrl.resolveRackWarehouse('KA-WH-DXB1-101A', true);
      expect(ok, isTrue);
      // Name-parse would yield 'WH-DXB1 - KA'; the API value must win.
      expect(ctrl.itemSourceWarehouse.value, equals('WH-DXB9 - KA'));
    });

    test('T-2: network error keeps the optimistic name-parse value', () async {
      final ctrl =
          makeController((_) async => const RackWarehouseLookup.error());
      final ok = await ctrl.resolveRackWarehouse('KA-WH-DXB1-101A', true);
      expect(ok, isTrue);
      expect(ctrl.itemSourceWarehouse.value, equals('WH-DXB1 - KA'));
    });

    test('T-3: 404 clears the warehouse and reports rack invalid', () async {
      final ctrl =
          makeController((_) async => const RackWarehouseLookup.notFound());
      final ok = await ctrl.resolveRackWarehouse('KA-WH-DXB1-101A', true);
      expect(ok, isFalse);
      expect(ctrl.itemSourceWarehouse.value, isNull);
    });

    test('T-4: non-parseable rack name still gets the API warehouse',
        () async {
      final ctrl = makeController(
          (_) async => const RackWarehouseLookup.found('WH-DXB2 - KA'));
      final ok = await ctrl.resolveRackWarehouse('ODDRACK99', true);
      expect(ok, isTrue);
      expect(ctrl.itemSourceWarehouse.value, equals('WH-DXB2 - KA'));
    });

    test(
        'T-5: non-parseable rack name + network error leaves warehouse null '
        '(document default applies at submit)', () async {
      final ctrl =
          makeController((_) async => const RackWarehouseLookup.error());
      final ok = await ctrl.resolveRackWarehouse('ODDRACK99', true);
      expect(ok, isTrue);
      expect(ctrl.itemSourceWarehouse.value, isNull);
    });

    test('T-6: found-with-null-warehouse keeps the name-parse value',
        () async {
      final ctrl =
          makeController((_) async => const RackWarehouseLookup.found(null));
      final ok = await ctrl.resolveRackWarehouse('KA-WH-DXB1-101A', true);
      expect(ok, isTrue);
      expect(ctrl.itemSourceWarehouse.value, equals('WH-DXB1 - KA'));
    });
  });

  group('StockEntryItemFormController.resolveRackWarehouse — target side', () {
    test('T-7: API warehouse lands on itemTargetWarehouse', () async {
      final ctrl = makeController(
          (_) async => const RackWarehouseLookup.found('WH-DXB3 - KA'));
      final ok = await ctrl.resolveRackWarehouse('KA-WH-DXB1-202B', false);
      expect(ok, isTrue);
      expect(ctrl.itemTargetWarehouse.value, equals('WH-DXB3 - KA'));
      expect(ctrl.itemSourceWarehouse.value, isNull,
          reason: 'target resolution must not touch the source side');
    });

    test('T-8: 404 clears itemTargetWarehouse and reports invalid', () async {
      final ctrl =
          makeController((_) async => const RackWarehouseLookup.notFound());
      final ok = await ctrl.resolveRackWarehouse('KA-WH-DXB1-202B', false);
      expect(ok, isFalse);
      expect(ctrl.itemTargetWarehouse.value, isNull);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/se_item_rack_warehouse_resolution_test.dart`
Expected: FAIL to compile — `rackWarehouseFetcher` and `resolveRackWarehouse` are not defined.

- [ ] **Step 3: Implement `resolveRackWarehouse` and the injectable fetcher**

In `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart`:

Add the import at the top with the other `multimax` imports:

```dart
import 'package:multimax/app/data/models/rack_warehouse_lookup.dart';
```

Insert the following directly after the `resetTargetRackValidation()` method (after its closing `}`, currently around line 489) and before `validateDualRack`:

```dart
  /// Fetches the authoritative warehouse for a rack from the Rack DocType.
  /// Injectable so unit tests can stub server outcomes without a Dio mock.
  Future<RackWarehouseLookup> Function(String rack) rackWarehouseFetcher =
      (rack) => ApiProvider().getRackWarehouse(rack);

  /// Resolves the warehouse for [rack] onto the item-level warehouse of the
  /// given side (Priority 1 of the cascade; `submit()` falls back to the
  /// document default when this stays null).
  ///
  /// Sets the rack-name parse optimistically for a zero-latency label, then
  /// overwrites it with the Rack DocType's `warehouse` field. On 404 the
  /// warehouse is cleared and `false` is returned — the rack is invalid.
  /// On a transient failure the parse value stands (offline degradation).
  Future<bool> resolveRackWarehouse(String rack, bool isSource) async {
    final target = isSource ? itemSourceWarehouse : itemTargetWarehouse;
    target.value = RackLocation.tryParse(rack)?.warehouseName;

    final lookup = await rackWarehouseFetcher(rack);
    if (isClosed) return false;

    switch (lookup.status) {
      case RackLookupStatus.found:
        if (lookup.warehouse != null) target.value = lookup.warehouse;
        return true;
      case RackLookupStatus.notFound:
        target.value = null;
        return false;
      case RackLookupStatus.error:
        return true;
    }
  }
```

Note: `ApiProvider` and `RackLocation` are already imported by this file.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/se_item_rack_warehouse_resolution_test.dart`
Expected: 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart test/unit/se_item_rack_warehouse_resolution_test.dart
git commit -m "feat(stock-entry): resolve item warehouse from Rack DocType on rack scan"
```

---

### Task 3: Wire resolution into `validateDualRack` + balance-scoping cascade

**Files:**
- Modify: `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart` (two locations: `resolvedWarehouse` getter ~line 216, `validateDualRack` ~line 492)

No new unit test: `validateDualRack` and `resolvedWarehouse`'s fallback arm read the `late _parent` field, which cannot be constructed in a unit test (no mocking library; the parent controller pulls live providers in `onInit`). Coverage comes from Task 2's tests (the derivation), the existing suite (regressions), `flutter analyze`, and the manual smoke test in Task 5.

- [ ] **Step 1: Restore the `resolvedWarehouse` cascade**

Replace (currently ~line 215):

```dart
  @override
  String? get resolvedWarehouse => _parent.fromWarehouse.value;
```

with:

```dart
  /// Warehouse scope for balance lookups (rack balance, batch balance,
  /// pickers, rack-stock preload).
  ///
  /// Priority 1: warehouse resolved from the scanned source rack.
  /// Priority 2: the document-level default source warehouse.
  /// Mirrors ERPNext v15 row-precedence (row s_warehouse over parent
  /// from_warehouse) and the submit() cascade below.
  @override
  String? get resolvedWarehouse =>
      itemSourceWarehouse.value ?? _parent.fromWarehouse.value;
```

- [ ] **Step 2: Reorder `validateDualRack` — resolve warehouse first, then balance**

Replace the entire `try` block of `validateDualRack(String rack, bool isSource)` (currently lines 504–531, from `try {` through the closing brace before `} catch (e) {`) with:

```dart
    try {
      // Resolve the rack's warehouse FIRST so the balance lookup below is
      // scoped to the rack's own warehouse rather than the document default
      // (a rack in a non-default warehouse otherwise reads balance 0 and is
      // falsely rejected).
      final rackExists = await resolveRackWarehouse(rack, isSource);
      if (!rackExists) {
        if (isSource) {
          isSourceRackValid.value = false;
        } else {
          isTargetRackValid.value = false;
        }
        rackError.value = 'Rack "$rack" not found.';
        showError('Rack "$rack" not found');
        return;
      }
      if (isSource) {
        isLoadingRackBalance.value = true;
        if (_rackStockMap.containsKey(rack)) {
          rackBalance.value = _rackStockMap[rack]!;
        } else {
          await fetchRackBalance(rack);
        }
        isLoadingRackBalance.value = false;
        if (rackBalance.value <= 0) {
          isSourceRackValid.value   = false;
          itemSourceWarehouse.value = null;
          rackError.value =
              'Rack balance is ${rackBalance.value.toStringAsFixed(0)} — cannot issue from this rack.';
        } else {
          isSourceRackValid.value = true;
          rackError.value = '';
        }
      } else {
        isTargetRackValid.value   = true;
        // Only clear rackError if source rack has no active error.
        // Preserving source-side negative-balance error message.
        if (isSourceRackValid.value) {
          rackError.value = '';
        }
      }
    } catch (e) {
```

Behavioural deltas vs. the old block, for review clarity:
1. `resolveRackWarehouse` is awaited before any balance fetch (so `fetchRackBalance` → `resolvedWarehouse` sees the rack's warehouse).
2. The two `itemSourceWarehouse.value = RackLocation.tryParse(...)` / `itemTargetWarehouse.value = RackLocation.tryParse(...)` assignments are gone — `resolveRackWarehouse` owns that write now.
3. A 404 marks the rack invalid with an error + snackbar; previously target racks were accepted unconditionally and source racks fell through to a zero-balance message.
4. The `return` inside `try` still runs the `finally` block (validation flags + `validateSheet()`), preserving the save-gate re-evaluation.

- [ ] **Step 3: Analyze and run the affected suites**

Run: `flutter analyze`
Expected: no new issues.

Run: `flutter test test/unit/se_item_rack_warehouse_resolution_test.dart test/unit/rack_location_warehouse_derivation_test.dart test/unit/rack_picker_controller_target_mode_test.dart`
Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart
git commit -m "fix(stock-entry): scope rack/batch balances to rack-derived warehouse"
```

---

### Task 4: Batch re-scope worker (batch-first scan order)

**Files:**
- Modify: `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart` (add `onInit` override; extend the existing `onClose` override ~line 1181)

When the user scans the batch *before* the source rack, the batch balance was fetched against the default warehouse. When the rack scan then resolves `itemSourceWarehouse`, the balance must be re-fetched in the new scope. Project convention (CLAUDE.md): workers are stored in a field and cancelled in `onClose()`.

- [ ] **Step 1: Add the worker**

The controller has no `onInit` override today. Add one near the other lifecycle overrides (place it directly before the existing `onClose` override, ~line 1181), plus the worker field:

```dart
  /// Re-fetches the batch balance when a rack scan resolves the item-level
  /// source warehouse AFTER the batch was already validated (batch-first
  /// scan order). Without this, the balance stays scoped to the document
  /// default warehouse.
  Worker? _batchRescopeWorker;

  @override
  void onInit() {
    super.onInit();
    _batchRescopeWorker = ever<String?>(itemSourceWarehouse, (_) {
      if (isClosed) return;
      if (isBatchValid.value && batchController.text.trim().isNotEmpty) {
        fetchBatchBalance();
      }
    });
  }
```

- [ ] **Step 2: Cancel the worker in `onClose`**

The existing override (~line 1181) is:

```dart
  @override
  void onClose() {
    disposeBarcodeListener();   // BarcodeAwareMixin: safety-net disposal
    disposeAutoFillListener();
    super.onClose();
  }
```

Change it to:

```dart
  @override
  void onClose() {
    _batchRescopeWorker?.dispose();
    disposeBarcodeListener();   // BarcodeAwareMixin: safety-net disposal
    disposeAutoFillListener();
    super.onClose();
  }
```

- [ ] **Step 3: Verify the existing tests still pass (worker must be inert without a batch)**

The Task 2 tests flip `itemSourceWarehouse` via `resolveRackWarehouse` with `isBatchValid == false`, so the worker body must no-op (no network call, no `_parent` access).

Run: `flutter test test/unit/se_item_rack_warehouse_resolution_test.dart`
Expected: 8 tests PASS.

- [ ] **Step 4: Analyze and commit**

Run: `flutter analyze`
Expected: no new issues.

```bash
git add lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart
git commit -m "feat(stock-entry): re-scope batch balance when rack resolves warehouse"
```

---

### Task 5: Full verification + docs

**Files:**
- Modify: `docs/stock_entry_flow.md` (sections "Rack Validation & Balance" and "Warehouse Resolution Cascade")

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: all tests PASS (no regressions outside the new files).

- [ ] **Step 2: Update `docs/stock_entry_flow.md`**

In the **Rack Validation & Balance** section, replace the `validateRack` description's inline-parse lines:

```
├── Attempt inline warehouse parse:
│   rack format "WH-A1" → parts[0]=branch, parts[1]=aisle, parts[2]=slot
│   derived warehouse = '{parts[1]}-{parts[2]} - {parts[0]}'
│   bsItemSourceWarehouse (or Target) = derived warehouse  ← triggers reactives
```

with:

```
├── resolveRackWarehouse(rack, isSource):
│   ├── optimistic: itemSource/TargetWarehouse = RackLocation.tryParse(rack)?.warehouseName
│   ├── GET /api/resource/Rack/{rack} → overwrite with doc's `warehouse` field
│   ├── 404 → warehouse cleared, rack invalid, snackbar
│   └── network error → optimistic parse value stands
```

In the **Warehouse Resolution Cascade** section, replace the cascade block:

```
effective_warehouse =
  bsItemSourceWarehouse    (set from rack scan → item-level)
  ?? derivedSourceWarehouse  (inline parse from rack string)
  ?? selectedFromWarehouse   (document-level header field)
```

with:

```
effective_warehouse =
  itemSourceWarehouse       (Rack DocType `warehouse` field; name-parse while in flight)
  ?? fromWarehouse          (document-level default source warehouse)

Matches ERPNext v15: row-level s_warehouse/t_warehouse take precedence;
parent from_warehouse/to_warehouse are defaults only.
```

- [ ] **Step 3: Manual smoke test (device)**

Run the app on the configured Android device (`flutter run -d <device_id>`, see `.vscode/launch.json`) against the live ERP instance:

1. New Stock Entry → Material Transfer → set Default Source + Target Warehouse in Details.
2. Items tab → scan an item barcode → scan a batch → scan a **source rack in a different warehouse** than the default → the sheet label must show that rack's warehouse "(auto from rack)" and the rack must NOT be rejected for zero balance if it has stock there.
3. Scan a target rack → label shows the target rack's warehouse.
4. Save → open the saved SE in ERPNext desk → item row `s_warehouse`/`t_warehouse` must match the racks' warehouses, not the defaults.
5. Repeat with no racks scanned (typed qty only, where applicable) → row warehouses must fall back to the document defaults.
6. Scan a nonsense rack code (e.g. `ZZ-XX-FAKE-000Z`) → "Rack not found" error, save blocked.

- [ ] **Step 4: Commit docs**

```bash
git add docs/stock_entry_flow.md
git commit -m "docs(stock-entry): document Rack DocType warehouse derivation cascade"
```
