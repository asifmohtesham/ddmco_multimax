# ToDo Form UX + Full CRUD — Design

**Date:** 2026-07-11
**Status:** Approved (pending user spec review)
**Branch target:** `release/play-store`

## Problem

On-device smoke testing of the ToDo form (shipped in `87668a25`) surfaced three UX
defects, all visible in one screenshot of a Desk-created ToDo opened from the app:

1. **Title is the Frappe hash.** The form header shows the document `name`
   (e.g. `f4e9qhihpi`) — ToDo autonames by hash, so the title is meaningless.
2. **Description shows raw HTML.** ToDo `description` is a Text Editor field;
   Desk stores HTML (`<div class="ql-editor read-mode"><p>…</p></div>`). The
   form dumps it into a plain `TextFormField`, tags and all. The list screen
   already renders it properly with `flutter_html`; the form does not.
3. **CRUD is unreachable from most entry points.** Every navigation path except
   the list screen's Edit button (dashboard cards, global search, reference
   chips) opens the form in `view` mode, which has no way to switch to editing.
   Delete exists in `ToDoProvider.deleteTodo` but was never wired into any UI.

## Verified against Frappe v15 (`frappe/frappe`, branch `version-15`)

From `frappe/desk/doctype/todo/todo.json` and `todo.py`:

- **`title_field: description`** — Desk itself titles ToDos by description.
  Validates decision (1) below.
- **`priority` options are `High, Medium, Low`** — there is **no "Urgent"**.
  Frappe validates Select values server-side, so our current picker offering
  Urgent is a latent save-rejection bug.
- **`description` is `reqd: 1`** — saving an empty description fails with a
  server MandatoryError; the form must block this client-side.
- **`status` options `Open, Closed, Cancelled`** — matches our picker. The
  `date` field's v15 label is **"Due Date"**.
- **Delete permission:** role "All" carries delete on ToDo; `has_permission` /
  `get_permission_query_conditions` further restrict non-permissive-role users
  to their own (`allocated_to` / `assigned_by`) docs. Gating the app's Delete
  button on the existing `ToDo:write` permission entry is a fair client-side
  approximation; the server stays authoritative and per-doc failures surface
  as error snackbars.
- **Delete side effect:** `on_trash` → `update_in_reference()` removes the
  assignment from the referenced document's `_assign` field. Deleting a
  reference-linked ToDo un-assigns it in ERPNext — the confirm dialog must say
  so when a reference is present. Close/cancel sync `_assign` the same way via
  `on_update` (no app change needed; server handles it).

## Decisions (user-approved)

1. **Header title = first line of the description**, flattened to plain text —
   same treatment the list and dashboard cards already use. Fallback "ToDo"
   when the description is empty; "New ToDo" in new mode. The hash disappears
   from the UI. Computed from the fetched model, not live from the text field.
2. **Description: render + plain-text edit.** View mode renders the HTML;
   edit mode edits stripped plain text; saving replaces any Desk formatting
   with plain text. Accepted trade-off for an ops app.
3. **CRUD scope: in-place Edit from view mode + Delete in the form header.**
   No list-card delete.

## Design

### 1. Shared HTML→text helpers — new `lib/app/core/utils/html_text.dart`

The dashboard card (`dashboard_todo_card.dart`) already has a private
`todoPlainText()` flattener. Move that logic into the shared util and expose
two functions:

- `String htmlToSingleLine(String html)` — existing behaviour: `<br>` and
  block-close tags → space, strip remaining tags, decode the common entities
  (`&nbsp; &amp; &lt; &gt; &#39; &quot;`), collapse all whitespace to single
  spaces, trim. Used for titles/cards.
- `String htmlToPlainText(String html)` — multi-line variant for the edit
  field: `<br>` and `</p>|</div>|</li>|</h1-6>` → newline, strip remaining
  tags, decode the same entities, collapse 3+ consecutive newlines to 2, trim.

`dashboard_todo_card.dart` deletes its local copy and imports
`htmlToSingleLine` (update its unit tests' imports accordingly).

### 2. Form header title (`todo_form_screen.dart`)

```dart
title = mode 'new'            → 'New ToDo'
        description non-empty → htmlToSingleLine(t.description)  // full string; header ellipsizes
        otherwise             → 'ToDo'
```

`DocTypeFormHeader` already shows the `ToDo` doctype label and status pill;
only the `title` argument changes.

### 3. Description field

- **View mode:** replace the read-only `TextFormField` with a `flutter_html`
  `Html(data: t.description)` block inside the Task `DocSectionCard`, styled
  `onSurface` (same pattern as the list card's expanded detail). When the
  description is empty, show a muted "No description" placeholder
  (`textMuted`-equivalent via `onSurfaceVariant`).
- **Edit/new mode:** keep the existing `TextFormField`. Every fetch —
  regardless of mode, so an in-place view→edit flip finds the text ready —
  populates it with `htmlToPlainText(t.description)` and takes the
  `_originalJson` dirty-tracking snapshot *after* conversion, so the
  freshly-opened form is not dirty and reverting an edit clears dirty.
- **Save:** `descriptionController.text` (plain text) is sent as-is.
- **Required-field guard:** `saveDocument()` refuses to run when
  `descriptionController.text.trim()` is empty — `SaveResult.error` +
  snackbar "Description is required" — mirroring the server's `reqd: 1`.

### 4. Priority + label corrections

- `priorityOptions` becomes `['Low', 'Medium', 'High']` (v15 set). Display
  stays tolerant: `DocPickerField` just shows whatever value the document has,
  and the list card's `urgent` colour case remains as defensive rendering for
  legacy data.
- The form's Date field label becomes **"Due Date"** (matches v15).

### 5. Edit-in-place (view → edit)

- `ToDoFormController.mode` changes from `String` to `RxString`. All reads
  become `mode.value`; the screen's outer `Obx` already reads `isEditable`,
  which now reacts to mode flips. Existing tests that assign `mode` directly
  are updated.
- New method: `void enterEditMode()` — flips `'view'` → `'edit'` when `name`
  is non-empty; no-op otherwise. Pure state flip: no busy flag needed.
- Header gains a pencil `IconButton` (tooltip "Edit"), rendered only in view
  mode and wrapped in `DocTypeGuard(doctype: 'ToDo', permType: 'write')`.
- Once in edit mode the existing Save / Close / Reopen actions light up
  (`canShowCloseAction` already keys on `mode == 'edit'`).

### 6. Delete

- **Controller:** `isDeleting = false.obs`; `deleteDocument()` shows the
  confirmation and delegates to a testable `performDelete()` (same
  confirm/core split as the list controller's `closeTodo`/`setTodoStatus`).
  - Confirm dialog: title "Delete ToDo?", destructive styling; message
    "This cannot be undone." plus, when `hasReference`,
    "This also removes the assignment from {referenceType} {referenceName}."
  - `performDelete()`: re-entrancy guard on `isDeleting`; calls
    `_provider.deleteTodo(name)`; on success → success snackbar,
    `isDirty.value = false` (so `PopScope` allows the pop), `Get.back()`.
    `DioException`/generic catch → error snackbar; `finally` clears
    `isDeleting`. No `modified` staleness check — Frappe's DELETE takes none.
- **Screen:** `AsyncIconButton` (trash icon, `busy: isDeleting`) in the header
  `extraActions`, shown in **edit mode only** (`mode == 'edit' && name`
  non-empty), wrapped in `DocTypeGuard(permType: 'write')`. View mode stays
  uncluttered; deleting from a deep link is view → Edit → Delete.

### 7. List refresh after deletion (`todo_controller.dart`)

`refreshTodoDetail()` currently treats any failure as an error snackbar. After
a legitimate delete, the follow-up refresh 404s and the ghost row lingers.
Change: when the re-fetch fails with `DioException` status 404, silently evict
the document — remove it from `todos`/`filteredTodos`, drop it from
`_detailedTodosCache`, and collapse `expandedTodoName` if it was expanded.
All other failures keep the existing error snackbar + leave-intact behaviour.

The dashboard's Upcoming-tasks list may briefly hold a deleted ToDo; tapping
it lands on the form's existing "ToDo not found" state, which is acceptable.

## Error handling summary

- Save with empty description → blocked client-side, snackbar.
- Save/close/reopen keep existing optimistic-locking + DioException paths.
- Delete failure → error snackbar, form stays open, `isDeleting` cleared.
- List refresh 404 → silent evict (deletion); other errors unchanged.

## Testing

- **Unit — `html_text_test.dart`:** both helpers against the exact
  screenshot sample (`<div class="ql-editor read-mode"><p>Inventory: Price
  List</p></div>` → `Inventory: Price List`), `<br>`/`</p>` newline handling,
  entity decoding, plain-text passthrough, empty string.
- **Unit — form controller:** `enterEditMode()` flips mode/`isEditable` (and
  no-ops in new mode); fetch populates plain text + not dirty; empty-description
  save blocked; `performDelete()` success (provider called, back navigation,
  dirty cleared) and failure (snackbar path, form stays) via `_Fake*` provider;
  priority options exclude Urgent.
- **Unit — list controller:** `refreshTodoDetail` 404 evicts row + cache +
  collapses expansion; non-404 failure keeps row and errors.
- **Widget — form screen:** view mode renders formatted description text (no
  raw tags visible); header title shows description first line, not the hash;
  Edit pencil appears in view mode (permission faked true) and tapping it
  makes fields editable; Delete appears in edit mode only; dark-mode render.
- Update existing tests that set `mode` as a plain string to `mode.value`.

Repo test conventions apply: no mocking library — hand-rolled
`_Fake* extends RealClass` fakes; `TestWidgetsFlutterBinding.ensureInitialized()`
+ path_provider MethodChannel stub wherever `ApiProvider` is touched; bare
`Controller()` construction deliberately skips `onInit()`.

## Out of scope

- ToDo fields not currently surfaced: `color`, `role`, `sender`,
  `assignment_rule`, `assigned_by` display.
- Delete on list cards.
- Rich-text editing in the app.
- Dashboard Upcoming-tasks eviction on delete.
