# Item Auto re-order Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a viewable and editable "Re-order" tab to the Multimax Item form that reads and writes `Item.reorder_levels`, mirroring the default behaviour of `frappe/erpnext` branch `version-15`.

**Architecture:** A 5th tab on the existing Item form. Reorder rows arrive free with the `Item` doc (the resource API already returns child tables — `Item.fromJson` currently discards them), are edited through a bottom-sheet row editor, and are saved back with a whole-document `PUT` carrying the optimistic-lock `modified` token. Pure v15 validation rules live in a standalone, GetX-free file so they unit-test without a network or a controller. The Item form gains its first business-field write path.

**Tech Stack:** Flutter, GetX (controllers/bindings/`.obs`), Dio via `ApiProvider`, Frappe/ERPNext v15 REST resource API. Tests: `flutter_test` only — **no mockito/mocktail in this repo**; fakes are written by subclassing the real provider.

**Spec:** `docs/superpowers/specs/2026-07-17-item-auto-reorder-design.md` (commit `4603aa88`)

## Global Constraints

Every task's requirements implicitly include this section.

- **GetX only.** Controllers extend `GetxController`; observables use `.obs`; screens extend `GetView<T>` and stay stateless. Any `ever(...)` Worker must be stored in a field and cancelled in `onClose()`.
- **REST calls belong in `lib/app/data/providers/*_provider.dart`**, never inline in a controller.
- **Never hardcode surface or ink colours.** Surfaces: `context.scheme.fg` / `colorScheme.surface` / `scheme.subtle` — never `Colors.white` or `grey.shade50/100`. Body text `scheme.text`/`onSurface`; secondary `scheme.textMuted`; decorative icons only `scheme.textSubtle`. Never `Colors.black87`, `Colors.grey`, or `grey.shadeX` as text.
- **Status colours as text** use the `AppColors` ramp: x700 in light, x300 in dark. Status tints: fill `x500.withValues(alpha: 0.13)`, border ≈ alpha 0.35.
- **Async feedback:** any control triggering async work uses `AsyncFilledButton`/`AsyncIconButton` driven by a controller `RxBool`, set and cleared in a `finally`, with a re-entrancy guard `if (busy.value) return;` before launching work.
- **Do not re-implement shared widgets privately.** Use `DocSectionCard`, `DocDetailRow`, `DocPickerField`, `FormEmptyState`, `InlineBanner`, `WarehousePickerSheet`, `DocTypeGuard`, `AsyncFilledButton`.
- **Do not hand-roll number formatting.** `FormattingHelper` (`lib/app/data/utils/formatting_helper.dart`) already provides `formatQtyGrouped(double?)` → `2400.0` renders `"2,400"`, `2400.5` renders `"2,400.5"` (display) and `formatQty(double?)` → `2400.0` renders `"2400"` (plain — use for editable fields, since separators break `double.tryParse`).
- **Dart import collision:** GetX and Dio both export `Response`. In providers and tests, import `package:get/get.dart' hide Response`. In `item_form_controller.dart` both are imported unhidden and it compiles only because the type name is never written — always use `final response = await ...`, never `Response response = ...`.
- **Verbatim v15 strings** (copy exactly, do not "fix"):
  - Section label: `Auto re-order`
  - Table label: `Reorder level based on Warehouse`
  - Table description: `Will also apply for variants unless overrridden` — **three r's, misspelled in the ERPNext source**
  - Valid `Item Reorder.material_request_type` options: `Purchase`, `Transfer`, `Material Issue`, `Manufacture` (note: `Transfer`, **not** `Material Transfer`)
- **Never run `flutter analyze` and `flutter test` concurrently** — they deadlock. Run test files individually.
- **CI does not run tests.** `.github/workflows/release.yml` only builds and uploads. Tests are a local-only gate — actually run them.
- Test file command: `flutter test test/unit/foo_test.dart`
- Single test command: `flutter test test/unit/foo_test.dart --plain-name "the test name"`

---

## File Structure

### New files

| File | Responsibility |
|---|---|
| `lib/app/modules/item/form/reorder_rules.dart` | Pure v15 validation + type-default logic. No GetX, no network. |
| `lib/app/modules/item/form/widgets/reorder_rule_card.dart` | Renders one `ItemReorder` as a card. |
| `lib/app/modules/item/form/widgets/reorder_rule_sheet.dart` | Bottom-sheet editor for one row. |
| `test/unit/item_reorder_model_test.dart` | Model parse/serialise. |
| `test/unit/reorder_rules_test.dart` | Pure validation rules. |
| `test/unit/item_form_reorder_controller_test.dart` | Controller state + save path. |
| `test/widget/reorder_rule_card_test.dart` | Card rendering + dark-mode/contrast. |
| `test/widget/reorder_rule_sheet_test.dart` | Sheet fields + dark-mode surface. |
| `test/widget/reorder_tab_test.dart` | Save-bar spinner repaint. |

### Modified files

| File | Change |
|---|---|
| `lib/app/data/models/item_model.dart` | Add `ItemReorder`; `Item` gains `reorderLevels`, `isStockItem`, `defaultMaterialRequestType`, `modified`. |
| `lib/app/data/providers/warehouse_provider.dart` | `getWarehouses` gains `isGroup` filter. |
| `lib/app/data/providers/item_provider.dart` | Add `updateReorderLevels`, `getStockSettings`. |
| `lib/app/modules/item/form/item_form_controller.dart` | First write path: reorder state, dirty diff, validation, save. |
| `lib/app/modules/item/form/item_tab_controller.dart` | `length: 4` → `5`. |
| `lib/app/modules/item/form/item_form_screen.dart` | 5th tab, banner, footer save, `PopScope`, guarded Close. |
| `lib/app/modules/home/home_controller.dart` | `enableDrag: false` on the item sheet. |
| `lib/app/data/constants/permission_entries.dart` | Add `(doctype: 'Item', permType: 'write')`. |
| `pubspec.yaml` | `2.11.0+50` → `2.12.0+51`. |

---

### Task 1: `ItemReorder` model + `Item` field parsing

**Files:**
- Modify: `lib/app/data/models/item_model.dart`
- Test: `test/unit/item_reorder_model_test.dart` (create)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class ItemReorder` with `final String? name; final String? warehouseGroup; final String warehouse; final double warehouseReorderLevel; final double warehouseReorderQty; final String materialRequestType;`
  - `ItemReorder.fromJson(Map<String, dynamic>)`, `Map<String, dynamic> toJson()`, `ItemReorder copyWith({...})`
  - `Item` gains `List<ItemReorder> reorderLevels`, `bool isStockItem`, `String? defaultMaterialRequestType`, `String? modified`.

- [ ] **Step 1: Write the failing test**

Create `test/unit/item_reorder_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/item_model.dart';

void main() {
  group('ItemReorder.fromJson', () {
    test('parses a full row', () {
      final r = ItemReorder.fromJson({
        'name': 'abc123',
        'warehouse_group': 'Finished Goods - KA',
        'warehouse': 'WH-DXB1 - KA',
        'warehouse_reorder_level': 2400,
        'warehouse_reorder_qty': 2400.5,
        'material_request_type': 'Purchase',
      });

      expect(r.name, 'abc123');
      expect(r.warehouseGroup, 'Finished Goods - KA');
      expect(r.warehouse, 'WH-DXB1 - KA');
      expect(r.warehouseReorderLevel, 2400.0);
      expect(r.warehouseReorderQty, 2400.5);
      expect(r.materialRequestType, 'Purchase');
    });

    test('normalises a blank warehouse_group to null', () {
      final r = ItemReorder.fromJson({'warehouse': 'WH-A', 'warehouse_group': ''});
      expect(r.warehouseGroup, isNull);
    });

    test('defaults missing numerics to zero', () {
      final r = ItemReorder.fromJson({'warehouse': 'WH-A'});
      expect(r.warehouseReorderLevel, 0.0);
      expect(r.warehouseReorderQty, 0.0);
      expect(r.materialRequestType, '');
    });
  });

  group('ItemReorder.toJson', () {
    test('mirrors item.py:508-509 — blank group defaults to the warehouse', () {
      final r = ItemReorder(warehouse: 'WH-A', materialRequestType: 'Purchase');
      expect(r.toJson()['warehouse_group'], 'WH-A');
    });

    test('keeps an explicit group untouched', () {
      final r = ItemReorder(
        warehouseGroup: 'Stores - KA',
        warehouse: 'WH-A',
        materialRequestType: 'Purchase',
      );
      expect(r.toJson()['warehouse_group'], 'Stores - KA');
    });

    test('omits name for a new row and includes it for an existing one', () {
      final fresh = ItemReorder(warehouse: 'WH-A', materialRequestType: 'Purchase');
      expect(fresh.toJson().containsKey('name'), isFalse);

      final existing = ItemReorder(
        name: 'abc123',
        warehouse: 'WH-A',
        materialRequestType: 'Purchase',
      );
      expect(existing.toJson()['name'], 'abc123');
    });

    test('round-trips through fromJson', () {
      final original = ItemReorder(
        name: 'abc123',
        warehouseGroup: 'Stores - KA',
        warehouse: 'WH-A',
        warehouseReorderLevel: 10,
        warehouseReorderQty: 20,
        materialRequestType: 'Transfer',
      );
      final again = ItemReorder.fromJson(original.toJson());

      expect(again.name, original.name);
      expect(again.warehouseGroup, original.warehouseGroup);
      expect(again.warehouse, original.warehouse);
      expect(again.warehouseReorderLevel, original.warehouseReorderLevel);
      expect(again.warehouseReorderQty, original.warehouseReorderQty);
      expect(again.materialRequestType, original.materialRequestType);
    });
  });

  group('Item.fromJson reorder fields', () {
    test('parses reorder_levels', () {
      final item = Item.fromJson({
        'name': 'ITEM-1',
        'reorder_levels': [
          {'warehouse': 'WH-A', 'material_request_type': 'Purchase'},
          {'warehouse': 'WH-B', 'material_request_type': 'Transfer'},
        ],
      });
      expect(item.reorderLevels.length, 2);
      expect(item.reorderLevels.first.warehouse, 'WH-A');
    });

    test('absent reorder_levels yields an empty list', () {
      final item = Item.fromJson({'name': 'ITEM-1'});
      expect(item.reorderLevels, isEmpty);
    });

    test('parses is_stock_item as an int check', () {
      expect(Item.fromJson({'is_stock_item': 1}).isStockItem, isTrue);
      expect(Item.fromJson({'is_stock_item': 0}).isStockItem, isFalse);
      expect(Item.fromJson({}).isStockItem, isFalse);
    });

    test('parses default_material_request_type and modified', () {
      final item = Item.fromJson({
        'default_material_request_type': 'Purchase',
        'modified': '2026-07-17 09:00:00',
      });
      expect(item.defaultMaterialRequestType, 'Purchase');
      expect(item.modified, '2026-07-17 09:00:00');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/item_reorder_model_test.dart`
Expected: FAIL — compile errors, `ItemReorder` is not defined.

- [ ] **Step 3: Write the implementation**

In `lib/app/data/models/item_model.dart`, add `ItemReorder` **above** `class Item` (after `ItemCustomerDetail`):

```dart
/// One row of `Item.reorder_levels` — the ERPNext `Item Reorder` child DocType.
///
/// Desk labels, for reference:
///   warehouse_group        → "Check in (group)"   (optional)
///   warehouse              → "Request for"        (mandatory)
///   warehouse_reorder_level→ "Re-order Level"
///   warehouse_reorder_qty  → "Re-order Qty"
///   material_request_type  → "Material Request Type" (mandatory)
///
/// `warehouse_group` is where stock is *measured*; `warehouse` is where the
/// Material Request is *raised*.
class ItemReorder {
  /// Child-row name. Null for a row that has never been saved — [toJson]
  /// omits the key so Frappe inserts rather than tries to update.
  final String? name;

  /// "Check in (group)". Null when unset; [toJson] defaults it to [warehouse],
  /// mirroring erpnext item.py:508-509.
  final String? warehouseGroup;

  /// "Request for". Mandatory server-side.
  final String warehouse;

  final double warehouseReorderLevel;
  final double warehouseReorderQty;

  /// Mandatory server-side. One of `Purchase`, `Transfer`, `Material Issue`,
  /// `Manufacture` — empty string when unset.
  final String materialRequestType;

  const ItemReorder({
    this.name,
    this.warehouseGroup,
    required this.warehouse,
    this.warehouseReorderLevel = 0,
    this.warehouseReorderQty = 0,
    this.materialRequestType = '',
  });

  factory ItemReorder.fromJson(Map<String, dynamic> json) {
    final group = json['warehouse_group']?.toString();
    return ItemReorder(
      name: json['name']?.toString(),
      // Frappe returns '' for an unset Link; normalise so the UI and the
      // dirty-diff see one canonical "unset".
      warehouseGroup: (group == null || group.isEmpty) ? null : group,
      warehouse: json['warehouse']?.toString() ?? '',
      warehouseReorderLevel:
          (json['warehouse_reorder_level'] as num?)?.toDouble() ?? 0.0,
      warehouseReorderQty:
          (json['warehouse_reorder_qty'] as num?)?.toDouble() ?? 0.0,
      materialRequestType: json['material_request_type']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        // item.py:508-509 defaults a blank group to the warehouse on save.
        // Applying it here keeps the payload identical to what Desk would
        // persist, so the dirty-diff baseline matches what comes back.
        'warehouse_group':
            (warehouseGroup == null || warehouseGroup!.isEmpty)
                ? warehouse
                : warehouseGroup,
        'warehouse': warehouse,
        'warehouse_reorder_level': warehouseReorderLevel,
        'warehouse_reorder_qty': warehouseReorderQty,
        'material_request_type': materialRequestType,
      };

  ItemReorder copyWith({
    String? name,
    String? warehouseGroup,
    bool clearWarehouseGroup = false,
    String? warehouse,
    double? warehouseReorderLevel,
    double? warehouseReorderQty,
    String? materialRequestType,
  }) =>
      ItemReorder(
        name: name ?? this.name,
        warehouseGroup:
            clearWarehouseGroup ? null : (warehouseGroup ?? this.warehouseGroup),
        warehouse: warehouse ?? this.warehouse,
        warehouseReorderLevel:
            warehouseReorderLevel ?? this.warehouseReorderLevel,
        warehouseReorderQty: warehouseReorderQty ?? this.warehouseReorderQty,
        materialRequestType: materialRequestType ?? this.materialRequestType,
      );
}
```

Then extend `Item`. Add these fields after `customerItems`:

```dart
  final List<ItemReorder> reorderLevels;

  /// Desk hides the Auto re-order section when this is false
  /// (`depends_on: "is_stock_item"`).
  final bool isStockItem;

  /// Seeds a new reorder row's type — see `defaultReorderTypeFor`.
  final String? defaultMaterialRequestType;

  /// Optimistic-lock token sent back on update.
  final String? modified;
```

Add to the constructor:

```dart
    this.reorderLevels = const [],
    this.isStockItem = false,
    this.defaultMaterialRequestType,
    this.modified,
```

And in `Item.fromJson`, before the `return`:

```dart
    var reorderList = json['reorder_levels'] as List? ?? [];
    List<ItemReorder> reorderLevels = reorderList
        .whereType<Map<String, dynamic>>()
        .map((i) => ItemReorder.fromJson(i))
        .toList();
```

Add to the returned `Item(...)`:

```dart
      reorderLevels: reorderLevels,
      // Frappe Check fields arrive as int 0/1; tolerate bool/string too.
      isStockItem: json['is_stock_item'] == 1 ||
          json['is_stock_item'] == true ||
          json['is_stock_item'] == '1',
      defaultMaterialRequestType: json['default_material_request_type'],
      modified: json['modified'],
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/item_reorder_model_test.dart`
Expected: PASS — 11 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/models/item_model.dart test/unit/item_reorder_model_test.dart
git commit -m "feat(item): add ItemReorder model and parse reorder_levels on Item

The Item resource payload already returned reorder_levels; Item.fromJson
discarded it. toJson mirrors erpnext item.py:508-509 by defaulting a blank
warehouse_group to the warehouse.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Pure v15 reorder rules

**Files:**
- Create: `lib/app/modules/item/form/reorder_rules.dart`
- Test: `test/unit/reorder_rules_test.dart` (create)

**Interfaces:**
- Consumes: `ItemReorder` (Task 1).
- Produces:
  - `const List<String> kReorderMaterialRequestTypes`
  - `String defaultReorderTypeFor(String? itemDefaultMaterialRequestType)`
  - `String? validateReorderRows(List<ItemReorder> rows)` — returns the first error message, or `null` when valid.

Kept GetX-free and network-free deliberately: these are the rules most worth testing and they should not need a controller or a `Get.put` to exercise.

- [ ] **Step 1: Write the failing test**

Create `test/unit/reorder_rules_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/modules/item/form/reorder_rules.dart';

ItemReorder _row({
  String warehouse = 'WH-A',
  String type = 'Purchase',
  double level = 0,
  double qty = 0,
}) =>
    ItemReorder(
      warehouse: warehouse,
      materialRequestType: type,
      warehouseReorderLevel: level,
      warehouseReorderQty: qty,
    );

void main() {
  group('defaultReorderTypeFor', () {
    test('passes Purchase through', () {
      expect(defaultReorderTypeFor('Purchase'), 'Purchase');
    });

    test('remaps Material Transfer to Transfer (item.js:292-298)', () {
      expect(defaultReorderTypeFor('Material Transfer'), 'Transfer');
    });

    test('passes Material Issue and Manufacture through', () {
      expect(defaultReorderTypeFor('Material Issue'), 'Material Issue');
      expect(defaultReorderTypeFor('Manufacture'), 'Manufacture');
    });

    test('returns empty for Customer Provided — not a valid Item Reorder option',
        () {
      // v15 Desk copies this verbatim, producing an invalid Select value.
      // We deliberately leave it unset instead.
      expect(defaultReorderTypeFor('Customer Provided'), '');
    });

    test('returns empty for null or empty input', () {
      expect(defaultReorderTypeFor(null), '');
      expect(defaultReorderTypeFor(''), '');
    });
  });

  group('validateReorderRows', () {
    test('accepts an empty list', () {
      expect(validateReorderRows([]), isNull);
    });

    test('accepts a valid row', () {
      expect(validateReorderRows([_row(level: 100, qty: 50)]), isNull);
    });

    test('rejects a blank warehouse', () {
      final err = validateReorderRows([_row(warehouse: '')]);
      expect(err, contains('Row #1'));
      expect(err, contains('Request for'));
    });

    test('rejects a blank material request type', () {
      final err = validateReorderRows([_row(type: '')]);
      expect(err, contains('Row #1'));
      expect(err, contains('material request type'));
    });

    test('rejects a duplicate (warehouse, type) pair', () {
      final err = validateReorderRows([
        _row(warehouse: 'WH-A', type: 'Purchase'),
        _row(warehouse: 'WH-A', type: 'Purchase'),
      ]);
      expect(err, contains('Row #2'));
      expect(err, contains('already exists'));
      expect(err, contains('WH-A'));
    });

    test('allows the same warehouse with a different type', () {
      // item.py:510-518 keys uniqueness on the TUPLE, not warehouse alone.
      expect(
        validateReorderRows([
          _row(warehouse: 'WH-A', type: 'Purchase'),
          _row(warehouse: 'WH-A', type: 'Transfer'),
        ]),
        isNull,
      );
    });

    test('rejects a level with no qty (item.py:520-521)', () {
      final err = validateReorderRows([_row(level: 100, qty: 0)]);
      expect(err, contains('Row #1'));
      expect(err, contains('Please set reorder quantity'));
    });

    test('allows a qty with no level — the check is one-directional', () {
      expect(validateReorderRows([_row(level: 0, qty: 50)]), isNull);
    });

    test('reports the row number of the offending row, 1-based', () {
      final err = validateReorderRows([
        _row(warehouse: 'WH-A'),
        _row(warehouse: 'WH-B'),
        _row(warehouse: 'WH-C', level: 5, qty: 0),
      ]);
      expect(err, contains('Row #3'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/reorder_rules_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'reorder_rules'` / undefined functions.

- [ ] **Step 3: Write the implementation**

Create `lib/app/modules/item/form/reorder_rules.dart`:

```dart
import 'package:multimax/app/data/models/item_model.dart';

/// Valid `Item Reorder.material_request_type` options in ERPNext version-15.
///
/// Note `Transfer`, not `Material Transfer` — the value is remapped to
/// `Material Transfer` server-side when the Material Request is created.
const List<String> kReorderMaterialRequestTypes = [
  'Purchase',
  'Transfer',
  'Material Issue',
  'Manufacture',
];

/// The type a newly added reorder row should start with.
///
/// Mirrors erpnext item.js:292-298, which seeds the row from the Item's
/// `default_material_request_type`, remapping `Material Transfer` → `Transfer`.
///
/// **Deliberate deviation from v15:** `Item.default_material_request_type` also
/// offers `Customer Provided`, which is *not* a valid `Item Reorder` option.
/// Desk copies it verbatim and produces a row carrying an invalid Select value.
/// Here an unmappable default returns `''` so the user must choose explicitly.
String defaultReorderTypeFor(String? itemDefaultMaterialRequestType) {
  final t = itemDefaultMaterialRequestType;
  if (t == null || t.isEmpty) return '';
  final mapped = t == 'Material Transfer' ? 'Transfer' : t;
  return kReorderMaterialRequestTypes.contains(mapped) ? mapped : '';
}

/// Client-side mirror of `validate_warehouse_for_reorder`
/// (erpnext item.py:497-534) for the checks evaluable without the warehouse
/// tree. Returns the first error message, or null when [rows] are valid.
///
/// **Not checked here:** that `warehouse` is a descendant of `warehouse_group`
/// (item.py:523-534). That needs the warehouse tree; the server is the
/// authority and its message is already specific, so it is surfaced verbatim
/// from the save response instead.
String? validateReorderRows(List<ItemReorder> rows) {
  final seen = <String>{};

  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final rowNo = i + 1;

    if (r.warehouse.trim().isEmpty) {
      return 'Row #$rowNo: Please select a warehouse in "Request for"';
    }
    if (r.materialRequestType.trim().isEmpty) {
      return 'Row #$rowNo: Please set the material request type';
    }

    // item.py:510-518 — uniqueness is the (warehouse, type) TUPLE. Two rows
    // for one warehouse with different types are legal.
    final key = '${r.warehouse}|${r.materialRequestType}';
    if (!seen.add(key)) {
      return 'Row #$rowNo: A reorder entry already exists for warehouse '
          '${r.warehouse} with reorder type ${r.materialRequestType}.';
    }

    // item.py:520-521 — one-directional: qty-without-level is allowed.
    if (r.warehouseReorderLevel != 0 && r.warehouseReorderQty == 0) {
      return 'Row #$rowNo: Please set reorder quantity';
    }
  }

  return null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/reorder_rules_test.dart`
Expected: PASS — 15 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/item/form/reorder_rules.dart test/unit/reorder_rules_test.dart
git commit -m "feat(item): add pure v15 reorder validation rules

Mirrors item.py:497-534 duplicate/mandatory checks and item.js:292-298 type
defaulting. Deviates from v15 on Customer Provided: Desk writes it verbatim
as an invalid Select value, we leave the type unset.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Provider methods

**Files:**
- Modify: `lib/app/data/providers/warehouse_provider.dart`
- Modify: `lib/app/data/providers/item_provider.dart`

**Interfaces:**
- Consumes: `ApiProvider.getDocument(String, String)` (`api_provider.dart:305`), `ApiProvider.updateDocument(String, String, Map<String, dynamic>)` (`api_provider.dart:315`), `ApiProvider.getDocumentList(...)`.
- Produces:
  - `WarehouseProvider.getWarehouses({bool includeGroups = false, bool? isGroup})`
  - `ItemProvider.updateReorderLevels(String itemCode, Map<String, dynamic> data)`
  - `ItemProvider.getStockSettings()`

No dedicated test: these are thin passthroughs with no logic, and the repo has no provider-level tests. They are exercised through the controller fakes in Task 4.

- [ ] **Step 1: Add the `isGroup` filter to `WarehouseProvider`**

Replace the whole of `lib/app/data/providers/warehouse_provider.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class WarehouseProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  /// [isGroup] selects group-only (`true`) or leaf-only (`false`) warehouses,
  /// mirroring the reorder link filters in erpnext item.js:449-473
  /// ("Check in (group)" → `is_group: 1`, "Request for" → `is_group: 0`).
  /// When null, [includeGroups] keeps the historical behaviour: leaf-only
  /// unless groups are explicitly requested.
  Future<Response> getWarehouses({
    bool includeGroups = false,
    bool? isGroup,
  }) async {
    return _apiProvider.getDocumentList(
      'Warehouse',
      limit: 0, // fetch all — warehouse list is small
      fields: ['name', 'warehouse_name', 'is_group', 'disabled'],
      filters: {
        if (isGroup != null)
          'is_group': isGroup ? 1 : 0
        else if (!includeGroups)
          'is_group': 0,
        'disabled': 0,
      },
      orderBy: 'name asc',
    );
  }
}
```

- [ ] **Step 2: Add the two `ItemProvider` methods**

In `lib/app/data/providers/item_provider.dart`, add both methods immediately after `getBatchWiseHistory` (before the closing `}` of `class ItemProvider`):

```dart
  /// Writes `reorder_levels` back onto the Item.
  ///
  /// [data] must carry the full `reorder_levels` array — Frappe replaces the
  /// child table wholesale, so any row omitted here is deleted — plus the
  /// optimistic-lock `modified` token.
  Future<Response> updateReorderLevels(
    String itemCode,
    Map<String, dynamic> data,
  ) async {
    return _apiProvider.updateDocument('Item', itemCode, data);
  }

  /// Reads the `Stock Settings` Single.
  ///
  /// Needed for `auto_indent`, which erpnext version-15 defaults to 0 — with
  /// it off, reorder rows never raise Material Requests. Requires read
  /// permission on Stock Settings; the resource API 403s for non-System
  /// Managers, so callers must fail open rather than showing a false alarm.
  Future<Response> getStockSettings() async {
    return _apiProvider.getDocument('Stock Settings', 'Stock Settings');
  }
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/app/data/providers/warehouse_provider.dart lib/app/data/providers/item_provider.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/app/data/providers/warehouse_provider.dart lib/app/data/providers/item_provider.dart
git commit -m "feat(item): add reorder write and Stock Settings read to providers

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Controller — reorder state, dirty diff, save

**Files:**
- Modify: `lib/app/modules/item/form/item_form_controller.dart`
- Test: `test/unit/item_form_reorder_controller_test.dart` (create)

**Interfaces:**
- Consumes: `ItemReorder`, `Item.reorderLevels/isStockItem/defaultMaterialRequestType/modified` (Task 1); `validateReorderRows`, `defaultReorderTypeFor` (Task 2); `ItemProvider.updateReorderLevels`, `ItemProvider.getStockSettings` (Task 3); `OptimisticLockingMixin` (`lib/app/data/mixins/optimistic_locking_mixin.dart`); `SaveResult` (`lib/app/data/enums/save_result.dart`).
- Produces:
  - `RxList<ItemReorder> reorderRows`
  - `RxBool isSavingReorder`, `RxBool isReorderDirty`, `RxBool autoIndentEnabled`
  - `void addReorderRow(ItemReorder)`, `void updateReorderRow(int, ItemReorder)`, `void removeReorderRow(int)`
  - `ItemReorder newReorderRowTemplate()`
  - `Future<void> fetchAutoIndentSetting()`
  - `Future<void> saveReorderLevels()`
  - `Future<void> reloadDocument()` (mixin override)

`ItemFormController` currently `extends GetxController`. Adding `OptimisticLockingMixin` requires the `reloadDocument()` override — without it the file will not compile.

- [ ] **Step 1: Write the failing test**

Create `test/unit/item_form_reorder_controller_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';

class _FakeApiProvider extends ApiProvider {
  Map<String, dynamic>? getDocumentData;
  int getDocumentStatusCode = 200;

  @override
  Future<Response> getDocument(String doctype, String name) async {
    return Response(
      requestOptions: RequestOptions(path: '/api/resource/$doctype/$name'),
      statusCode: getDocumentStatusCode,
      data: getDocumentData == null ? null : {'data': getDocumentData},
    );
  }
}

class _FakeItemProvider extends ItemProvider {
  // updateReorderLevels
  String? lastUpdateItemCode;
  Map<String, dynamic>? lastUpdatePayload;
  int updateStatusCode = 200;
  Object? throwOnUpdate;

  @override
  Future<Response> updateReorderLevels(
    String itemCode,
    Map<String, dynamic> data,
  ) async {
    lastUpdateItemCode = itemCode;
    lastUpdatePayload = data;
    if (throwOnUpdate != null) throw throwOnUpdate!;
    return Response(
      requestOptions: RequestOptions(path: '/api/resource/Item/$itemCode'),
      statusCode: updateStatusCode,
    );
  }

  // getStockSettings
  dynamic autoIndentValue = 1;
  int stockSettingsStatusCode = 200;
  Object? throwOnStockSettings;

  @override
  Future<Response> getStockSettings() async {
    if (throwOnStockSettings != null) throw throwOnStockSettings!;
    return Response(
      requestOptions:
          RequestOptions(path: '/api/resource/Stock Settings/Stock Settings'),
      statusCode: stockSettingsStatusCode,
      data: {
        'data': {'auto_indent': autoIndentValue}
      },
    );
  }
}

Map<String, dynamic> _cannedItem({
  List<Map<String, dynamic>>? reorderLevels,
  int isStockItem = 1,
  String defaultType = 'Purchase',
  String modified = '2026-07-17 09:00:00',
}) =>
    {
      'name': 'ITEM-1',
      'item_name': 'Widget',
      'item_code': 'ITEM-1',
      'item_group': 'Products',
      'is_stock_item': isStockItem,
      'default_material_request_type': defaultType,
      'modified': modified,
      'reorder_levels': reorderLevels ?? const [],
    };

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ApiProvider's constructor fires _initDio(), which touches path_provider
    // for the cookie-jar directory — stub it so construction doesn't throw.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => '/tmp/test_cookies',
    );
  });

  late _FakeApiProvider fakeApi;
  late _FakeItemProvider fakeProvider;

  setUp(() {
    fakeApi = _FakeApiProvider();
    Get.put<ApiProvider>(fakeApi);
    fakeProvider = _FakeItemProvider();
    Get.put<ItemProvider>(fakeProvider);
  });

  tearDown(() => Get.deleteAll(force: true));

  Future<ItemFormController> loadedController({
    List<Map<String, dynamic>>? reorderLevels,
    int isStockItem = 1,
    String defaultType = 'Purchase',
  }) async {
    fakeApi.getDocumentData = _cannedItem(
      reorderLevels: reorderLevels,
      isStockItem: isStockItem,
      defaultType: defaultType,
    );
    final ctrl = ItemFormController();
    ctrl.itemCode = 'ITEM-1';
    await ctrl.fetchItemDetails();
    return ctrl;
  }

  group('reorder row seeding', () {
    test('seeds reorderRows from the fetched item', () async {
      final ctrl = await loadedController(reorderLevels: [
        {
          'name': 'r1',
          'warehouse': 'WH-A',
          'material_request_type': 'Purchase',
          'warehouse_reorder_level': 100,
          'warehouse_reorder_qty': 50,
        }
      ]);

      expect(ctrl.reorderRows.length, 1);
      expect(ctrl.reorderRows.first.warehouse, 'WH-A');
      expect(ctrl.isReorderDirty.value, isFalse);
    });

    test('seeds an empty list when the item has no rows', () async {
      final ctrl = await loadedController();
      expect(ctrl.reorderRows, isEmpty);
      expect(ctrl.isReorderDirty.value, isFalse);
    });
  });

  group('dirty tracking', () {
    test('adding a row marks dirty', () async {
      final ctrl = await loadedController();
      ctrl.addReorderRow(
        const ItemReorder(warehouse: 'WH-A', materialRequestType: 'Purchase'),
      );
      expect(ctrl.isReorderDirty.value, isTrue);
    });

    test('is a diff, not a latch — reverting clears dirty', () async {
      final ctrl = await loadedController(reorderLevels: [
        {'name': 'r1', 'warehouse': 'WH-A', 'material_request_type': 'Purchase'}
      ]);

      ctrl.addReorderRow(
        const ItemReorder(warehouse: 'WH-B', materialRequestType: 'Transfer'),
      );
      expect(ctrl.isReorderDirty.value, isTrue);

      ctrl.removeReorderRow(1);
      expect(ctrl.isReorderDirty.value, isFalse);
    });

    test('editing a row marks dirty', () async {
      final ctrl = await loadedController(reorderLevels: [
        {'name': 'r1', 'warehouse': 'WH-A', 'material_request_type': 'Purchase'}
      ]);

      ctrl.updateReorderRow(
        0,
        ctrl.reorderRows.first.copyWith(warehouseReorderLevel: 500),
      );
      expect(ctrl.isReorderDirty.value, isTrue);
    });
  });

  group('newReorderRowTemplate', () {
    test('defaults the type from the item default', () async {
      final ctrl = await loadedController(defaultType: 'Material Transfer');
      expect(ctrl.newReorderRowTemplate().materialRequestType, 'Transfer');
    });

    test('leaves the type blank for Customer Provided', () async {
      final ctrl = await loadedController(defaultType: 'Customer Provided');
      expect(ctrl.newReorderRowTemplate().materialRequestType, '');
    });
  });

  group('fetchAutoIndentSetting', () {
    test('auto_indent 0 disables', () async {
      final ctrl = await loadedController();
      fakeProvider.autoIndentValue = 0;
      await ctrl.fetchAutoIndentSetting();
      expect(ctrl.autoIndentEnabled.value, isFalse);
    });

    test('auto_indent 1 enables', () async {
      final ctrl = await loadedController();
      fakeProvider.autoIndentValue = 1;
      await ctrl.fetchAutoIndentSetting();
      expect(ctrl.autoIndentEnabled.value, isTrue);
    });

    test('fails OPEN on a 403 — no false alarm for non-System-Managers',
        () async {
      final ctrl = await loadedController();
      fakeProvider.throwOnStockSettings = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 403,
        ),
      );

      await ctrl.fetchAutoIndentSetting();

      expect(ctrl.autoIndentEnabled.value, isTrue,
          reason: 'a permission error must not render the warning banner');
    });
  });

  group('saveReorderLevels', () {
    test('sends the rows plus the optimistic-lock modified token', () async {
      final ctrl = await loadedController();
      ctrl.addReorderRow(const ItemReorder(
        warehouse: 'WH-A',
        materialRequestType: 'Purchase',
        warehouseReorderLevel: 100,
        warehouseReorderQty: 50,
      ));

      await ctrl.saveReorderLevels();

      expect(fakeProvider.lastUpdateItemCode, 'ITEM-1');
      expect(fakeProvider.lastUpdatePayload?['modified'],
          '2026-07-17 09:00:00');
      final sent =
          fakeProvider.lastUpdatePayload?['reorder_levels'] as List;
      expect(sent.length, 1);
      expect(sent.first['warehouse'], 'WH-A');
      // Blank group defaults to the warehouse (item.py:508-509).
      expect(sent.first['warehouse_group'], 'WH-A');
      expect(ctrl.isSavingReorder.value, isFalse);
    });

    test('blocks a duplicate (warehouse, type) and never calls the provider',
        () async {
      final ctrl = await loadedController();
      ctrl.addReorderRow(const ItemReorder(
          warehouse: 'WH-A', materialRequestType: 'Purchase'));
      ctrl.addReorderRow(const ItemReorder(
          warehouse: 'WH-A', materialRequestType: 'Purchase'));

      await ctrl.saveReorderLevels();

      expect(fakeProvider.lastUpdatePayload, isNull);
    });

    test('blocks a level with no qty', () async {
      final ctrl = await loadedController();
      ctrl.addReorderRow(const ItemReorder(
        warehouse: 'WH-A',
        materialRequestType: 'Purchase',
        warehouseReorderLevel: 100,
      ));

      await ctrl.saveReorderLevels();

      expect(fakeProvider.lastUpdatePayload, isNull);
    });

    test('re-entrancy guard skips a save already in flight', () async {
      final ctrl = await loadedController();
      ctrl.addReorderRow(const ItemReorder(
          warehouse: 'WH-A', materialRequestType: 'Purchase'));
      ctrl.isSavingReorder.value = true;

      await ctrl.saveReorderLevels();

      expect(fakeProvider.lastUpdatePayload, isNull);
    });

    test('surfaces the server message and clears the busy flag on failure',
        () async {
      final ctrl = await loadedController();
      ctrl.addReorderRow(const ItemReorder(
          warehouse: 'WH-A', materialRequestType: 'Purchase'));

      fakeProvider.throwOnUpdate = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 417,
          data: {
            '_server_messages':
                '["{\\"message\\": \\"Row #1: The warehouse <b>WH-A</b> is not a child warehouse of a group warehouse <b>G</b>\\"}"]'
          },
        ),
      );

      await ctrl.saveReorderLevels();

      expect(ctrl.isSavingReorder.value, isFalse);
    });

    test('extracts a Frappe _server_messages payload, stripped of HTML', () {
      final msg = ItemFormController.parseServerMessage({
        '_server_messages':
            '["{\\"message\\": \\"Row #1: The warehouse <b>WH-A</b> is not a child warehouse of a group warehouse <b>G</b>\\"}"]'
      });

      expect(
        msg,
        'Row #1: The warehouse WH-A is not a child warehouse of a group warehouse G',
      );
    });

    test('falls back to exception when _server_messages is absent', () {
      final msg = ItemFormController.parseServerMessage(
          {'exception': 'frappe.exceptions.ValidationError: Something broke'});
      expect(msg, 'Something broke');
    });

    test('falls back to a generic message for an unparseable body', () {
      expect(ItemFormController.parseServerMessage(null), 'Save failed');
      expect(ItemFormController.parseServerMessage({}), 'Save failed');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/item_form_reorder_controller_test.dart`
Expected: FAIL — `reorderRows`, `isReorderDirty`, `saveReorderLevels`, `parseServerMessage` etc. are not defined.

- [ ] **Step 3: Write the implementation**

**3a.** In `lib/app/modules/item/form/item_form_controller.dart`, add these imports to the existing block:

```dart
import 'dart:convert';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/modules/item/form/reorder_rules.dart';
```

**3b.** Change the class declaration (line 15):

```dart
class ItemFormController extends GetxController with OptimisticLockingMixin {
```

**3c.** Add the reorder state after the existing `isLoadingBatches` declaration:

```dart
  // ── Auto re-order ─────────────────────────────────────────────────────────
  /// Working copy of `Item.reorder_levels`, seeded on every successful fetch.
  var reorderRows = <ItemReorder>[].obs;

  /// True while [saveReorderLevels] is in flight.
  var isSavingReorder = false.obs;

  /// True when [reorderRows] differs from the last-fetched state.
  var isReorderDirty = false.obs;

  /// Mirrors `Stock Settings.auto_indent`. Defaults to **true** so the warning
  /// banner stays hidden until we positively learn the setting is off — a
  /// permission error must not produce a false alarm.
  var autoIndentEnabled = true.obs;

  /// JSON snapshot of [reorderRows] taken after each successful fetch, so the
  /// dirty flag is a diff rather than a one-way latch (reverting an edit
  /// clears it). Mirrors the DN/PO/PS/ToDo form controllers.
  String _originalReorderJson = '';

  bool _reorderTabLoaded = false;
  // ──────────────────────────────────────────────────────────────────────────
```

**3d.** Add `case 4` to `onTabChanged`:

```dart
      case 4:
        if (!_reorderTabLoaded) {
          _reorderTabLoaded = true;
          fetchAutoIndentSetting();
        }
        break;
```

**3e.** In `loadItem`, reset the new lazy-load flag alongside the existing ones:

```dart
    _reorderTabLoaded = false;
```

**3f.** In `fetchItemDetails`, seed the rows after `item.value` is assigned. The success branch becomes:

```dart
      if (response.statusCode == 200 && response.data['data'] != null) {
        item.value = Item.fromJson(response.data['data']);
        _seedReorderRows();
      } else {
```

**3g.** Add the reorder methods before the `isImage` helper:

```dart
  // ── Auto re-order ─────────────────────────────────────────────────────────

  @override
  Future<void> reloadDocument() async {
    await fetchItemDetails();
  }

  String _reorderJson(List<ItemReorder> rows) =>
      jsonEncode(rows.map((r) => r.toJson()).toList());

  void _seedReorderRows() {
    reorderRows.value =
        List<ItemReorder>.from(item.value?.reorderLevels ?? const []);
    _originalReorderJson = _reorderJson(reorderRows);
    isReorderDirty.value = false;
  }

  void _checkReorderDirty() {
    isReorderDirty.value = _reorderJson(reorderRows) != _originalReorderJson;
  }

  /// A blank row seeded with the item's default request type.
  ItemReorder newReorderRowTemplate() => ItemReorder(
        warehouse: '',
        materialRequestType:
            defaultReorderTypeFor(item.value?.defaultMaterialRequestType),
      );

  void addReorderRow(ItemReorder row) {
    reorderRows.add(row);
    _checkReorderDirty();
  }

  void updateReorderRow(int index, ItemReorder row) {
    if (index < 0 || index >= reorderRows.length) return;
    reorderRows[index] = row;
    _checkReorderDirty();
  }

  void removeReorderRow(int index) {
    if (index < 0 || index >= reorderRows.length) return;
    reorderRows.removeAt(index);
    _checkReorderDirty();
  }

  /// Reads `Stock Settings.auto_indent`.
  ///
  /// **Fails open by design.** Reading the Stock Settings Single needs
  /// permission on that doctype and the resource API 403s for non-System
  /// Managers. On any error [autoIndentEnabled] is left `true`, so the warning
  /// banner is simply not shown rather than shown wrongly.
  Future<void> fetchAutoIndentSetting() async {
    try {
      final response = await _provider.getStockSettings();
      if (response.statusCode == 200 && response.data?['data'] != null) {
        final v = response.data['data']['auto_indent'];
        autoIndentEnabled.value = v == 1 || v == true || v == '1';
      }
    } catch (e) {
      if (kDebugMode) log('Could not read Stock Settings.auto_indent: $e');
    }
  }

  /// Extracts a human-readable message from a Frappe error body.
  ///
  /// Frappe returns validation throws in `_server_messages` — a JSON-encoded
  /// list of JSON-encoded maps each carrying a `message`. The reorder
  /// descendant check (item.py:523-534) arrives this way, and its text is
  /// specific enough to be worth surfacing verbatim rather than replacing with
  /// a generic string. Public and static so it is unit-testable directly.
  static String parseServerMessage(dynamic data) {
    if (data is! Map) return 'Save failed';

    final raw = data['_server_messages'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List && decoded.isNotEmpty) {
          final messages = <String>[];
          for (final entry in decoded) {
            final m = entry is String ? jsonDecode(entry) : entry;
            final text = m is Map ? m['message'] : null;
            if (text != null) messages.add(text.toString());
          }
          if (messages.isNotEmpty) {
            // Frappe embeds <b>/<br> in throw messages.
            return messages
                .join('\n')
                .replaceAll(RegExp(r'<br\s*/?>'), '\n')
                .replaceAll(RegExp(r'<[^>]*>'), '')
                .trim();
          }
        }
      } catch (_) {
        // Malformed payload — fall through to the exception key.
      }
    }

    if (data['exception'] != null) {
      return data['exception'].toString().split(':').last.trim();
    }
    return 'Save failed';
  }

  /// Writes [reorderRows] back to `Item.reorder_levels`.
  ///
  /// The full array is sent: Frappe replaces the child table wholesale, so an
  /// omitted row is deleted. Existing rows carry their `name` and are updated
  /// in place; new rows omit it and are inserted.
  Future<void> saveReorderLevels() async {
    if (isSavingReorder.value) return;

    final error = validateReorderRows(reorderRows);
    if (error != null) {
      GlobalSnackbar.error(message: error);
      return;
    }
    if (checkStaleAndBlock()) return;

    isSavingReorder.value = true;

    final data = <String, dynamic>{
      'reorder_levels': reorderRows.map((r) => r.toJson()).toList(),
      'modified': item.value?.modified,
    };

    try {
      final response = await _provider.updateReorderLevels(itemCode, data);
      if (response.statusCode == 200) {
        // Reseeds rows and the dirty baseline from the server's own version,
        // which includes any warehouse_group the server defaulted for us.
        await fetchItemDetails();
        GlobalSnackbar.success(message: 'Re-order rules saved');
      } else {
        GlobalSnackbar.error(message: 'Failed to save re-order rules');
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      GlobalSnackbar.error(message: parseServerMessage(e.response?.data));
    } catch (e) {
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSavingReorder.value = false;
    }
  }
  // ──────────────────────────────────────────────────────────────────────────
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/item_form_reorder_controller_test.dart`
Expected: PASS — 16 tests.

- [ ] **Step 5: Verify the existing suite still passes**

The controller's class declaration changed, so re-run its neighbours:

Run: `flutter test test/unit/todo_form_controller_test.dart`
Expected: PASS (unchanged).

Run: `flutter analyze lib/app/modules/item/`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/item/form/item_form_controller.dart test/unit/item_form_reorder_controller_test.dart
git commit -m "feat(item): add reorder state, dirty diff and save path to ItemFormController

First business-field write path in the Item module. Applies OptimisticLockingMixin
for the modified token, parses Frappe _server_messages so the server's
warehouse-descendant throw surfaces verbatim, and fails open on the
Stock Settings read so a 403 never shows a false auto_indent warning.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `ReorderRuleCard` widget

**Files:**
- Create: `lib/app/modules/item/form/widgets/reorder_rule_card.dart`
- Test: `test/widget/reorder_rule_card_test.dart` (create)

**Interfaces:**
- Consumes: `ItemReorder` (Task 1).
- Produces: `ReorderRuleCard({required ItemReorder rule, required int index, VoidCallback? onEdit, VoidCallback? onDelete})`. Null `onEdit`/`onDelete` render the read-only state (no overflow menu) — that is how the permission gate hides editing.

- [ ] **Step 1: Write the failing test**

Create `test/widget/reorder_rule_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/modules/item/form/widgets/reorder_rule_card.dart';
import 'package:multimax/main.dart' show buildAppTheme;

/// WCAG 2.x contrast ratio between two opaque colours.
/// Each contrast test file declares its own — the helper is not shared
/// (see status_ink_contrast_test.dart, which does the same).
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  Widget app(Brightness b, Widget child) => MaterialApp(
        theme: buildAppTheme(AppScheme.of(b), b),
        home: Scaffold(body: child),
      );

  const rule = ItemReorder(
    warehouseGroup: 'Finished Goods - KA',
    warehouse: 'WH-DXB1 - KA',
    warehouseReorderLevel: 2400,
    warehouseReorderQty: 2400,
    materialRequestType: 'Purchase',
  );

  testWidgets('renders group, warehouse, levels and type', (tester) async {
    await tester.pumpWidget(
      app(Brightness.light, const ReorderRuleCard(rule: rule, index: 0)),
    );

    expect(find.text('Finished Goods - KA'), findsOneWidget);
    expect(find.text('WH-DXB1 - KA'), findsOneWidget);
    expect(find.text('Re-order at 2,400 · Order 2,400'), findsOneWidget);
    expect(find.text('Purchase'), findsOneWidget);
  });

  testWidgets('shows the warehouse as the group when the group is blank',
      (tester) async {
    // item.py:508-509 — a blank group behaves as the warehouse itself.
    await tester.pumpWidget(app(
      Brightness.light,
      const ReorderRuleCard(
        rule: ItemReorder(warehouse: 'WH-A', materialRequestType: 'Purchase'),
        index: 0,
      ),
    ));
    expect(find.text('WH-A'), findsNWidgets(2));
  });

  testWidgets('renders a placeholder when the type is unset', (tester) async {
    await tester.pumpWidget(app(
      Brightness.light,
      const ReorderRuleCard(
        rule: ItemReorder(warehouse: 'WH-A'),
        index: 0,
      ),
    ));
    expect(find.text('No request type'), findsOneWidget);
  });

  testWidgets('hides the overflow menu when not editable', (tester) async {
    await tester.pumpWidget(
      app(Brightness.light, const ReorderRuleCard(rule: rule, index: 0)),
    );
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('shows the overflow menu when editable', (tester) async {
    await tester.pumpWidget(app(
      Brightness.light,
      ReorderRuleCard(rule: rule, index: 0, onEdit: () {}, onDelete: () {}),
    ));
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  for (final b in Brightness.values) {
    testWidgets('warehouse ink is readable (>=4.5) on the card [$b]',
        (tester) async {
      await tester.pumpWidget(
        app(b, const ReorderRuleCard(rule: rule, index: 0)),
      );

      final scheme = AppScheme.of(b);
      final text = tester.widget<Text>(find.text('WH-DXB1 - KA'));
      // The card sits on scheme.subtle, so measure the ink against that.
      expect(
        _contrast(text.style!.color!, scheme.subtle),
        greaterThanOrEqualTo(4.5),
      );
    });
  }

  testWidgets('uses the themed surface, not a hardcoded white', (tester) async {
    final darkTheme = buildAppTheme(AppScheme.dark, Brightness.dark);
    await tester.pumpWidget(MaterialApp(
      theme: darkTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark,
      home: const Scaffold(body: ReorderRuleCard(rule: rule, index: 0)),
    ));

    final container = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('WH-DXB1 - KA'),
            matching: find.byType(Container),
          )
          .first,
    );
    final deco = container.decoration as BoxDecoration;
    expect(deco.color, isNot(Colors.white));
    expect(deco.color, AppScheme.dark.subtle);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/reorder_rule_card_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package` / `ReorderRuleCard` is not defined.

- [ ] **Step 3: Write the implementation**

Create `lib/app/modules/item/form/widgets/reorder_rule_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

/// One `Item.reorder_levels` row.
///
/// Reads as: *check stock across `warehouseGroup`, raise the request against
/// `warehouse`* — which is exactly what the ERPNext reorder engine does.
///
/// [onEdit]/[onDelete] null → read-only (no overflow menu). The Re-order tab
/// passes null when the user lacks `Item:write`.
class ReorderRuleCard extends StatelessWidget {
  const ReorderRuleCard({
    super.key,
    required this.rule,
    required this.index,
    this.onEdit,
    this.onDelete,
  });

  final ItemReorder rule;

  /// Zero-based position; rendered 1-based to match the server's "Row #N".
  final int index;

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final editable = onEdit != null || onDelete != null;

    // A blank group behaves as the warehouse itself (item.py:508-509), so show
    // that rather than an empty arrow.
    final group = (rule.warehouseGroup == null || rule.warehouseGroup!.isEmpty)
        ? rule.warehouse
        : rule.warehouseGroup!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.subtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        group,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.textMuted),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.arrow_forward,
                          size: 14, color: scheme.textSubtle),
                    ),
                    Flexible(
                      child: Text(
                        rule.warehouse,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Re-order at '
                  '${FormattingHelper.formatQtyGrouped(rule.warehouseReorderLevel)}'
                  ' · Order '
                  '${FormattingHelper.formatQtyGrouped(rule.warehouseReorderQty)}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  rule.materialRequestType.isEmpty
                      ? 'No request type'
                      : rule.materialRequestType,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.textSubtle),
                ),
              ],
            ),
          ),
          if (editable)
            PopupMenuButton<String>(
              tooltip: 'Rule ${index + 1} actions',
              icon: Icon(Icons.more_vert, color: scheme.textSubtle),
              onSelected: (v) {
                if (v == 'edit') onEdit?.call();
                if (v == 'delete') onDelete?.call();
              },
              itemBuilder: (_) => [
                if (onEdit != null)
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (onDelete != null)
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
    );
  }
}
```

> `FormattingHelper.formatQtyGrouped` (`lib/app/data/utils/formatting_helper.dart:80`)
> already renders `2400.0` → `"2,400"` and `2400.5` → `"2,400.5"` via a shared
> `NumberFormat('#,##0.##')`. Do not hand-roll a thousands separator.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/reorder_rule_card_test.dart`
Expected: PASS — 8 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/item/form/widgets/reorder_rule_card.dart \
        test/widget/reorder_rule_card_test.dart
git commit -m "feat(item): add ReorderRuleCard

Reads as: check stock across the group, raise the request against the
warehouse — which is what the reorder engine actually does.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: `ReorderRuleSheet` editor

**Files:**
- Create: `lib/app/modules/item/form/widgets/reorder_rule_sheet.dart`
- Test: `test/widget/reorder_rule_sheet_test.dart` (create)

**Interfaces:**
- Consumes: `ItemReorder` (Task 1), `kReorderMaterialRequestTypes` (Task 2), `WarehousePickerSheet` (`lib/app/modules/global_widgets/warehouse_picker_sheet.dart`), `DocPickerField`.
- Produces: `ReorderRuleSheet({required ItemReorder initial, required Future<List<String>> Function({required bool isGroup}) loadWarehouses, required ValueChanged<ItemReorder> onSaved})`.

Warehouse loading is injected as a callback rather than reaching for a provider, so the sheet stays a pure widget and is pumpable in a test without GetX registrations.

- [ ] **Step 1: Write the failing test**

A bottom sheet that hardcodes a light surface renders theme-default text at ~1.1:1 in dark mode — the exact failure `dark_mode_sheet_surfaces_test.dart` exists to catch. That file hand-lists each sheet it covers (there is no registry), so a new sheet is invisible until a block is written for it. This is that block, kept local to the feature.

Create `test/widget/reorder_rule_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/modules/item/form/widgets/reorder_rule_sheet.dart';
import 'package:multimax/main.dart' show buildAppTheme;

Future<List<String>> _fakeWarehouses({required bool isGroup}) async =>
    isGroup ? ['Stores - KA'] : ['WH-A', 'WH-B'];

void main() {
  final darkTheme = buildAppTheme(AppScheme.dark, Brightness.dark);
  final darkSurface = darkTheme.colorScheme.surface;

  /// Background colour of the first ancestor Container of [inner] that paints
  /// a BoxDecoration colour. Mirrors dark_mode_sheet_surfaces_test.dart.
  Color? sheetColorAbove(WidgetTester tester, Finder inner) {
    final containers =
        find.ancestor(of: inner, matching: find.byType(Container));
    for (final e in containers.evaluate()) {
      final deco = (e.widget as Container).decoration;
      if (deco is BoxDecoration && deco.color != null) return deco.color;
    }
    return null;
  }

  Widget darkApp(Widget child) => MaterialApp(
        theme: darkTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(body: child),
      );

  Widget sheet({ItemReorder? initial, ValueChanged<ItemReorder>? onSaved}) =>
      ReorderRuleSheet(
        initial: initial ??
            const ItemReorder(warehouse: '', materialRequestType: 'Purchase'),
        loadWarehouses: _fakeWarehouses,
        onSaved: onSaved ?? (_) {},
      );

  testWidgets('uses the themed surface, not a hardcoded white', (tester) async {
    await tester.pumpWidget(darkApp(sheet()));
    expect(sheetColorAbove(tester, find.text('Re-order rule')), darkSurface);
  });

  testWidgets('renders all five v15 fields with Desk labels', (tester) async {
    await tester.pumpWidget(darkApp(sheet()));

    expect(find.text('Check in (group)'), findsOneWidget);
    expect(find.text('Request for'), findsOneWidget);
    expect(find.text('Re-order Level'), findsOneWidget);
    expect(find.text('Re-order Qty'), findsOneWidget);
    expect(find.text('Material Request Type'), findsOneWidget);
  });

  testWidgets('a blank group reads as "Same as Request for"', (tester) async {
    // Mirrors item.py:508-509 rather than showing an empty field.
    await tester.pumpWidget(darkApp(sheet()));
    expect(find.text('Same as Request for'), findsOneWidget);
  });

  testWidgets('renders zero levels as blank, not "0"', (tester) async {
    await tester.pumpWidget(darkApp(sheet()));
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    for (final f in fields) {
      expect(f.controller?.text, '');
    }
  });

  testWidgets('seeds the fields from an existing rule', (tester) async {
    await tester.pumpWidget(darkApp(sheet(
      initial: const ItemReorder(
        warehouseGroup: 'Stores - KA',
        warehouse: 'WH-A',
        warehouseReorderLevel: 2400,
        warehouseReorderQty: 50,
        materialRequestType: 'Transfer',
      ),
    )));

    expect(find.text('Stores - KA'), findsOneWidget);
    expect(find.text('WH-A'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);

    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller?.text, '2400');
    expect(fields[1].controller?.text, '50');
  });

  testWidgets('Done emits the edited row', (tester) async {
    ItemReorder? saved;

    // Pushed modally rather than pumped as the only route: _save() ends with
    // Navigator.pop(), and popping the last route in a test navigator is not
    // safe. This also matches how the sheet is actually shown.
    await tester.pumpWidget(MaterialApp(
      theme: darkTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => sheet(
                  initial: const ItemReorder(
                    name: 'r1',
                    warehouse: 'WH-A',
                    materialRequestType: 'Purchase',
                  ),
                  onSaved: (r) => saved = r,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '300');
    await tester.enterText(find.byType(TextField).last, '150');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.name, 'r1', reason: 'the child-row name must survive an edit');
    expect(saved!.warehouseReorderLevel, 300);
    expect(saved!.warehouseReorderQty, 150);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/reorder_rule_sheet_test.dart`
Expected: FAIL — `ReorderRuleSheet` is not defined.

- [ ] **Step 3: Write the implementation**

Create `lib/app/modules/item/form/widgets/reorder_rule_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/app/modules/global_widgets/warehouse_picker_sheet.dart';
import 'package:multimax/app/modules/item/form/reorder_rules.dart';

/// Bottom-sheet editor for a single `Item.reorder_levels` row.
///
/// The Desk grid is five columns wide and has no mobile equivalent, so each
/// row is edited in its own sheet.
///
/// Link filters mirror erpnext item.js:449-473 — "Check in (group)" lists
/// group warehouses, "Request for" lists leaf warehouses. v15 *intends* to
/// narrow "Request for" to children of the chosen group but that branch is
/// dead upstream (`Item Reorder` has no `parent_warehouse` field, and
/// `filters.extend` is Python idiom that would throw in JS), so Desk lists
/// every leaf warehouse company-wide and so do we. A mismatched pair is caught
/// by the server's descendant check on save.
class ReorderRuleSheet extends StatefulWidget {
  const ReorderRuleSheet({
    super.key,
    required this.initial,
    required this.loadWarehouses,
    required this.onSaved,
  });

  final ItemReorder initial;

  /// Injected so the sheet needs no provider and stays pumpable in tests.
  final Future<List<String>> Function({required bool isGroup}) loadWarehouses;

  final ValueChanged<ItemReorder> onSaved;

  @override
  State<ReorderRuleSheet> createState() => _ReorderRuleSheetState();
}

class _ReorderRuleSheetState extends State<ReorderRuleSheet> {
  late String? _warehouseGroup;
  late String _warehouse;
  late String _type;

  late final TextEditingController _levelCtrl;
  late final TextEditingController _qtyCtrl;

  @override
  void initState() {
    super.initState();
    _warehouseGroup = widget.initial.warehouseGroup;
    _warehouse = widget.initial.warehouse;
    _type = widget.initial.materialRequestType;
    _levelCtrl =
        TextEditingController(text: _initialNum(widget.initial.warehouseReorderLevel));
    _qtyCtrl =
        TextEditingController(text: _initialNum(widget.initial.warehouseReorderQty));
  }

  /// Zero renders blank so the field reads as "unset" rather than "0".
  ///
  /// Uses formatQty, not formatQtyGrouped: this seeds an editable numeric
  /// field, and thousands separators would not survive double.tryParse.
  String _initialNum(double v) => v == 0 ? '' : FormattingHelper.formatQty(v);

  @override
  void dispose() {
    _levelCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickWarehouse({required bool isGroup}) async {
    final warehouses = await widget.loadWarehouses(isGroup: isGroup);
    if (!mounted) return;

    Get.bottomSheet(
      WarehousePickerSheet(
        warehouses: warehouses,
        isLoading: false,
        title: isGroup ? 'Select group warehouse' : 'Select warehouse',
        groupNames: isGroup ? warehouses.toSet() : const {},
        onSelected: (wh) => setState(() {
          if (isGroup) {
            _warehouseGroup = wh;
          } else {
            _warehouse = wh;
          }
        }),
      ),
      isScrollControlled: true,
    );
  }

  void _pickType() {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Material Request Type',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ...kReorderMaterialRequestTypes.map(
              (t) => ListTile(
                title: Text(t),
                trailing: t == _type ? const Icon(Icons.check) : null,
                onTap: () {
                  // Navigator.of(ctx).pop() rather than Get.back(): Get.back()
                  // calls closeCurrentSnackbar first, which throws when a
                  // Snackbar is queued but not yet attached to the Overlay.
                  Navigator.of(context).pop();
                  setState(() => _type = t);
                },
              ),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  void _save() {
    widget.onSaved(widget.initial.copyWith(
      warehouseGroup: _warehouseGroup,
      clearWarehouseGroup: _warehouseGroup == null,
      warehouse: _warehouse,
      materialRequestType: _type,
      warehouseReorderLevel: double.tryParse(_levelCtrl.text.trim()) ?? 0,
      warehouseReorderQty: double.tryParse(_qtyCtrl.text.trim()) ?? 0,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      // Lifts the sheet above the keyboard when the numeric fields focus.
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  'Re-order rule',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: scheme.text,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DocPickerField(
                label: 'Check in (group)',
                icon: Icons.account_tree_outlined,
                value: _warehouseGroup,
                placeholder: 'Same as Request for',
                helperText: 'Where stock is measured',
                trailingIcon: Icons.chevron_right,
                onTap: () => _pickWarehouse(isGroup: true),
              ),
              const SizedBox(height: 12),
              DocPickerField(
                label: 'Request for',
                icon: Icons.warehouse_outlined,
                value: _warehouse.isEmpty ? null : _warehouse,
                placeholder: 'Select warehouse',
                helperText: 'Where the Material Request is raised',
                trailingIcon: Icons.chevron_right,
                onTap: () => _pickWarehouse(isGroup: false),
              ),
              const SizedBox(height: 12),
              _numberField(context, 'Re-order Level', _levelCtrl),
              const SizedBox(height: 12),
              _numberField(context, 'Re-order Qty', _qtyCtrl),
              const SizedBox(height: 12),
              DocPickerField(
                label: 'Material Request Type',
                icon: Icons.playlist_add_check,
                value: _type.isEmpty ? null : _type,
                placeholder: 'Select type',
                trailingIcon: Icons.chevron_right,
                onTap: _pickType,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Done'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numberField(
      BuildContext context, String label, TextEditingController ctrl) {
    final scheme = context.scheme;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12, color: scheme.textMuted)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
          style: TextStyle(color: scheme.text),
          decoration: InputDecoration(
            hintText: '0',
            filled: true,
            fillColor: cs.surface,
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/reorder_rule_sheet_test.dart`
Expected: PASS — 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/item/form/widgets/reorder_rule_sheet.dart \
        test/widget/reorder_rule_sheet_test.dart
git commit -m "feat(item): add ReorderRuleSheet row editor

Warehouse loading is injected so the sheet needs no provider and stays
pumpable in widget tests. Link filters mirror item.js:449-473.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Wire the Re-order tab into the screen

**Files:**
- Modify: `lib/app/modules/item/form/item_tab_controller.dart:24`
- Modify: `lib/app/modules/item/form/item_form_screen.dart`
- Modify: `lib/app/data/constants/permission_entries.dart`

**Interfaces:**
- Consumes: everything from Tasks 1-6; `InlineBanner`/`BannerType` (`lib/app/modules/global_widgets/inline_banner.dart`), `DocTypeGuard`, `AsyncFilledButton`, `DocSectionCard`, `FormEmptyState`, `WarehouseProvider`.
- Produces: a 5th tab. No new public API.

- [ ] **Step 1: Bump the tab count**

In `lib/app/modules/item/form/item_tab_controller.dart`, line 24:

```dart
    tabController = TabController(length: 5, vsync: this);
```

- [ ] **Step 2: Register the write permission**

In `lib/app/data/constants/permission_entries.dart`, add to `kStockPermissions` after the `(doctype: 'Item', permType: 'report')` line:

```dart
  (doctype: 'Item',             permType: 'write'),  // Item Re-order rules editing
```

- [ ] **Step 3: Add the tab to the screen**

In `lib/app/modules/item/form/item_form_screen.dart`, add these imports:

```dart
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/providers/warehouse_provider.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/modules/global_widgets/inline_banner.dart';
import 'package:multimax/app/modules/item/form/widgets/reorder_rule_card.dart';
import 'package:multimax/app/modules/item/form/widgets/reorder_rule_sheet.dart';
```

Add the 5th `Tab` to the `TabBar` (after `Tab(text: 'Attachments')`):

```dart
                    Tab(text: 'Re-order'),
```

Add the 5th child to the `TabBarView` (after `_buildAttachmentsTab(context, cs)`):

```dart
                          _buildReorderTab(context, item, cs),
```

Then add the tab builder before the closing `}` of the class:

```dart
  // ── Re-order Tab ──────────────────────────────────────────────────────────

  /// Loads warehouses for the rule sheet's pickers.
  ///
  /// Filters mirror erpnext item.js:449-473 — group warehouses for
  /// "Check in (group)", leaf warehouses for "Request for".
  Future<List<String>> _loadWarehouses({required bool isGroup}) async {
    try {
      final response =
          await Get.find<WarehouseProvider>().getWarehouses(isGroup: isGroup);
      if (response.statusCode == 200 && response.data['data'] != null) {
        return (response.data['data'] as List)
            .map((w) => w['name'].toString())
            .toList();
      }
    } catch (_) {
      // Picker opens empty rather than throwing over the sheet.
    }
    return const [];
  }

  void _openRuleSheet(BuildContext context, {int? index}) {
    final isNew = index == null;
    final initial =
        isNew ? controller.newReorderRowTemplate() : controller.reorderRows[index];

    Get.bottomSheet(
      ReorderRuleSheet(
        initial: initial,
        loadWarehouses: _loadWarehouses,
        onSaved: (row) => isNew
            ? controller.addReorderRow(row)
            : controller.updateReorderRow(index, row),
      ),
      isScrollControlled: true,
    );
  }

  Widget _buildReorderTab(BuildContext context, Item item, ColorScheme cs) {
    final scheme = context.scheme;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    // Desk gates the section on `depends_on: "is_stock_item"`. The tab count
    // stays static at 5 — resizing a TabController built on
    // GetSingleTickerProviderStateMixin is fragile (see item_tab_controller.dart)
    // — so a non-stock item gets an empty state instead of a vanishing tab.
    if (!item.isStockItem) {
      return Center(
        child: const FormEmptyState(
          icon: Icons.inventory_2_outlined,
          message: 'Auto re-order applies to stock items only.',
        ),
      );
    }

    return Column(
      children: [
        // auto_indent defaults to 0 in v15, in which case these rules never
        // raise a Material Request. Desk only warns on save; warn always.
        Obx(() => InlineBanner(
              visible: !controller.autoIndentEnabled.value,
              message: 'Auto re-order is disabled in Stock Settings. '
                  'These rules will not raise Material Requests.',
              type: BannerType.warning,
            )),
        Expanded(
          child: Obx(() {
            final rows = controller.reorderRows;
            final canWrite =
                Get.find<PermissionService>().hasAccess('Item', permType: 'write') ??
                    false;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DocSectionCard(
                    title: 'Auto re-order',
                    children: [
                      Text(
                        'Reorder level based on Warehouse',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.textMuted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // "overrridden" is misspelled in the ERPNext source;
                        // kept verbatim.
                        'Will also apply for variants unless overrridden',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.textSubtle),
                      ),
                      const SizedBox(height: 12),
                      if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No re-order rules. Nothing will be re-ordered '
                            'automatically for this item.',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.textMuted),
                          ),
                        ),
                      ...rows.asMap().entries.map(
                            (e) => ReorderRuleCard(
                              rule: e.value,
                              index: e.key,
                              onEdit: canWrite
                                  ? () => _openRuleSheet(context, index: e.key)
                                  : null,
                              onDelete: canWrite
                                  ? () => controller.removeReorderRow(e.key)
                                  : null,
                            ),
                          ),
                      DocTypeGuard(
                        doctype: 'Item',
                        permType: 'write',
                        fallback: const SizedBox.shrink(),
                        loading: const SizedBox.shrink(),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => _openRuleSheet(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Add rule'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Mirrors the Desk description: a variant with no rules of
                  // its own falls back to the template's at scheduler time.
                  // Stored rows only are shown — inheritance is computed
                  // server-side in memory and never persisted, so rendering the
                  // template's rows here would misrepresent stored state.
                  if (item.variantOf != null && rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'No rules of its own. The template\'s rules apply '
                        'unless you add rules here.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.textSubtle),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        // The save bar appears only when there is something to save, so the
        // button is never enabled-but-inert. AsyncFilledButton requires a
        // non-null onPressed, so visibility is the disable mechanism.
        Obx(() {
          if (!controller.isReorderDirty.value) return const SizedBox.shrink();
          return DocTypeGuard(
            doctype: 'Item',
            permType: 'write',
            fallback: const SizedBox.shrink(),
            loading: const SizedBox.shrink(),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomInset),
              decoration: BoxDecoration(
                color: scheme.fg,
                border: Border(
                    top: BorderSide(color: cs.outlineVariant)),
              ),
              child: AsyncFilledButton(
                busy: controller.isSavingReorder,
                onPressed: controller.saveReorderLevels,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: 'Save re-order rules',
                loadingLabel: 'Saving…',
              ),
            ),
          );
        }),
      ],
    );
  }
```

Add the `PermissionService` import used above:

```dart
import 'package:multimax/app/data/services/permission_service.dart';
```

- [ ] **Step 4: Register `WarehouseProvider` in the binding**

`_loadWarehouses` calls `Get.find<WarehouseProvider>()`, so it must be registered. In `lib/app/modules/item/form/item_form_binding.dart`, add inside `dependencies()` **after** the two existing registrations:

```dart
    Get.lazyPut<WarehouseProvider>(() => WarehouseProvider(), fenix: true);
```

and the import:

```dart
import 'package:multimax/app/data/providers/warehouse_provider.dart';
```

The modal path (`home_controller._openItemDetailSheet`) bypasses the binding, so also register it there — see Task 8 Step 2.

- [ ] **Step 5: Verify it compiles**

Run: `flutter analyze lib/app/modules/item/ lib/app/data/constants/permission_entries.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/item/form/item_tab_controller.dart \
        lib/app/modules/item/form/item_form_screen.dart \
        lib/app/modules/item/form/item_form_binding.dart \
        lib/app/data/constants/permission_entries.dart
git commit -m "feat(item): add Re-order tab to the Item form

Fifth tab with the auto_indent warning banner, rule cards, a bottom-sheet
row editor and a dirty-gated footer save. Editing affordances are gated on
Item:write; the section stays readable without it.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Guard against losing unsaved rules

**Files:**
- Modify: `lib/app/modules/item/form/item_form_screen.dart`
- Modify: `lib/app/modules/home/home_controller.dart:607-626`
- Test: `test/widget/reorder_tab_test.dart` (create)

**Interfaces:**
- Consumes: `controller.isReorderDirty` (Task 4), `GlobalDialog` (`lib/app/modules/global_widgets/global_dialog.dart`).
- Produces: no new public API.

The Item form is hosted both as a route and as a bottom sheet opened with `enableDrag: true`. `PopScope` guards the system back button but does **not** intercept a modal sheet's drag-dismiss, which calls `Navigator.pop` directly. `Get.bottomSheet`'s `enableDrag` is fixed at open time and cannot react to dirty state, so the deterministic fix is to disable dragging on the item sheet and route its Close button through the same confirm. The trade-off — no swipe-to-dismiss on the item sheet — is accepted; the Close button is already present.

- [ ] **Step 1: Pin the save-bar spinner**

CLAUDE.md is explicit that a clean `flutter analyze` proves nothing about loading feedback, and this repo already carries a regression test for the header variant of this trap. The footer save uses `AsyncFilledButton`, which owns its `Obx`; this pins that the icon→spinner swap actually paints.

Create `test/widget/reorder_tab_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/main.dart' show buildAppTheme;

void main() {
  testWidgets('save bar swaps icon for a spinner when the busy flag flips',
      (tester) async {
    final busy = false.obs;
    addTearDown(busy.close);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(AppScheme.light, Brightness.light),
      home: Scaffold(
        body: AsyncFilledButton(
          busy: busy,
          onPressed: () {},
          icon: const Icon(Icons.save_outlined, size: 18),
          label: 'Save re-order rules',
          loadingLabel: 'Saving…',
        ),
      ),
    ));

    expect(find.byIcon(Icons.save_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    busy.value = true;
    // Single pumps — pumpAndSettle would spin forever on the indefinite
    // CircularProgressIndicator.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Saving…'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it**

Run: `flutter test test/widget/reorder_tab_test.dart`
Expected: PASS — 1 test. This pins existing `AsyncFilledButton` behaviour rather than driving new code, so it passes on first run by design; it fails if someone later hand-rolls the save button and loses the `Obx`.

- [ ] **Step 3: Add the dismissal guard**

**3a.** In `lib/app/modules/item/form/item_form_screen.dart`, add the import:

```dart
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
```

**3b.** Add the confirm helper to the class:

```dart
  /// Confirms before discarding unsaved re-order rules. Returns true when the
  /// caller should proceed with closing.
  ///
  /// GlobalDialog.confirm returns null when dismissed by tapping outside, so
  /// only an explicit `true` discards — an accidental tap keeps the edits.
  Future<bool> _confirmDiscard() async {
    if (!controller.isReorderDirty.value) return true;
    final discard = await GlobalDialog.confirm(
      title: 'Discard changes?',
      message: 'Your re-order rules have not been saved.',
      confirmText: 'Discard',
      confirmColor: AppColors.red700,
      icon: Icons.warning_amber_outlined,
    );
    return discard == true;
  }
```

`GlobalDialog.confirm` is `Future<bool?> confirm({required String title, required String message, String confirmText = 'Confirm', Color confirmColor = AppColors.blue600, IconData icon = Icons.check_circle_outline})` (`global_dialog.dart:31-37`). **There is no `cancelText` parameter** — the cancel affordance is built in. `AppColors.red700` is the destructive token (there is no `red600`); this mirrors the delete-confirm call at `delivery_note_form_controller.dart:634-640`.

`AppColors` comes from `app_theme.dart`, already imported in Step 3a of Task 7.

**3c.** Wrap the returned `Scaffold` in the outer `Obx` with `PopScope`:

```dart
        return PopScope(
          canPop: !controller.isReorderDirty.value,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (await _confirmDiscard()) Get.back();
          },
          child: Scaffold(
            body: NestedScrollView(
              // … unchanged …
            ),
          ),
        );
```

**3d.** Route the modal Close button through the same confirm — replace `onPressed: Get.back` in `extraActions`:

```dart
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Close',
                          onPressed: () async {
                            if (await _confirmDiscard()) Get.back();
                          },
                        ),
```

**3e.** In `lib/app/modules/home/home_controller.dart`, in `_openItemDetailSheet`, register `WarehouseProvider` (the modal path bypasses `ItemFormBinding`) and disable dragging:

```dart
  void _openItemDetailSheet(String itemCode, {String? batchNo}) {
    Get.put(ItemTabController());
    Get.put(ItemFormController())..loadItem(itemCode, batchNo: batchNo);
    // The modal path bypasses ItemFormBinding; the Re-order tab's warehouse
    // pickers need this.
    if (!Get.isRegistered<WarehouseProvider>()) {
      Get.put(WarehouseProvider());
    }
    barcodeController.clear();

    Get.bottomSheet(
      FractionallySizedBox(
        heightFactor: 0.9,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: const ItemFormScreen(),
        ),
      ),
      isScrollControlled: true,
      // Drag-dismiss calls Navigator.pop directly, which PopScope cannot
      // intercept, so unsaved re-order rules could vanish with a swipe.
      // enableDrag is fixed at open time and cannot track dirty state, so it
      // is off; the Close button (guarded by _confirmDiscard) is the exit.
      enableDrag: false,
    ).then((_) {
      Get.delete<ItemTabController>(force: true);
      Get.delete<ItemFormController>(force: true);
    });
  }
```

with the import:

```dart
import 'package:multimax/app/data/providers/warehouse_provider.dart';
```

- [ ] **Step 4: Run the tests**

Run: `flutter analyze lib/app/modules/item/ lib/app/modules/home/home_controller.dart`
Expected: `No issues found!`

Run: `flutter test test/widget/reorder_tab_test.dart`
Expected: PASS — 1 test.

Run: `flutter test test/unit/item_form_reorder_controller_test.dart`
Expected: PASS (unchanged).

- [ ] **Step 5: Verify the whole suite**

Run: `flutter test`
Expected: PASS, except the 24 pre-existing failures recorded in the project baseline (952 passing). **Compare against that baseline — do not treat pre-existing failures as regressions, and do not "fix" them here.** If the pass count dropped or a new file fails, that is a regression from this work.

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/item/form/item_form_screen.dart \
        lib/app/modules/home/home_controller.dart \
        test/widget/reorder_tab_test.dart
git commit -m "feat(item): guard unsaved re-order rules against dismissal

PopScope covers the route and system back. The item bottom sheet loses
drag-dismiss because Get.bottomSheet fixes enableDrag at open time and a drag
calls Navigator.pop directly, which PopScope cannot intercept; the Close
button routes through the same confirm.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Version bump

**Files:**
- Modify: `pubspec.yaml:5`

`feat:` — a new module surface and flow → **MINOR**, per CLAUDE.md. Do not default to PATCH. No backend change, no custom field, no server script is required, so this is not MAJOR.

- [ ] **Step 1: Confirm the classification**

Run: `dart run tool/bump_version.dart`
Expected: proposes `2.12.0+51`.

If it proposes a PATCH, override it — the script is an aid, not an authority, and is known to misclassify. The diff adds a new editable flow, which is a feature.

- [ ] **Step 2: Apply the bump**

In `pubspec.yaml`, line 5:

```yaml
version: 2.12.0+51
```

- [ ] **Step 3: Verify**

Run: `grep '^version:' pubspec.yaml`
Expected: `version: 2.12.0+51`

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml
git commit -m "chore(release): 2.12.0+51

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Verification

`flutter analyze` proving clean says nothing about whether the spinner repaints or the banner shows — CLAUDE.md is explicit about this. Before calling the work done, exercise on-device or in a widget test:

1. Open a stock Item → **Re-order** tab. Existing rules render.
2. With `Stock Settings.auto_indent` off, the warning banner shows. (If the logged-in user is not a System Manager the Stock Settings read 403s and the banner is correctly absent — verify as SM.)
3. **+ Add rule** → sheet → pick a leaf warehouse, set level 100 / qty 50, type Purchase → Done. The save bar appears.
4. Save → success snackbar → rows reload with `warehouse_group` populated to the warehouse.
5. Pick a "Check in (group)" that is *not* an ancestor of "Request for" → save → the server's descendant message surfaces verbatim, not "Save failed".
6. Add two rows with the same warehouse and the same type → save blocked client-side with "Row #2: A reorder entry already exists…".
7. Add the same warehouse with *different* types → saves fine.
8. Set a level with no qty → blocked with "Row #1: Please set reorder quantity".
9. Edit a rule, press back → discard confirm. Cancel → still there. Revert the edit manually → save bar disappears (dirty is a diff).
10. Open a non-stock item → Re-order tab shows the empty state.
11. Sign in as a user without `Item:write` → rules render, no Add/Edit/Delete/Save.
12. Toggle dark mode on the Re-order tab → banner, cards and sheet all readable.

## Out of scope

Do not implement these; they are settled decisions recorded in the spec.

- Enabling `Stock Settings.auto_indent`. The app reports it, never changes it.
- Narrowing "Request for" to descendants of the chosen group. v15's narrowing branch is dead code; matching v15 means not narrowing.
- Rendering the template's inherited rows on a variant.
- Making any other Item field editable — the other four tabs stay read-only.
- Viewing or managing the Material Requests the engine generates.
