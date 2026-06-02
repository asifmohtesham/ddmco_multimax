# Material Request List Tile UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve the Material Request list tile to surface owner, modified time, and total quantity in the collapsed state, and add visual hierarchy to the expanded section.

**Architecture:** Three sequential changes — (1) extend the list API fetch with three new fields and add `totalQty` to the model, (2) update the collapsed tile's stats/auditStats to use those fields, (3) restructure the expanded section into visual zones and merge the footer row.

**Tech Stack:** Flutter, GetX, Dart, Frappe/ERPNext REST API

---

## File Map

| File | Change |
|------|--------|
| `lib/app/data/providers/material_request_provider.dart` | Add `owner`, `modified`, `total_qty` to list fields |
| `lib/app/data/models/material_request_model.dart` | Add `totalQty` field, parse from JSON |
| `lib/app/modules/material_request/material_request_screen.dart` | Collapsed stats + auditStats, expanded zones, merged footer |

---

## Task 1: Extend Data Layer

**Files:**
- Modify: `lib/app/data/providers/material_request_provider.dart`
- Modify: `lib/app/data/models/material_request_model.dart`

- [ ] **Step 1: Add fields to the list fetch**

Open `lib/app/data/providers/material_request_provider.dart`. Replace the `fields` list in `getMaterialRequests()`:

```dart
// BEFORE:
fields: ['name', 'transaction_date', 'schedule_date', 'status', 'docstatus', 'material_request_type']

// AFTER:
fields: [
  'name', 'transaction_date', 'schedule_date', 'status', 'docstatus',
  'material_request_type', 'owner', 'modified', 'total_qty'
]
```

- [ ] **Step 2: Add `totalQty` field to the model**

Open `lib/app/data/models/material_request_model.dart`. Add the field declaration to the class body (after `setWarehouse`):

```dart
final double totalQty;
```

Add it to the constructor (after `this.setWarehouse`):

```dart
required this.totalQty,
```

Add parsing in `fromJson` (after the `setWarehouse` line):

```dart
totalQty: double.tryParse(json['total_qty']?.toString() ?? '0') ?? 0.0,
```

The complete updated `MaterialRequest` class should look like:

```dart
class MaterialRequest {
  final String name;
  final String modified;
  final String transactionDate;
  final String scheduleDate;
  final String status;
  final int docstatus;
  final String materialRequestType;
  final String? owner;
  final String? setWarehouse;
  final double totalQty;
  final List<MaterialRequestItem> items;

  MaterialRequest({
    required this.name,
    required this.modified,
    required this.transactionDate,
    required this.scheduleDate,
    required this.status,
    required this.docstatus,
    required this.materialRequestType,
    this.owner,
    this.setWarehouse,
    required this.totalQty,
    required this.items,
  });

  factory MaterialRequest.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<MaterialRequestItem> items =
        itemsList.map((i) => MaterialRequestItem.fromJson(i)).toList();

    return MaterialRequest(
      name: json['name']?.toString() ?? 'No Name',
      modified: json['modified']?.toString() ?? '',
      transactionDate: json['transaction_date']?.toString() ?? '',
      scheduleDate: json['schedule_date']?.toString() ?? '',
      status: _getStatusFromDocstatus(
          _parseInt(json['docstatus']), json['status']?.toString()),
      docstatus: _parseInt(json['docstatus']),
      materialRequestType:
          json['material_request_type']?.toString() ?? 'Purchase',
      owner: json['owner']?.toString(),
      setWarehouse: json['set_warehouse']?.toString(),
      totalQty: double.tryParse(json['total_qty']?.toString() ?? '0') ?? 0.0,
      items: items,
    );
  }

  static String _getStatusFromDocstatus(int docstatus, String? serverStatus) {
    if (docstatus == 2) return 'Cancelled';
    if (docstatus == 0) return 'Draft';
    return serverStatus ?? 'Submitted';
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
```

- [ ] **Step 3: Analyze**

```bash
flutter analyze
```

Expected: no new errors or warnings.

- [ ] **Step 4: Commit**

```bash
git add lib/app/data/providers/material_request_provider.dart lib/app/data/models/material_request_model.dart
git commit -m "feat: add owner, modified, total_qty to material request list fetch"
```

---

## Task 2: Update Collapsed Tile

**Files:**
- Modify: `lib/app/modules/material_request/material_request_screen.dart`

- [ ] **Step 1: Add the `_abbreviateOwner` helper**

In `_MaterialRequestScreenState`, add this private method anywhere in the helpers section (e.g., after `_miniStat`):

```dart
String _abbreviateOwner(String email) {
  if (email == '—') return '—';
  return email.split('@').first;
}
```

- [ ] **Step 2: Update the `GenericDocumentCard` call**

Find the `GenericDocumentCard(` call inside the `SliverList` builder (around line 401). Replace the `stats` list and add `auditStats`:

```dart
// BEFORE:
stats: [
  GenericDocumentCard.buildIconStat(
    context,
    Icons.assignment_outlined,
    req.materialRequestType,
  ),
  GenericDocumentCard.buildIconStat(
    context,
    Icons.access_time,
    FormattingHelper.getRelativeTime(req.transactionDate),
  ),
  if (req.scheduleDate.isNotEmpty)
    GenericDocumentCard.buildIconStat(
      context,
      Icons.event_outlined,
      'Due ${FormattingHelper.getRelativeTime(req.scheduleDate)}',
    ),
],

// AFTER:
stats: [
  GenericDocumentCard.buildIconStat(
    context,
    Icons.inventory_2_outlined,
    '${req.totalQty.toStringAsFixed(0)} qty',
  ),
  GenericDocumentCard.buildIconStat(
    context,
    Icons.access_time,
    FormattingHelper.getRelativeTime(req.transactionDate),
  ),
  if (req.scheduleDate.isNotEmpty)
    GenericDocumentCard.buildIconStat(
      context,
      Icons.event_outlined,
      'Due ${FormattingHelper.getRelativeTime(req.scheduleDate)}',
    ),
],
auditStats: [
  GenericDocumentCard.buildIconStat(
    context,
    Icons.person_outline,
    _abbreviateOwner(req.owner ?? '—'),
  ),
  GenericDocumentCard.buildIconStat(
    context,
    Icons.edit_outlined,
    FormattingHelper.getRelativeTime(req.modified),
  ),
],
```

- [ ] **Step 3: Analyze**

```bash
flutter analyze
```

Expected: no errors.

- [ ] **Step 4: Visual check**

Run the app on a device:

```bash
flutter run -d <device_id>
```

Navigate to Material Requests. Verify the collapsed tile shows:
- `📦 120 qty` (or actual value) in place of the old type stat
- A muted second row: `👤 asif · ✏️ 4mo ago`
- The "Material Issue" type stat is gone

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/material_request/material_request_screen.dart
git commit -m "feat: show total qty, owner, and modified time in collapsed material request tile"
```

---

## Task 3: Polish Expanded Section

**Files:**
- Modify: `lib/app/modules/material_request/material_request_screen.dart`

- [ ] **Step 1: Wrap dates row in tinted container (Zone 2)**

In `_buildExpandedContent`, find the dates `Row(crossAxisAlignment: CrossAxisAlignment.start, ...)` that contains the two `_infoCell` calls. Replace the bare `Row` with a `Container`-wrapped version:

```dart
// BEFORE:
Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Expanded(
      child: _infoCell(
        context,
        label: 'TRANSACTION DATE',
        value: detailed.transactionDate,
        icon: Icons.calendar_today_outlined,
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: _infoCell(
        context,
        label: 'REQUIRED BY',
        value: detailed.scheduleDate.isNotEmpty
            ? detailed.scheduleDate
            : '—',
        icon: Icons.event_outlined,
        valueColor: colorScheme.primary,
        alignRight: true,
      ),
    ),
  ],
),

// AFTER:
Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  decoration: BoxDecoration(
    color: colorScheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(8),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: _infoCell(
          context,
          label: 'TRANSACTION DATE',
          value: detailed.transactionDate,
          icon: Icons.calendar_today_outlined,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _infoCell(
          context,
          label: 'REQUIRED BY',
          value: detailed.scheduleDate.isNotEmpty
              ? detailed.scheduleDate
              : '—',
          icon: Icons.event_outlined,
          valueColor: colorScheme.primary,
          alignRight: true,
        ),
      ),
    ],
  ),
),
```

- [ ] **Step 2: Add fulfillment progress bar to `_buildItemsSummary`**

Find the `_buildItemsSummary` method. Add `orderedQty` calculation and the progress bar after the mini-stats `Row`:

```dart
Widget _buildItemsSummary(BuildContext context, MaterialRequest detailed) {
  final totalQty = detailed.items.fold(0.0, (sum, i) => sum + i.qty);
  final orderedQty = detailed.items.fold(0.0, (sum, i) => sum + i.orderedQty);
  final fulfilledCount =
      detailed.items.where((i) => i.orderedQty >= i.qty).length;
  final colorScheme = Theme.of(context).colorScheme;

  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _miniStat(context, '${detailed.items.length}', 'Lines'),
            const SizedBox(width: 16),
            _miniStat(context, totalQty.toStringAsFixed(0), 'Total Qty'),
            const SizedBox(width: 16),
            _miniStat(
              context,
              '$fulfilledCount',
              'Ordered',
              color: fulfilledCount == detailed.items.length
                  ? Colors.green
                  : colorScheme.primary,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: totalQty > 0
                ? (orderedQty / totalQty).clamp(0.0, 1.0)
                : 0.0,
            minHeight: 4,
            backgroundColor: colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              orderedQty >= totalQty ? Colors.green : colorScheme.primary,
            ),
          ),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 3: Merge the footer into a single row**

In `_buildExpandedContent`, find the two-row footer block — the owner `Row` followed by `const SizedBox(height: 16)` and the action buttons `Row`. Replace both rows (and the `SizedBox` between them) with a single merged row:

```dart
// REMOVE these (the existing owner row, spacer, and action row):
//   Row(children: [Icon(person_outline)...Text(owner)...Text(modified)...])
//   const SizedBox(height: 16),
//   Row(mainAxisAlignment: MainAxisAlignment.end, children: [...buttons...])

// REPLACE WITH:
Row(
  children: [
    Icon(Icons.person_outline,
        size: 14, color: colorScheme.onSurfaceVariant),
    const SizedBox(width: 6),
    Expanded(
      child: Text(
        _abbreviateOwner(detailed.owner ?? '—'),
        style: theme.textTheme.bodySmall
            ?.copyWith(color: colorScheme.onSurfaceVariant),
        overflow: TextOverflow.ellipsis,
      ),
    ),
    if (detailed.docstatus == 0) ...[
      RoleGuard(
        roles: controller.writeRoles.toList(),
        child: IconButton.filled(
          onPressed: () =>
              controller.deleteMaterialRequest(detailed.name),
          icon: const Icon(Icons.delete_outline),
          style: IconButton.styleFrom(
            backgroundColor: Colors.red.shade50,
            foregroundColor: Colors.red,
          ),
          tooltip: 'Delete',
        ),
      ),
      const SizedBox(width: 8),
      RoleGuard(
        roles: controller.writeRoles.toList(),
        fallback: FilledButton.tonalIcon(
          onPressed: () => Get.toNamed(
              AppRoutes.MATERIAL_REQUEST_FORM,
              arguments: {'name': detailed.name, 'mode': 'view'}),
          icon: const Icon(Icons.visibility_outlined, size: 18),
          label: const Text('View'),
        ),
        child: FilledButton.tonalIcon(
          onPressed: () => Get.toNamed(
              AppRoutes.MATERIAL_REQUEST_FORM,
              arguments: {'name': detailed.name, 'mode': 'edit'}),
          icon: const Icon(Icons.edit, size: 18),
          label: const Text('Edit'),
        ),
      ),
    ] else ...[
      FilledButton.tonalIcon(
        onPressed: () => Get.toNamed(
            AppRoutes.MATERIAL_REQUEST_FORM,
            arguments: {'name': detailed.name, 'mode': 'view'}),
        icon: const Icon(Icons.visibility_outlined, size: 18),
        label: const Text('View Details'),
      ),
    ],
  ],
),
```

- [ ] **Step 4: Analyze**

```bash
flutter analyze
```

Expected: no errors.

- [ ] **Step 5: Visual check on device**

```bash
flutter run -d <device_id>
```

Navigate to Material Requests and expand a tile. Verify:
- Dates section has a light tinted background container
- Items section shows mini-stats + a thin progress bar below them (green if fully ordered, primary color otherwise)
- Footer is a single row: owner name on the left, delete/edit buttons on the right
- The standalone "modified time" line is gone from the expanded footer

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/material_request/material_request_screen.dart
git commit -m "feat: polish material request expanded tile with date zone, progress bar, and merged footer"
```
