# ToDo Form UX + Full CRUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the ToDo form's hash title and raw-HTML description, and make full CRUD reachable from every entry point (in-place Edit from view mode + Delete).

**Architecture:** A new pure `html_text.dart` util converts Frappe rich-text HTML to plain text (single-line for titles, multi-line for editing). `ToDoFormController.mode` becomes reactive (`RxString`) so a header pencil can flip view→edit in place; delete is a confirm-then-`performDelete()` split mirroring the list controller's `closeTodo`/`setTodoStatus`. The list controller's `refreshTodoDetail` learns to evict a 404'd (deleted) ToDo.

**Tech Stack:** Flutter + GetX, `flutter_html` (existing dep), Dio, hand-rolled `_Fake*` test fakes (no mocking library).

**Spec:** `docs/superpowers/specs/2026-07-11-todo-form-ux-crud-design.md`

## Global Constraints

- Verified v15 facts: ToDo `priority` options are exactly `High, Medium, Low` (no "Urgent"); `description` is `reqd: 1`; `title_field` is `description`; the `date` field's label is "Due Date".
- Never hardcode surface/ink colours — use `colorScheme.*` / `context.scheme.*` (CLAUDE.md contrast rules).
- Async controls need immediate feedback: `AsyncIconButton` + controller `RxBool` cleared in `finally` + re-entrancy guard (CLAUDE.md Async feedback).
- Test conventions: no mocking library — `_Fake* extends RealClass`; `TestWidgetsFlutterBinding.ensureInitialized()` + path_provider MethodChannel stub wherever `ApiProvider` is constructed; bare `Controller()` skips `onInit()` deliberately.
- Baseline: 24 pre-existing, unrelated test failures (warehouse-picker/search-delegate `ListTile` assertion). Success = no NEW failures.
- Run tests from the repo root `C:\Users\asifm\StudioProjects\ddmco_multimax`.

---

### Task 1: Shared HTML→text helpers + dashboard migration

**Files:**
- Create: `lib/app/core/utils/html_text.dart`
- Create: `test/unit/html_text_test.dart`
- Modify: `lib/app/modules/home/widgets/dashboard_todo_card.dart` (delete local `todoPlainText`, lines 6–26; update its one call site ~line 108)
- Modify: `test/unit/dashboard_todo_card_test.dart` (remove the `todoPlainText` group, lines ~24–45)

**Interfaces:**
- Consumes: nothing.
- Produces: `String htmlToPlainText(String html)` and `String htmlToSingleLine(String html)`, top-level functions in `package:multimax/app/core/utils/html_text.dart`. Tasks 2 and 4 import these.

- [ ] **Step 1: Write the failing test**

Create `test/unit/html_text_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/core/utils/html_text.dart';

void main() {
  group('htmlToSingleLine', () {
    test('flattens the Desk ql-editor wrapper to its inner text', () {
      expect(
        htmlToSingleLine(
            '<div class="ql-editor read-mode"><p>Inventory: Price List</p></div>'),
        'Inventory: Price List',
      );
    });

    test('strips tags and joins block elements with spaces', () {
      expect(
        htmlToSingleLine(
            '<div class="ql-editor"><p>Pack <b>DN-101</b></p>\n<p>today</p></div>'),
        'Pack DN-101 today',
      );
    });

    test('decodes common entities and converts <br> to a space', () {
      expect(
        htmlToSingleLine('Check&nbsp;racks<br/>A &amp; B &lt;urgent&gt;'),
        'Check racks A & B <urgent>',
      );
    });

    test('passes plain text through untouched', () {
      expect(htmlToSingleLine('Call supplier'), 'Call supplier');
    });

    test('returns empty for empty input', () {
      expect(htmlToSingleLine(''), '');
    });
  });

  group('htmlToPlainText', () {
    test('converts the Desk sample to plain text', () {
      expect(
        htmlToPlainText(
            '<div class="ql-editor read-mode"><p>Inventory: Price List</p></div>'),
        'Inventory: Price List',
      );
    });

    test('keeps paragraph and <br> structure as newlines', () {
      expect(
        htmlToPlainText('<p>Line one</p><p>Line two<br>Line three</p>'),
        'Line one\nLine two\nLine three',
      );
    });

    test('collapses 3+ newlines to a single blank line', () {
      expect(htmlToPlainText('<p>a</p><br><br><br><p>b</p>'), 'a\n\nb');
    });

    test('decodes entities on multi-line output', () {
      expect(
        htmlToPlainText('Check&nbsp;racks<br/>A &amp; B'),
        'Check racks\nA & B',
      );
    });

    test('returns empty for empty input', () {
      expect(htmlToPlainText(''), '');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/html_text_test.dart`
Expected: FAIL — compile error, `html_text.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/app/core/utils/html_text.dart`:

```dart
/// Pure HTML→plain-text helpers for Frappe rich-text ("Text Editor") fields.
///
/// Frappe stores fields like ToDo.description as HTML (Desk's Quill editor
/// emits `<div class="ql-editor read-mode"><p>…</p></div>`). These helpers
/// flatten that markup for surfaces that need plain text. Kept top-level and
/// pure so they are unit-testable without a widget tree.
library;

String _decodeEntities(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&#39;', "'")
    .replaceAll('&quot;', '"');

/// Converts rich-text HTML to multi-line plain text — for plain-text
/// editors. `<br>` and block-close tags become newlines, every other tag is
/// stripped, common entities are decoded, and runs of 3+ newlines collapse
/// to one blank line.
String htmlToPlainText(String html) {
  var s = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li|h[1-6])>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '');
  s = _decodeEntities(s);
  s = s
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

/// Flattens rich-text HTML to a single-line plain string — for titles and
/// card summaries. Same conversion as [htmlToPlainText], then all whitespace
/// (including newlines) collapses to single spaces.
String htmlToSingleLine(String html) =>
    htmlToPlainText(html).replaceAll(RegExp(r'\s+'), ' ').trim();
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/html_text_test.dart`
Expected: PASS (10 tests).

- [ ] **Step 5: Migrate the dashboard card**

In `lib/app/modules/home/widgets/dashboard_todo_card.dart`:
1. Delete the whole `todoPlainText` function (the doc comment + function, lines ~11–26).
2. Add import: `import 'package:multimax/app/core/utils/html_text.dart';`
3. Change the call site `final title = todoPlainText(todo.description);` → `final title = htmlToSingleLine(todo.description);`

In `test/unit/dashboard_todo_card_test.dart`: delete the entire `group('todoPlainText', …)` block (its cases now live in `html_text_test.dart`). Leave every other group untouched.

- [ ] **Step 6: Run both test files**

Run: `flutter test test/unit/html_text_test.dart test/unit/dashboard_todo_card_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/app/core/utils/html_text.dart test/unit/html_text_test.dart lib/app/modules/home/widgets/dashboard_todo_card.dart test/unit/dashboard_todo_card_test.dart
git commit -m "refactor(html): shared htmlToPlainText/htmlToSingleLine utils"
```

---

### Task 2: Reactive mode, HTML-aware fetch, v15 priority + required description

**Files:**
- Modify: `lib/app/modules/todo/form/todo_form_controller.dart`
- Modify: `lib/app/modules/todo/form/todo_form_screen.dart:32` (one-line compile fix only — full UI work is Task 4)
- Test: `test/unit/todo_form_controller_test.dart`

**Interfaces:**
- Consumes: `htmlToPlainText` from Task 1.
- Produces (Task 4 relies on these): `RxString mode` (was `String`), `void enterEditMode()`, `bool get isEditable` (unchanged signature, now reactive), `static const List<String> priorityOptions = ['Low', 'Medium', 'High']`.

- [ ] **Step 1: Update existing tests + write new failing tests**

In `test/unit/todo_form_controller_test.dart`:

1. Every `..mode = 'x'` cascade becomes `..mode.value = 'x'`, and every bare `ctrl.mode = 'x'` becomes `ctrl.mode.value = 'x'` (≈12 sites).
2. Assertions `expect(ctrl.mode, 'edit')` / `expect(ctrl.mode, 'new', …)` become `expect(ctrl.mode.value, …)`.
3. Replace every `'Urgent'` with `'High'` (the `saveDocument — update` payload test sets/expects `priority`, the dirty-revert test, and the view-mode-ignores test — 4 sites).
4. The three save tests that previously saved with an empty description must now set one first (the new required-field guard would short-circuit them). Add `ctrl.descriptionController.text = 'x';` before `await ctrl.saveDocument();` in:
   - `'flags an error result when create fails'`
   - `'sends the current field values plus the optimistic-lock token'`
   - `'flags an error result and clears isSaving on a Dio failure'`
5. Append these new groups at the end of `main()`:

```dart
  group('enterEditMode', () {
    test('flips view to edit for a saved doc', () {
      final ctrl = ToDoFormController()..name = 'TD-0001';
      ctrl.mode.value = 'view';

      ctrl.enterEditMode();

      expect(ctrl.mode.value, 'edit');
      expect(ctrl.isEditable, isTrue);
    });

    test('no-ops when the doc is unsaved', () {
      final ctrl = ToDoFormController()..name = '';
      ctrl.mode.value = 'view';

      ctrl.enterEditMode();

      expect(ctrl.mode.value, 'view');
    });

    test('no-ops in new mode', () {
      final ctrl = ToDoFormController()..name = '';
      ctrl.mode.value = 'new';

      ctrl.enterEditMode();

      expect(ctrl.mode.value, 'new');
    });
  });

  group('v15 alignment', () {
    test('priority options match v15 todo.json (no Urgent)', () {
      expect(ToDoFormController.priorityOptions, ['Low', 'Medium', 'High']);
    });

    test('fetch converts a Desk HTML description to plain text and stays clean',
        () async {
      fakeProvider.getTodoData = _canned(
          description:
              '<div class="ql-editor read-mode"><p>Inventory: Price List</p></div>');
      final ctrl = ToDoFormController()..name = 'TD-0001';
      ctrl.mode.value = 'edit';

      await ctrl.fetchDocument();

      expect(ctrl.descriptionController.text, 'Inventory: Price List');
      expect(ctrl.isDirty.value, isFalse,
          reason: 'dirty snapshot must be taken AFTER the HTML conversion');
    });

    test('refuses to save when the description is empty (reqd:1 in v15)',
        () async {
      final ctrl = ToDoFormController()..name = '';
      ctrl.mode.value = 'new';
      ctrl.descriptionController.text = '   ';

      await ctrl.saveDocument();

      expect(fakeProvider.lastCreatePayload, isNull);
      expect(ctrl.saveResult.value, SaveResult.error);
      expect(ctrl.isSaving.value, isFalse);
    });
  });
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `flutter test test/unit/todo_form_controller_test.dart`
Expected: FAIL — compile errors (`mode.value` on a `String`, no `enterEditMode`).

- [ ] **Step 3: Implement the controller changes**

In `lib/app/modules/todo/form/todo_form_controller.dart`:

1. Add import: `import 'package:multimax/app/core/utils/html_text.dart';`
2. Replace the `mode` declaration (currently `String mode = (Get.arguments is Map ? Get.arguments['mode'] : null) ?? 'view';`):

```dart
  /// Form mode: `'new'`, `'edit'`, or `'view'`. Reactive so the header's
  /// Edit action can flip view→edit in place and the screen rebuilds.
  final RxString mode =
      RxString((Get.arguments is Map ? Get.arguments['mode'] : null) ?? 'view');
```

3. Replace the priority options (v15 `todo.json` has exactly High/Medium/Low; Frappe validates Select values server-side, so the old `'Urgent'` entry made saves fail):

```dart
  static const List<String> priorityOptions = ['Low', 'Medium', 'High'];
```

4. Mechanical `mode` → `mode.value` at every read/write: `isEditable` getter, `canShowCloseAction` getter, `onInit` (`if (mode.value == 'new')`), `_checkForChanges` (`if (mode.value == 'new')`), and in `saveDocument` (`if (mode.value != 'new')` for the modified token, `if (mode.value == 'new')` for the create branch, and `mode.value = 'edit';` after create).
5. Add `enterEditMode()` right after the `canShowCloseAction` getter:

```dart
  /// Flips a read-only 'view' form into 'edit' in place — used by the header
  /// Edit action so deep-linked entry points (dashboard cards, search,
  /// reference chips) can edit without re-navigating. No-op for unsaved docs
  /// and non-view modes.
  void enterEditMode() {
    if (mode.value != 'view' || name.isEmpty) return;
    mode.value = 'edit';
  }
```

6. In `fetchDocument`, change `descriptionController.text = t.description;` to:

```dart
        descriptionController.text = htmlToPlainText(t.description);
```

(The `_originalJson` snapshot two lines below already runs after this, so the clean/dirty diff uses the converted text.)

7. In `saveDocument`, insert the required-field guard between the re-entrancy guard and `checkStaleAndBlock()`:

```dart
    if (isSaving.value) return;
    // ToDo.description is reqd:1 in v15 — block client-side instead of
    // surfacing a raw server MandatoryError.
    if (descriptionController.text.trim().isEmpty) {
      saveResult.value = SaveResult.error;
      GlobalSnackbar.error(message: 'Description is required');
      return;
    }
    if (checkStaleAndBlock()) return;
```

In `lib/app/modules/todo/form/todo_form_screen.dart` line 32, fix the one compile break:

```dart
      final VoidCallback? onReload =
          controller.mode.value != 'new' ? controller.reloadDocument : null;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/todo_form_controller_test.dart test/widget/todo_form_screen_test.dart test/unit/todo_form_binding_test.dart`
Expected: PASS (widget tests still pass — view-mode rendering is unchanged until Task 4).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/todo/form/todo_form_controller.dart lib/app/modules/todo/form/todo_form_screen.dart test/unit/todo_form_controller_test.dart
git commit -m "fix(todo): reactive form mode, HTML-aware fetch, v15 priority set, required description"
```

---

### Task 3: Delete in the form controller

**Files:**
- Modify: `lib/app/modules/todo/form/todo_form_controller.dart`
- Test: `test/unit/todo_form_controller_test.dart`

**Interfaces:**
- Consumes: `ToDoProvider.deleteTodo(String name)` (exists, `lib/app/data/providers/todo_provider.dart:52`), `GlobalDialog.confirm({title, message, confirmText, confirmColor, icon})`, `AppColors.red700` from `package:multimax/app/data/constants/app_theme.dart`.
- Produces (Task 4 relies on these): `RxBool isDeleting`, `Future<void> deleteDocument()` (confirm + delete + pop), `Future<bool> performDelete()` (testable network core, returns success).

- [ ] **Step 1: Write the failing tests**

In `test/unit/todo_form_controller_test.dart`, extend `_FakeToDoProvider` with:

```dart
  String? lastDeleteName;
  int deleteTodoStatusCode = 202;
  Object? throwOnDelete;

  @override
  Future<Response> deleteTodo(String name) async {
    lastDeleteName = name;
    if (throwOnDelete != null) throw throwOnDelete!;
    return Response(
      requestOptions: RequestOptions(path: '/api/resource/ToDo/$name'),
      statusCode: deleteTodoStatusCode,
    );
  }
```

Append a new group at the end of `main()`:

```dart
  group('performDelete', () {
    test('deletes on the server and clears the dirty flag', () async {
      final ctrl = ToDoFormController()..name = 'TD-0001';
      ctrl.mode.value = 'edit';
      ctrl.isDirty.value = true;

      final deleted = await ctrl.performDelete();

      expect(deleted, isTrue);
      expect(fakeProvider.lastDeleteName, 'TD-0001');
      expect(ctrl.isDirty.value, isFalse,
          reason: 'PopScope must allow the post-delete pop');
      expect(ctrl.isDeleting.value, isFalse);
    });

    test('reports failure and stays put on a server error', () async {
      fakeProvider.deleteTodoStatusCode = 500;
      final ctrl = ToDoFormController()..name = 'TD-0001';
      ctrl.mode.value = 'edit';

      final deleted = await ctrl.performDelete();

      expect(deleted, isFalse);
      expect(ctrl.isDeleting.value, isFalse);
    });

    test('re-entrancy guard skips a delete already in flight', () async {
      final ctrl = ToDoFormController()..name = 'TD-0001';
      ctrl.isDeleting.value = true;

      final deleted = await ctrl.performDelete();

      expect(deleted, isFalse);
      expect(fakeProvider.lastDeleteName, isNull);
    });

    test('reports failure on a Dio exception', () async {
      fakeProvider.throwOnDelete = DioException(
        requestOptions: RequestOptions(path: '/api/resource/ToDo/TD-0001'),
      );
      final ctrl = ToDoFormController()..name = 'TD-0001';

      final deleted = await ctrl.performDelete();

      expect(deleted, isFalse);
      expect(ctrl.isDeleting.value, isFalse);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/todo_form_controller_test.dart`
Expected: FAIL — `performDelete`/`isDeleting` undefined.

- [ ] **Step 3: Implement delete in the controller**

In `lib/app/modules/todo/form/todo_form_controller.dart`:

1. Add import: `import 'package:multimax/app/data/constants/app_theme.dart';`
2. Add the busy flag next to `isClosing`:

```dart
  /// `true` while [performDelete] is in flight.
  var isDeleting = false.obs;
```

3. Add after `toggleCloseReopen()`:

```dart
  // ── Delete ────────────────────────────────────────────────────────────

  /// Confirms, deletes, and pops the form. Frappe's `on_trash` also removes
  /// the assignment from the referenced document's `_assign` — the dialog
  /// says so when a reference is present.
  Future<void> deleteDocument() async {
    if (isDeleting.value) return;
    final t = todo.value;
    final refNote = (t != null && t.hasReference)
        ? ' This also removes the assignment from '
            '${t.referenceType} ${t.referenceName}.'
        : '';
    final confirmed = await GlobalDialog.confirm(
      title: 'Delete ToDo?',
      message: 'This cannot be undone.$refNote',
      confirmText: 'Delete',
      confirmColor: AppColors.red700,
      icon: Icons.delete_outline,
    );
    if (confirmed != true) return;

    final deleted = await performDelete();
    if (deleted) Get.back();
  }

  /// Core delete network logic, split from [deleteDocument] so it can be
  /// exercised without the confirmation dialog (which needs a widget tree).
  /// Returns `true` when the server accepted the deletion. Frappe's REST
  /// DELETE answers 202 Accepted.
  Future<bool> performDelete() async {
    if (isDeleting.value) return false;
    isDeleting.value = true;
    try {
      final response = await _provider.deleteTodo(name);
      if (response.statusCode == 200 ||
          response.statusCode == 202 ||
          response.statusCode == 204) {
        GlobalSnackbar.success(message: 'ToDo Deleted');
        isDirty.value = false;
        return true;
      }
      GlobalSnackbar.error(message: 'Failed to delete ToDo');
      return false;
    } on DioException catch (e) {
      GlobalSnackbar.error(message: 'Failed to delete ToDo: ${e.message}');
      return false;
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to delete ToDo: $e');
      return false;
    } finally {
      isDeleting.value = false;
    }
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/todo_form_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/todo/form/todo_form_controller.dart test/unit/todo_form_controller_test.dart
git commit -m "feat(todo): delete from the form controller with confirm + busy flag"
```

---

### Task 4: Form screen — title, rendered description, Edit/Delete header actions

**Files:**
- Modify: `lib/app/modules/todo/form/todo_form_screen.dart`
- Test: `test/widget/todo_form_screen_test.dart`

**Interfaces:**
- Consumes: `htmlToSingleLine` (Task 1); `mode`/`enterEditMode` (Task 2); `isDeleting`/`deleteDocument` (Task 3); existing `DocTypeGuard(doctype, permType, child)`, `AsyncIconButton(busy, onPressed, tooltip, icon)`.
- Produces: final UI. Nothing downstream.

**Repaint-safety note:** `DocTypeFormHeader`'s `shouldRebuild` compares `extraActions` by *length* only — but every view↔edit flip also flips `onSave` null↔non-null, which `shouldRebuild` does key on, so the header always repaints on a mode flip. The delete spinner repaints via `AsyncIconButton`'s own `Obx`. No extra work needed — this is why the actions below are safe.

- [ ] **Step 1: Update the widget tests (failing first)**

Rewrite `test/widget/todo_form_screen_test.dart` as:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/todo_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/todo/form/todo_form_controller.dart';
import 'package:multimax/app/modules/todo/form/todo_form_screen.dart';

class _FakeToDoProvider extends ToDoProvider {
  final Map<String, dynamic> data;
  _FakeToDoProvider(this.data);

  @override
  Future<Response> getTodo(String name) async => Response(
        requestOptions: RequestOptions(path: '/api/resource/ToDo/$name'),
        statusCode: 200,
        data: {'data': data},
      );
}

class _FakeUserProvider extends UserProvider {
  @override
  Future<Response> getUsers() async => Response(
        requestOptions: RequestOptions(path: '/api/resource/User'),
        statusCode: 200,
        data: {'data': const <Map<String, dynamic>>[]},
      );
}

/// Grants every permission immediately, so DocTypeGuard-wrapped header
/// actions render without a network round-trip.
class _FakePermissionService extends PermissionService {
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => true;
}

Map<String, dynamic> _todoJson() => {
      'name': 'TD-0001',
      'status': 'Open',
      'description':
          '<div class="ql-editor read-mode"><p>Inventory: Price List</p></div>',
      'modified': '2026-07-11 09:00:00',
      'priority': 'High',
      'date': '2026-07-15',
      'reference_type': 'Delivery Note',
      'reference_name': 'DN-00042',
      'allocated_to': 'ops@x.com',
      'owner': 'ops@x.com',
      'assigned_by': '',
    };

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  setUp(() {
    Get.testMode = true;
    Get.put<ApiProvider>(ApiProvider());
    Get.put<ToDoProvider>(_FakeToDoProvider(_todoJson()));
    Get.put<UserProvider>(_FakeUserProvider());
    Get.put<PermissionService>(_FakePermissionService());
    // Bare construction reads Get.arguments (null) → mode 'view', name '';
    // the cascade sets the name so Edit/Delete gating sees a saved doc.
    Get.put(ToDoFormController()..name = 'TD-0001');
  });

  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester,
      {Brightness brightness = Brightness.light}) async {
    final theme = ThemeData(brightness: brightness, useMaterial3: true);
    await tester.pumpWidget(GetMaterialApp(
      theme: theme,
      darkTheme: theme,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: const ToDoFormScreen(),
    ));
    // Two pumps: mount + flush the zero-delay fake fetch.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('titles the form with the description text, not the hash',
      (tester) async {
    await pump(tester);
    expect(find.text('Inventory: Price List'), findsOneWidget);
    expect(find.text('TD-0001'), findsNothing);
  });

  testWidgets('renders the description as rich text, not raw HTML',
      (tester) async {
    await pump(tester);
    expect(find.byType(Html), findsOneWidget);
    expect(find.textContaining('<div', findRichText: true), findsNothing);
  });

  testWidgets('labels the date field Due Date (v15 label)', (tester) async {
    await pump(tester);
    expect(find.text('Due Date'), findsOneWidget);
    expect(find.text('2026-07-15'), findsOneWidget);
  });

  testWidgets('view mode offers Edit; tapping flips to edit in place',
      (tester) async {
    await pump(tester);
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsNothing);

    await tester.tap(find.byTooltip('Edit'));
    await tester.pump();

    expect(find.byTooltip('Edit'), findsNothing);
    expect(find.byTooltip('Delete'), findsOneWidget);
    expect(find.byType(Html), findsNothing,
        reason: 'edit mode swaps the rendered view for the text editor');
  });

  testWidgets('shows the reference document as an open-in-new chip in view mode',
      (tester) async {
    await pump(tester);
    expect(find.text('DN-00042'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
  });

  testWidgets('hides the Save action in view mode', (tester) async {
    await pump(tester);
    expect(find.byTooltip('Save'), findsNothing);
  });

  testWidgets('renders in dark mode', (tester) async {
    await pump(tester, brightness: Brightness.dark);
    expect(find.text('Inventory: Price List'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `flutter test test/widget/todo_form_screen_test.dart`
Expected: FAIL — title still shows `TD-0001`, no `Html` widget, no Edit/Delete tooltips.

- [ ] **Step 3: Implement the screen changes**

In `lib/app/modules/todo/form/todo_form_screen.dart`:

1. Add imports:

```dart
import 'package:flutter_html/flutter_html.dart';
import 'package:multimax/app/core/utils/html_text.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
```

2. Replace the title computation (currently keyed on `t.name`):

```dart
      final plainTitle = t == null ? '' : htmlToSingleLine(t.description);
      final String title = controller.mode.value == 'new'
          ? 'New ToDo'
          : t == null
              ? 'Loading...'
              : (plainTitle.isEmpty ? 'ToDo' : plainTitle);
```

3. Replace `extraActions` with (Edit pencil in view mode, Close/Reopen + Delete in edit mode; all write-gated; hidden while `t == null` so the not-found state stays action-free):

```dart
                extraActions: [
                  if (controller.mode.value == 'view' &&
                      controller.name.isNotEmpty &&
                      t != null)
                    DocTypeGuard(
                      doctype: 'ToDo',
                      permType: 'write',
                      child: IconButton(
                        tooltip: 'Edit',
                        onPressed: controller.enterEditMode,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                  if (canShowClose)
                    AsyncIconButton(
                      busy: controller.isClosing,
                      onPressed: controller.toggleCloseReopen,
                      tooltip: controller.status.value == 'Closed'
                          ? 'Reopen'
                          : 'Close',
                      icon: Icon(
                        controller.status.value == 'Closed'
                            ? Icons.replay
                            : Icons.check_circle_outline,
                      ),
                    ),
                  if (controller.mode.value == 'edit' &&
                      controller.name.isNotEmpty &&
                      t != null)
                    DocTypeGuard(
                      doctype: 'ToDo',
                      permType: 'write',
                      child: AsyncIconButton(
                        busy: controller.isDeleting,
                        onPressed: controller.deleteDocument,
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                ],
```

4. Change `_buildBody(context)` call to `_buildBody(context, t)` (it is only reached when `t != null`, so the parameter is non-nullable) and update the signature + Task section:

```dart
  Widget _buildBody(BuildContext context, ToDo t) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DocSectionCard(
            title: 'Task',
            margin: EdgeInsets.zero,
            children: [
              if (controller.isEditable)
                TextFormField(
                  controller: controller.descriptionController,
                  minLines: 3,
                  maxLines: 8,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Description',
                    hintText: 'What needs to be done?',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: colorScheme.surface,
                  ),
                )
              else if (t.description.trim().isEmpty)
                Text(
                  'No description',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                // Frappe stores the description as rich-text HTML — render
                // it like the list card does instead of showing raw tags.
                Html(
                  data: t.description,
                  style: {
                    'body': Style(
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                      fontSize:
                          FontSize(theme.textTheme.bodyMedium?.fontSize ?? 14),
                      color: colorScheme.onSurface,
                    ),
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDetailsSection(context),
          const SizedBox(height: 16),
          _buildReferenceSection(context),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
```

Add the model import the new signature needs: `import 'package:multimax/app/data/models/todo_model.dart';`

5. In `_buildDetailsSection`, change the date picker's label `'Date'` → `'Due Date'` (v15 label).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/todo_form_screen_test.dart test/unit/todo_form_controller_test.dart`
Expected: PASS.

If `find.text('Inventory: Price List')` unexpectedly finds 2 widgets, `flutter_html` rendered a plain `Text` (not `RichText`) — switch the title assertion to `expect(find.text('Inventory: Price List'), findsWidgets)` plus keep `find.text('TD-0001') findsNothing`, which is the actual regression being pinned.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/todo/form/todo_form_screen.dart test/widget/todo_form_screen_test.dart
git commit -m "feat(todo): human title, rendered description, in-place Edit + Delete actions"
```

---

### Task 5: List refresh evicts deleted ToDos (404)

**Files:**
- Modify: `lib/app/modules/todo/todo_controller.dart:179-197` (`refreshTodoDetail`)
- Test: `test/unit/todo_controller_test.dart`

**Interfaces:**
- Consumes: nothing new (Dio's default config throws `DioException` on non-2xx; fakes return bare `Response`s — both paths must evict).
- Produces: nothing downstream; behavioural fix only.

- [ ] **Step 1: Write the failing tests**

In `test/unit/todo_controller_test.dart`, extend `_FakeToDoProvider`:

```dart
  Object? throwOnGetTodo;
```

and change its `getTodo` override to:

```dart
  @override
  Future<Response> getTodo(String name) async {
    if (throwOnGetTodo != null) throw throwOnGetTodo!;
    return Response(
      requestOptions: RequestOptions(path: '/api/resource/ToDo/$name'),
      statusCode: getTodoStatusCode,
      data: getTodoData == null ? null : {'data': getTodoData},
    );
  }
```

Append to the `refreshTodoDetail` group:

```dart
    // After a delete on the form screen, the list's post-return refresh gets
    // a 404 — that must silently evict the row, not error-snackbar and leave
    // a ghost card behind.
    test('a thrown 404 evicts the deleted ToDo from list, cache, and expansion',
        () async {
      fakeProvider.getTodoData = _canned();
      final ctrl = ToDoController();
      ctrl.todos.add(ToDo.fromJson(_canned()));
      ctrl.filteredTodos.add(ToDo.fromJson(_canned()));
      ctrl.expandedTodoName.value = 'TD-0001';

      fakeProvider.throwOnGetTodo = DioException(
        requestOptions: RequestOptions(path: '/api/resource/ToDo/TD-0001'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/resource/ToDo/TD-0001'),
          statusCode: 404,
        ),
      );
      await ctrl.refreshTodoDetail('TD-0001');

      expect(ctrl.todos, isEmpty);
      expect(ctrl.filteredTodos, isEmpty);
      expect(ctrl.expandedTodoName.value, '');
      expect(ctrl.detailedTodo, isNull);
    });

    test('a non-throwing 404 response also evicts', () async {
      final ctrl = ToDoController();
      ctrl.todos.add(ToDo.fromJson(_canned()));
      fakeProvider.getTodoStatusCode = 404;

      await ctrl.refreshTodoDetail('TD-0001');

      expect(ctrl.todos, isEmpty);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/todo_controller_test.dart`
Expected: FAIL — todos list still contains the row (and the 500-path regression test still passes).

- [ ] **Step 3: Implement the evict**

In `lib/app/modules/todo/todo_controller.dart`:

1. Add import: `import 'package:dio/dio.dart';` (only `DioException` is referenced, so no `Response` name clash with GetX).
2. Replace `refreshTodoDetail` and add the private helper:

```dart
  Future<void> refreshTodoDetail(String name) async {
    if (name.isEmpty) return;
    try {
      final response = await _provider.getTodo(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final updated = ToDo.fromJson(response.data['data']);
        _detailedTodosCache[name] = updated;
        final idx = todos.indexWhere((t) => t.name == name);
        if (idx != -1) {
          todos[idx] = updated;
          _applyLocalSearch();
        }
      } else if (response.statusCode == 404) {
        _evictTodo(name);
      } else {
        AppNotification.error('Failed to refresh ToDo');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _evictTodo(name);
      } else {
        AppNotification.error(e.toString());
      }
    } catch (e) {
      AppNotification.error(e.toString());
    }
  }

  /// Removes a ToDo the server no longer has (deleted on the form screen)
  /// from the list, the detail cache, and the expansion state — silently,
  /// since a 404 after a delete is expected, not an error.
  void _evictTodo(String name) {
    _detailedTodosCache.remove(name);
    todos.removeWhere((t) => t.name == name);
    _applyLocalSearch();
    if (expandedTodoName.value == name) expandedTodoName.value = '';
  }
```

(Keep the existing doc comment above `refreshTodoDetail`, extending it with one line: `/// A 404 means the document was deleted — the row is evicted instead.`)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/todo_controller_test.dart`
Expected: PASS — including the pre-existing "failed re-fetch leaves state intact" 500-path test.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/todo/todo_controller.dart test/unit/todo_controller_test.dart
git commit -m "fix(todo): list refresh evicts a deleted (404) ToDo instead of erroring"
```

---

### Task 6: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Analyzer**

Run: `flutter analyze`
Expected: 0 errors (pre-existing infos/warnings in untouched files are fine).

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: only the 24 pre-existing failures (warehouse-picker / global-search-delegate / PR-sheet `ListTile` assertion families). Compare the failing-test list against the baseline — any NEW failure must be fixed before finishing.

- [ ] **Step 3: On-device smoke checklist (user-assisted)**

Deploy to the Android device and verify against the original screenshot's ToDo:
1. Open a Desk-created ToDo from the dashboard → title is the description text, not the hash; description renders without tags.
2. Tap Edit → fields unlock; description shows clean plain text; priority picker offers Low/Medium/High only.
3. Clear the description → Save → blocked with "Description is required".
4. Edit + save → Desk shows the updated plain-text description.
5. Delete a reference-linked ToDo → confirm dialog mentions the assignment removal; after delete, the list has no ghost row and Desk shows the assignment gone from the referenced document.
