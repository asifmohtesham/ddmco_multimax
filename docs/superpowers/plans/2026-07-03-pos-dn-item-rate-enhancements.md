# POS & DN Item Rate — Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the six smoke-test enhancements to the POS & DN Item Rate report — drop the server Total row, add item image + tap-to-zoom, tap-card→Item detail, scrollbar, bottom safe-area, and an end-of-list totals footer — plus long-press-copy of the customer code, using a shared image widget extracted from Stock Balance.

**Architecture:** Reuse-first. Extract Stock Balance's private thumbnail + zoom into a shared `global_widgets/item_image.dart` (behaviour-preserving), enrich report rows with images client-side via the existing `getItemImages` API, and add pure static helpers (`attachImages`, `sumTotals`) to the controller so logic stays unit-testable. UI changes are confined to the tile and screen. Three of the six items become standing CLAUDE.md conventions.

**Tech Stack:** Flutter, GetX, `cached_network_image`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-07-03-pos-dn-item-rate-enhancements-design.md`

## Global Constraints

- Report status strings, exact: `New`, `Already mapped`, `No delivery line`, `No code`. The Total row (`status` NOT in this set) must be dropped in `parseRows`.
- Image URL contract (mirror `stock_balance_controller.attachItemImages`): trim one trailing `/` off base; keep values starting with `http` as-is; rows with no image for their code are left unchanged; the absolute URL is written to row key `item_image`.
- Item form navigation: `Get.toNamed(AppRoutes.ITEM_FORM, arguments: {'itemCode': itemCode})` — key is `itemCode` (NOT `name`/`mode`). Only when `item_code` is non-empty.
- End-of-list totals are computed from **filtered** rows; sum quantity columns (`upload_qty`, `dn_qty`) only — never `upload_rate`.
- Status accent colours already use the AppColors x700/x300 ramp via `posDnStatusAccent` — reuse it, do not hardcode.
- Scrollbar uses a single `ScrollController` shared between the `Scrollbar` and the `CustomScrollView`.
- Bottom inset: `MediaQuery.of(context).padding.bottom`, applied to the trailing footer so the last card clears the system nav bar.
- Behaviour-preserving extraction: Stock Balance must render and zoom images exactly as before; its existing tests must stay green.
- All commands run from repo root `C:\Users\asifm\StudioProjects\ddmco_multimax`; test with `flutter test <path>`, lint with `flutter analyze <path>`.
- `toNum` / `formatQty` live in `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart` and are already imported by the tile — reuse them.

---

### Task 1: Extract shared `ItemThumbnail` + `showItemImagePreview`

Move Stock Balance's private `_ItemThumb` and `showItemImagePreview` into a shared widget file and re-point Stock Balance at it. Behaviour-preserving.

**Files:**
- Create: `lib/app/modules/global_widgets/item_image.dart`
- Modify: `lib/app/modules/stock/reports/stock_balance/stock_balance_screen.dart` (delete `_ItemThumb` class + `showItemImagePreview` function ~lines 1098-1250; replace the `_ItemThumb(...)` usage ~line 778; add import; remove now-unused `cached_network_image` import at line 3)
- Test: `test/widget/item_image_test.dart` (create)

**Interfaces:**
- Produces:
  - `class ItemThumbnail extends StatelessWidget` — `ItemThumbnail({Key? key, required String? imageUrl, required String itemCode, required String itemName, double size = 46})`. Renders a rounded `CachedNetworkImage`, falling back to 2-letter initials; when `imageUrl` is non-empty, tapping opens `showItemImagePreview`.
  - `void showItemImagePreview(BuildContext context, String url, String itemCode, String itemName)` — full-bleed dialog with `InteractiveViewer` (minScale 1, maxScale 5).

- [ ] **Step 1: Write the failing test**

Create `test/widget/item_image_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/item_image.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('shows initials fallback when imageUrl is null/empty', (tester) async {
    await tester.pumpWidget(_wrap(const ItemThumbnail(
      imageUrl: null, itemCode: '2001272', itemName: 'STRAPS T/X PRINT',
    )));
    // 'STRAPS T/X PRINT' -> words [STRAPS, T, X, PRINT] -> first two initials 'ST'
    expect(find.text('ST'), findsOneWidget);
  });

  testWidgets('falls back to item code for initials when name is blank',
      (tester) async {
    await tester.pumpWidget(_wrap(const ItemThumbnail(
      imageUrl: '', itemCode: 'AB1234', itemName: '',
    )));
    expect(find.text('AB'), findsOneWidget);
  });

  testWidgets('no zoom gesture when there is no image', (tester) async {
    await tester.pumpWidget(_wrap(const ItemThumbnail(
      imageUrl: null, itemCode: 'X', itemName: 'X',
    )));
    // With no image the thumb is not wrapped in a GestureDetector-with-onTap.
    final gestures = tester.widgetList<GestureDetector>(find.byType(GestureDetector));
    expect(gestures.where((g) => g.onTap != null), isEmpty);
  });

  testWidgets('showItemImagePreview opens a dialog with an InteractiveViewer',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_wrap(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    showItemImagePreview(ctx, 'https://example.com/x.jpg', '2001272', 'STRAPS');
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('2001272 · STRAPS'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/item_image_test.dart`
Expected: FAIL — `item_image.dart` does not exist / `ItemThumbnail` undefined.

- [ ] **Step 3: Create the shared widget file**

Create `lib/app/modules/global_widgets/item_image.dart` (copied verbatim from Stock Balance's `_ItemThumb`/`showItemImagePreview`, renamed public, with a configurable `size`):

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A rounded item thumbnail. Shows the network image when [imageUrl] is
/// non-empty, otherwise a 2-letter initials fallback derived from the item
/// name (or code). Tapping an actual image opens [showItemImagePreview]
/// without leaving the current screen.
class ItemThumbnail extends StatelessWidget {
  final String? imageUrl;
  final String itemCode;
  final String itemName;
  final double size;

  const ItemThumbnail({
    super.key,
    required this.imageUrl,
    required this.itemCode,
    required this.itemName,
    this.size = 46,
  });

  String get _initials {
    final source = itemName.trim().isNotEmpty ? itemName : itemCode;
    final words = source
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '·';
    final letters = words.take(2).map((w) => w[0]).join();
    return letters.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget fallback() => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          color: cs.secondaryContainer,
          child: Text(
            _initials,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSecondaryContainer,
            ),
          ),
        );

    final url = imageUrl?.trim() ?? '';
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? fallback()
            : CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, __) => fallback(),
                errorWidget: (_, __, ___) => fallback(),
              ),
      ),
    );

    if (url.isEmpty) return thumb;
    return GestureDetector(
      onTap: () => showItemImagePreview(context, url, itemCode, itemName),
      child: thumb,
    );
  }
}

/// Shows the item image enlarged in an in-screen, dismissible dialog with
/// pinch/drag zoom. Stays on the current screen — no navigation.
void showItemImagePreview(
  BuildContext context,
  String url,
  String itemCode,
  String itemName,
) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    useSafeArea: false, // let the preview fill the whole screen
    builder: (ctx) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      clipBehavior: Clip.hardEdge,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    ),
                    errorWidget: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    itemName.isNotEmpty ? '$itemCode · $itemName' : itemCode,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
```

- [ ] **Step 4: Re-point Stock Balance at the shared widget**

In `lib/app/modules/stock/reports/stock_balance/stock_balance_screen.dart`:

1. Delete the `cached_network_image` import at line 3 (it will no longer be referenced in this file after the class/function are removed — verify with analyze in Step 6; if any other reference remains, keep it).
2. Add import (with the other `global_widgets` imports):
   ```dart
   import 'package:multimax/app/modules/global_widgets/item_image.dart';
   ```
3. Replace the `_ItemThumb(...)` usage (~line 778) with `ItemThumbnail(...)` — the constructor params are identical (`imageUrl`, `itemCode`, `itemName`), so only the type name changes:
   ```dart
                         ItemThumbnail(
   ```
   (keep the exact argument lines that follow unchanged).
4. Delete the entire `// ── Item thumbnail ──` section: the `class _ItemThumb extends StatelessWidget { ... }` and the `void showItemImagePreview(...) { ... }` function (the block spanning roughly lines 1098-1250, ending just before `// ── Ledger strip ──`).

- [ ] **Step 5: Run the new test + Stock Balance's tests**

Run: `flutter test test/widget/item_image_test.dart`
Expected: PASS (4 tests).

Run: `flutter test test/widget/stock_balance_tile_test.dart test/widget/stock_balance_screen_test.dart` (any Stock Balance widget test files that exist — discover with `ls test/widget | grep stock_balance`)
Expected: PASS (unchanged from before — behaviour preserved).

- [ ] **Step 6: Analyze both files**

Run: `flutter analyze lib/app/modules/global_widgets/item_image.dart lib/app/modules/stock/reports/stock_balance/stock_balance_screen.dart`
Expected: no new warnings/errors (an "unused import" on `cached_network_image` means Step 4.1 was missed — remove it; if analyze says it IS still used, revert the deletion).

- [ ] **Step 7: Commit**

```bash
git add lib/app/modules/global_widgets/item_image.dart lib/app/modules/stock/reports/stock_balance/stock_balance_screen.dart test/widget/item_image_test.dart
git commit -m "refactor(widgets): extract shared ItemThumbnail + image zoom from Stock Balance"
```

---

### Task 2: Controller — drop Total row, image enrichment, totals

Add the total-row drop to `parseRows`, a pure `attachImages` helper, a pure `sumTotals` helper, and wire image enrichment into `runReport`.

**Files:**
- Modify: `lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart`
- Test: `test/unit/pos_dn_item_rate_controller_test.dart` (extend existing)

**Interfaces:**
- Consumes: `ApiProvider.getItemImages(List<String>) -> Future<Map<String,String>>`, `ApiProvider.baseUrl` (String getter) — both already exist.
- Produces:
  - `parseRows` now drops rows whose `status` ∉ the four known statuses.
  - `static List<Map<String,dynamic>> attachImages(List<Map<String,dynamic>> rows, Map<String,String> imgMap, String baseUrl)`
  - `static Map<String,num> sumTotals(List<Map<String,dynamic>> rows)` → keys `count`, `pos_qty`, `dn_qty`.

- [ ] **Step 1: Write the failing tests**

Append to `test/unit/pos_dn_item_rate_controller_test.dart` (inside the existing `main()`, add new groups; keep existing tests):

```dart
  group('parseRows drops the server total row', () {
    test('keeps only the four known statuses', () {
      final rows = PosDnItemRateController.parseRows(const {
        'columns': [
          {'fieldname': 'status'},
          {'fieldname': 'ref_code'},
        ],
        'result': [
          {'status': 'New', 'ref_code': '1'},
          {'status': 'No code', 'ref_code': null},
          {'status': 'Total', 'ref_code': null},          // add_total_row
          {'status': '', 'ref_code': null},               // stray blank
        ],
      });
      expect(rows.length, 2);
      expect(rows.map((r) => r['status']), ['New', 'No code']);
    });
  });

  group('attachImages', () {
    const rows = [
      {'item_code': 'A'},
      {'item_code': 'B'},
      {'item_code': ''},
    ];

    test('prefixes relative paths with base (one trailing slash trimmed)', () {
      final out = PosDnItemRateController.attachImages(
        rows, {'A': '/files/a.jpg'}, 'https://erp.example.com/');
      expect(out[0]['item_image'], 'https://erp.example.com/files/a.jpg');
    });

    test('keeps http URLs as-is and leaves un-imaged rows unchanged', () {
      final out = PosDnItemRateController.attachImages(
        rows, {'A': 'https://cdn/x.png'}, 'https://erp.example.com');
      expect(out[0]['item_image'], 'https://cdn/x.png');
      expect(out[1].containsKey('item_image'), isFalse);
      expect(out[2].containsKey('item_image'), isFalse);
    });

    test('empty imgMap returns rows unchanged', () {
      final out = PosDnItemRateController.attachImages(rows, {}, 'https://x');
      expect(out, same(rows));
    });
  });

  group('sumTotals', () {
    test('sums qty columns and counts rows, ignoring rate and null/dash', () {
      final t = PosDnItemRateController.sumTotals(const [
        {'upload_qty': 84, 'upload_rate': 140, 'dn_qty': 12},
        {'upload_qty': 12, 'upload_rate': 360, 'dn_qty': 12},
        {'upload_qty': null, 'upload_rate': '—', 'dn_qty': '—'},
      ]);
      expect(t['count'], 3);
      expect(t['pos_qty'], 96);
      expect(t['dn_qty'], 24);
      expect(t.containsKey('pos_rate'), isFalse); // rate is never summed
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/pos_dn_item_rate_controller_test.dart`
Expected: FAIL — `attachImages` / `sumTotals` undefined; the total-row test fails (current `parseRows` keeps all 4 rows).

- [ ] **Step 3: Update `parseRows`**

In `pos_dn_item_rate_controller.dart`, `parseRows` currently builds `rows` and returns it. Add a known-status filter before returning. Replace the final `return rows;` of `parseRows` with:

```dart
    const known = {statusNew, statusMapped, statusNoDelivery, statusNoCode};
    return rows
        .where((r) => known.contains((r['status'] ?? '').toString()))
        .toList();
```

(If `parseRows` is `static`, `statusNew` etc. are accessible as they are static consts on the same class — reference them bare as shown.)

- [ ] **Step 4: Add `attachImages` and `sumTotals` statics**

Add these two static methods to the class (near the other statics, e.g. after `defaultFromDate`):

```dart
  /// Returns [rows] with an absolute `item_image` URL set from [imgMap]
  /// (keyed by item code). Relative frappe paths are prefixed with [baseUrl]
  /// (one trailing slash trimmed); `http…` values are kept as-is; rows whose
  /// code has no image are left untouched. Mirrors Stock Balance.
  static List<Map<String, dynamic>> attachImages(
    List<Map<String, dynamic>> rows,
    Map<String, String> imgMap,
    String baseUrl,
  ) {
    if (imgMap.isEmpty) return rows;
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return rows.map((r) {
      final code = (r['item_code'] ?? '').toString();
      final img = imgMap[code];
      if (img == null || img.isEmpty) return r;
      final url = img.startsWith('http') ? img : '$base$img';
      return {...r, 'item_image': url};
    }).toList();
  }

  /// Row count + summed quantity columns over [rows]. Rate is intentionally
  /// NOT summed (summing rates across items is meaningless). Non-numeric /
  /// null qty values contribute 0.
  static Map<String, num> sumTotals(List<Map<String, dynamic>> rows) {
    num pos = 0, dn = 0;
    for (final r in rows) {
      pos += _numOrZero(r['upload_qty']);
      dn += _numOrZero(r['dn_qty']);
    }
    return {'count': rows.length, 'pos_qty': pos, 'dn_qty': dn};
  }

  static num _numOrZero(dynamic v) =>
      v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);
```

- [ ] **Step 5: Wire enrichment into `runReport`**

In `runReport`, replace the success block:

```dart
      if (resp.statusCode == 200) {
        reportRows.assignAll(parseRows(resp.data['message']));
        hasRun.value = true;
        errorMessage.value = null;
      }
```

with (enrich with images after parsing; enrichment failure must not fail the report):

```dart
      if (resp.statusCode == 200) {
        var rows = parseRows(resp.data['message']);
        final codes = <String>{
          for (final r in rows)
            if ((r['item_code'] ?? '').toString().isNotEmpty)
              r['item_code'].toString(),
        }.toList();
        if (codes.isNotEmpty) {
          try {
            final imgMap = await _api.getItemImages(codes);
            rows = attachImages(rows, imgMap, _api.baseUrl);
          } catch (_) {
            // Image enrichment is best-effort; rows still render without it.
          }
        }
        reportRows.assignAll(rows);
        hasRun.value = true;
        errorMessage.value = null;
      }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/unit/pos_dn_item_rate_controller_test.dart`
Expected: PASS (existing tests + the new total-row, attachImages, sumTotals groups).

- [ ] **Step 7: Analyze**

Run: `flutter analyze lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart`
Expected: no new issues.

- [ ] **Step 8: Commit**

```bash
git add lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart test/unit/pos_dn_item_rate_controller_test.dart
git commit -m "feat(pos-dn-rate): drop server total row, enrich images, sum totals"
```

---

### Task 3: Tile — thumbnail, tap-to-Item, long-press-copy

Add the leading thumbnail, a whole-card tap → Item detail (only when `item_code` present), and long-press-copy of the customer code.

**Files:**
- Modify: `lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_tile.dart`
- Test: `test/widget/pos_dn_item_rate_tile_test.dart` (extend existing)

**Interfaces:**
- Consumes: `ItemThumbnail` from `global_widgets/item_image.dart` (Task 1); rows may now carry `item_image` (Task 2); `AppRoutes.ITEM_FORM`.
- Produces: no new public API — tile behaviour changes only.

- [ ] **Step 1: Write the failing tests**

Append to `test/widget/pos_dn_item_rate_tile_test.dart` (keep existing tests; add these). Note: card-tap navigation is asserted via GetX route change, so these use `GetMaterialApp` with a stub `ITEM_FORM` page.

```dart
  testWidgets('renders a thumbnail (initials) for a New row', (tester) async {
    await tester.pumpWidget(_wrap(_newRow));
    // ItemThumbnail present; initials from 'STRAPS T/X PRINT 40mm' -> 'ST'
    expect(find.byType(ItemThumbnail), findsOneWidget);
  });

  testWidgets('tapping the card navigates to ITEM_FORM when item_code present',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: '/home',
      getPages: [
        GetPage(name: '/home', page: () => Scaffold(
          body: Center(child: SizedBox(width: 380,
              child: PosDnItemRateTile(row: _newRow))))),
        GetPage(name: AppRoutes.ITEM_FORM,
            page: () => const Scaffold(body: Text('ITEM FORM STUB'))),
      ],
    ));
    // Tap the card body (avoid the thumbnail and voucher chips).
    await tester.tapAt(tester.getCenter(find.text('DN')));
    await tester.pumpAndSettle();
    expect(find.text('ITEM FORM STUB'), findsOneWidget);
    expect(Get.arguments, {'itemCode': '2001272'});
  });

  testWidgets('card is NOT tappable for a No code row (no item_code)',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: '/home',
      getPages: [
        GetPage(name: '/home', page: () => Scaffold(
          body: Center(child: SizedBox(width: 380, child: PosDnItemRateTile(row: const {
            'status': 'No code', 'upload_item': 'CARD CASE',
            'pos_upload': 'KA-1', 'idx': 1,
          }))))),
        GetPage(name: AppRoutes.ITEM_FORM,
            page: () => const Scaffold(body: Text('ITEM FORM STUB'))),
      ],
    ));
    await tester.tapAt(tester.getCenter(find.text('CARD CASE')));
    await tester.pumpAndSettle();
    expect(find.text('ITEM FORM STUB'), findsNothing);
  });

  testWidgets('long-pressing the customer code copies it to the clipboard',
      (tester) async {
    final copied = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add(call);
      return null;
    });
    await tester.pumpWidget(_wrap(_newRow));
    await tester.longPress(find.text('5067101'));
    await tester.pump();
    expect(copied, isNotEmpty);
    expect(copied.first.arguments['text'], '5067101');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
```

Add the required imports to the top of the test file if absent:

```dart
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/item_image.dart';
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget/pos_dn_item_rate_tile_test.dart`
Expected: FAIL — no `ItemThumbnail` in the tile, no card `onTap`, no long-press copy.

- [ ] **Step 3: Add imports to the tile**

In `pos_dn_item_rate_tile.dart`, add:

```dart
import 'package:flutter/services.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/item_image.dart';
```

(`package:get/get.dart` and `app_routes.dart` are already imported.)

- [ ] **Step 4: Wrap the card body in an InkWell and add the thumbnail + copy**

In `PosDnItemRateTile.build`, after the existing local variable block, add:

```dart
    final itemImage = (row['item_image'] ?? '').toString();
    final canOpenItem = itemCode.isNotEmpty;
```

Change the `return Card(...)` so the `Padding` child is wrapped in an `InkWell` that navigates only when `canOpenItem`, and add the thumbnail to the hero row. Replace the whole `return Card( ... );` with:

```dart
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      color: cs.surfaceContainerLowest,
      child: InkWell(
        onTap: canOpenItem
            ? () => Get.toNamed(AppRoutes.ITEM_FORM,
                arguments: {'itemCode': itemCode})
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero: thumbnail + customer code + status ─────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ItemThumbnail(
                    imageUrl: itemImage.isEmpty ? null : itemImage,
                    itemCode: itemCode,
                    itemName: dnItem.isNotEmpty ? dnItem : uploadItem,
                    size: 40,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onLongPress: refCode.isEmpty
                                    ? null
                                    : () {
                                        Clipboard.setData(
                                            ClipboardData(text: refCode));
                                        GlobalSnackbar.success(
                                          title: 'Copied',
                                          message: 'Customer code $refCode',
                                        );
                                      },
                                child: Text(
                                  refCode.isEmpty ? '—' : refCode,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'ShureTechMono',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            PosDnStatusPill(status: status),
                          ],
                        ),
                        if (itemCode.isNotEmpty || itemGroup.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (itemCode.isNotEmpty)
                                Text(itemCode,
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: cs.onSurfaceVariant)),
                              if (itemCode.isNotEmpty && itemGroup.isNotEmpty)
                                Text(' · ',
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: cs.onSurfaceVariant)),
                              if (itemGroup.isNotEmpty)
                                Text(itemGroup,
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // ── Item names: the naming gap is the point — show both ──────
              if (dnItem.isNotEmpty) _NameRow(label: 'DN', value: dnItem),
              if (uploadItem.isNotEmpty) _NameRow(label: 'POS', value: uploadItem),
              if (customerLine.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (customer.isNotEmpty)
                      Text(customer,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    if (customer.isNotEmpty && custGroup.isNotEmpty)
                      Text(' · ',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    if (custGroup.isNotEmpty)
                      Text(custGroup,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
              const SizedBox(height: 8),

              // ── Numbers ──────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  StatCell(label: 'POS Qty', value: formatQty(toNum(row['upload_qty']))),
                  StatCell(label: 'POS Rate', value: formatQty(toNum(row['upload_rate']))),
                  StatCell(label: 'DN Qty', value: formatQty(toNum(row['dn_qty']))),
                ],
              ),

              // ── Voucher links ────────────────────────────────────────────
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (dnName.isNotEmpty)
                    _VoucherChip(
                      icon: Icons.local_shipping_outlined,
                      label: dnName,
                      onTap: () => Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM,
                          arguments: {'name': dnName, 'mode': 'edit'}),
                    ),
                  if (posUpload.isNotEmpty)
                    _VoucherChip(
                      icon: Icons.cloud_upload_outlined,
                      label: idx.isEmpty ? posUpload : '$posUpload · #$idx',
                      onTap: () => Get.toNamed(AppRoutes.POS_UPLOAD_FORM,
                          arguments: {'name': posUpload, 'mode': 'edit'}),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
```

Note: `GlobalSnackbar.success({required String title, required String message})` exists (verified) — use it exactly as shown. The copy behaviour (`Clipboard.setData`) is what the test asserts; the snackbar is confirmation only.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/widget/pos_dn_item_rate_tile_test.dart`
Expected: PASS (existing 6 + 4 new).

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_tile.dart`
Expected: no new issues.

- [ ] **Step 7: Commit**

```bash
git add lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_tile.dart test/widget/pos_dn_item_rate_tile_test.dart
git commit -m "feat(pos-dn-rate): tile thumbnail, tap-to-item, long-press-copy code"
```

---

### Task 4: Screen — scrollbar, bottom inset, end-of-list totals footer

Wrap the scroll view in a `Scrollbar`, pad the last card past the nav bar, and add the end-of-list totals footer.

**Files:**
- Modify: `lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_screen.dart`
- Test: `test/widget/pos_dn_item_rate_screen_test.dart` (extend existing)

Also add the spec's top `ResultCountPill` ("N rows"), reusing the shared widget.

**Interfaces:**
- Consumes: `PosDnItemRateController.sumTotals` + `filteredRows` (Task 2), existing status constants, `ResultCountPill` from `lib/app/modules/global_widgets/result_count_pill.dart` (ctor: `ResultCountPill({required int count, required bool hasMore, required bool hasActiveFilters, required String noun, required IconData icon, String? pluralNoun})`).
- Produces: `PosDnItemRateScreen` becomes a `StatefulWidget` (to own the shared `ScrollController`).

- [ ] **Step 1: Write the failing tests**

Append to `test/widget/pos_dn_item_rate_screen_test.dart` (keep existing; reuse the `fourRows()` helper already defined there). These need a taller surface so the footer is built (lazy slivers) — follow the existing pattern of setting `tester.view.physicalSize`.

```dart
  testWidgets('shows an end-of-list footer with summed quantities',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = Get.find<PosDnItemRateController>();
    c.reportRows.assignAll([
      {'status': 'New', 'ref_code': '1', 'item_code': 'A',
       'upload_item': 'X', 'upload_qty': 84, 'dn_qty': 12, 'pos_upload': 'K', 'idx': 1},
      {'status': 'New', 'ref_code': '2', 'item_code': 'B',
       'upload_item': 'Y', 'upload_qty': 12, 'dn_qty': 12, 'pos_upload': 'K', 'idx': 2},
    ]);
    c.hasRun.value = true;
    await tester.pumpWidget(const GetMaterialApp(home: PosDnItemRateScreen()));
    await tester.pump();

    expect(find.textContaining('End of list'), findsOneWidget);
    // POS Qty total 96, DN Qty total 24 appear in the footer.
    expect(find.textContaining('96'), findsWidgets);
    expect(find.textContaining('24'), findsWidgets);
  });

  testWidgets('wraps the scroll view in a Scrollbar', (tester) async {
    final c = Get.find<PosDnItemRateController>();
    c.reportRows.assignAll(fourRows());
    c.hasRun.value = true;
    await tester.pumpWidget(const GetMaterialApp(home: PosDnItemRateScreen()));
    await tester.pump();
    expect(find.byType(Scrollbar), findsOneWidget);
  });

  testWidgets('shows a ResultCountPill with the filtered row count',
      (tester) async {
    final c = Get.find<PosDnItemRateController>();
    c.reportRows.assignAll(fourRows()); // 4 rows
    c.hasRun.value = true;
    await tester.pumpWidget(const GetMaterialApp(home: PosDnItemRateScreen()));
    await tester.pump();
    expect(find.byType(ResultCountPill), findsOneWidget);
    expect(find.textContaining('4'), findsWidgets);
  });
```

Add the `ResultCountPill` import to the test file's imports if absent:

```dart
import 'package:multimax/app/modules/global_widgets/result_count_pill.dart';
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget/pos_dn_item_rate_screen_test.dart`
Expected: FAIL — no `Scrollbar`, no `ResultCountPill`, no "End of list" footer.

- [ ] **Step 3: Convert the screen to Stateful and add the ScrollController**

Add these imports to `pos_dn_item_rate_screen.dart`:

```dart
import 'package:multimax/app/modules/global_widgets/result_count_pill.dart';
```

Replace the class declaration and `build` opening. Change:

```dart
class PosDnItemRateScreen extends GetView<PosDnItemRateController> {
  const PosDnItemRateScreen({super.key});
```

to:

```dart
class PosDnItemRateScreen extends StatefulWidget {
  const PosDnItemRateScreen({super.key});

  @override
  State<PosDnItemRateScreen> createState() => _PosDnItemRateScreenState();
}

class _PosDnItemRateScreenState extends State<PosDnItemRateScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  PosDnItemRateController get controller => Get.find<PosDnItemRateController>();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }
```

The `_buildFilterChips` method stays as-is (it already takes `BuildContext`). It must move inside the State class — keep it where it is in the file, just ensure it's a method of `_PosDnItemRateScreenState`.

- [ ] **Step 4: Wrap the CustomScrollView in a Scrollbar, add bottom inset + footer**

In `build`, wrap the `CustomScrollView` with a `Scrollbar` and give both the shared controller. Change:

```dart
        return RefreshIndicator(
          onRefresh: controller.runReport,
          color: cs.primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
```

to:

```dart
        final bottomInset = MediaQuery.of(context).padding.bottom;
        return RefreshIndicator(
          onRefresh: controller.runReport,
          color: cs.primary,
          child: Scrollbar(
            controller: _scrollCtrl,
            child: CustomScrollView(
              controller: _scrollCtrl,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
```

Then close the extra `Scrollbar(` wrapper: the existing `slivers: [ ... ],` list closes with `],` then `),` for the CustomScrollView — add one more `),` for the Scrollbar. (Match the added indentation; `flutter analyze` will catch a bracket mismatch.)

Insert the `ResultCountPill` as a sliver right after the status-chip-row sliver and before the body `if (controller.isRunning.value)` chain (only when there are rows to count):

```dart
              // ── Result count pill ──────────────────────────────────────
              if (!controller.isRunning.value && controller.reportRows.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: ResultCountPill(
                      count: rows.length,
                      hasMore: false,
                      hasActiveFilters:
                          controller.statusFilter.value != 'ALL' ||
                          controller.searchQuery.value.trim().isNotEmpty ||
                          controller.activeFilters.isNotEmpty,
                      noun: 'row',
                      icon: Icons.receipt_long_outlined,
                    ),
                  ),
                ),
```

In the final `else` branch that renders the list, replace:

```dart
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: PosDnItemRateTile(row: rows[index]),
                      ),
                      childCount: rows.length,
                    ),
                  ),
                ),
```

with (list + end-of-list footer sliver carrying the bottom inset):

```dart
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: PosDnItemRateTile(row: rows[index]),
                      ),
                      childCount: rows.length,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12, 4, 12, 16 + bottomInset),
                    child: _EndOfListFooter(
                      totals: PosDnItemRateController.sumTotals(rows),
                    ),
                  ),
                ),
              ],
```

- [ ] **Step 5: Add the `_EndOfListFooter` widget**

At the bottom of the file (after `_StatusChipRow`), add:

```dart
/// End-of-list marker + totals summary (row count, summed POS/DN qty over the
/// currently-shown rows). Rate is intentionally not summed.
class _EndOfListFooter extends StatelessWidget {
  final Map<String, num> totals;
  const _EndOfListFooter({required this.totals});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final count = totals['count'] ?? 0;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: cs.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('End of list · $count row${count == 1 ? '' : 's'}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ),
            Expanded(child: Divider(color: cs.outlineVariant)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Total(label: 'Total POS Qty', value: totals['pos_qty'] ?? 0),
              _Total(label: 'Total DN Qty', value: totals['dn_qty'] ?? 0),
            ],
          ),
        ),
      ],
    );
  }
}

class _Total extends StatelessWidget {
  final String label;
  final num value;
  const _Total({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final d = value.toDouble();
    final text = d == d.roundToDouble()
        ? d.toStringAsFixed(0)
        : d.toStringAsFixed(2);
    return Column(
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: cs.onSurfaceVariant)),
        Text(text,
            style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700, fontFamily: 'ShureTechMono')),
      ],
    );
  }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/widget/pos_dn_item_rate_screen_test.dart`
Expected: PASS (existing 5 + 2 new).

- [ ] **Step 7: Analyze**

Run: `flutter analyze lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_screen.dart`
Expected: no new issues.

- [ ] **Step 8: Commit**

```bash
git add lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_screen.dart test/widget/pos_dn_item_rate_screen_test.dart
git commit -m "feat(pos-dn-rate): scrollbar, bottom safe-area, end-of-list totals footer"
```

---

### Task 5: Codify conventions in CLAUDE.md + full verification

Add the three standing conventions and run the whole suite.

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add the conventions subsection**

In `CLAUDE.md`, after the "Async feedback" section (before "Contrast / colour usage"), add:

```markdown
## List / report screen conventions

Any vertically-scrollable result list (list screens, report screens) MUST:

- **Scrollbar.** Wrap the `CustomScrollView`/`ListView` in a `Scrollbar` sharing
  a single `ScrollController` with the scroll view — users need a scroll
  position indicator on long result sets.
- **Clear the system nav bar.** The last item must not sit under the Android
  gesture/nav bar. Read `MediaQuery.of(context).padding.bottom` once and add it
  to the trailing padding or footer (see `delivery_note_screen` / the POS & DN
  Item Rate report).
- **End-of-list marker.** End the list with an "End of list" marker so the user
  knows they've reached the bottom. **Report** lists put a totals summary there —
  sum the quantity columns, never rate columns (summing rates is meaningless).
```

- [ ] **Step 2: Commit the doc**

```bash
git add CLAUDE.md
git commit -m "docs(claude): add list/report screen scrollbar + safe-area + end-of-list conventions"
```

- [ ] **Step 3: Run the full suite**

Run: `flutter test`
Expected: ALL pass (baseline was 706 before this round; now higher). If a pre-existing test fails, confirm it fails on the base commit too before touching it.

- [ ] **Step 4: Run analyze on the whole project**

Run: `flutter analyze`
Expected: no NEW warnings/errors vs. the pre-round baseline (pre-existing info-level lints, e.g. UPPER_CASE route constants, are fine).

- [ ] **Step 5: Report status**

Remaining (outside this plan, requires the user): on-device re-smoke — confirm the Total card is gone, thumbnails load + zoom, card tap opens the Item detail, the scrollbar shows, the last card clears the nav bar, and the end-of-list totals match.
