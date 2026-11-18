# Items from Photos: swipe to delete and Download — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove a photo from the review list with a swipe (with Undo), and save the generated Excel/PDF to a chosen folder with a Download button on Mac, iPhone and Android.

**Architecture:** Two controller additions in `StockSheetController` (`removeAt`/`restore`, `download()` with an injectable saver) and their UI in `ReviewList` (a `Dismissible` per row) and the finished-state footer of `StockSheetScreen`. Download uses `file_picker`'s `saveFile(fileName:, bytes:)`.

**Tech Stack:** Flutter (GetX), `file_picker`, the Mac over SSH for the iOS build (`ssh sys6.it.ka 'ssh -o BatchMode=yes mbp.it.ka zsh -s' < script.sh`).

**Spec:** `docs/superpowers/specs/2026-11-18-items-from-photos-swipe-and-download-design.md`

## Global Constraints

- Copy, verbatim: "Photo removed.", "Undo", "Download", "Saved <file name>." (one file, e.g. "Saved Items-20261118-1706.xlsx."), "Saved 2 files.", "Couldn't save the file. Try again."
- Swipe direction end-to-start only; background fill `AppColors.red700` with a white delete icon (CLAUDE.md contrast rules; no other hardcoded colours).
- Swipe disabled exactly when **Generate file** is blocked by a changing list: `controller.adding`, `controller.rechecking`, `controller.fixing`, or `controller.busy` true.
- File names unchanged: `Items-<yyyyMMdd-HHmm>.xlsx` / `.pdf` (from `controller.files`).
- Async rules (CLAUDE.md "Async feedback"): Download has a busy flag set and cleared in `finally`, a re-entry guard, and visible feedback; Share and Download never run at the same time.
- The finished-state footer must not overflow at 360 dp width.
- `file_picker` must support Swift Package Manager on iOS (`ios/<plugin>/Package.swift` in the resolved version, also under the Mac's Flutter 3.45).
- British English; Conventional Commits ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A swipe while photos are still being added or a code is being fixed**: no swipe (row stays). Test in Task 1.
2. **Undo after the list changed** (another row removed or added): the photo comes back at its old index, clamped to the list length, never a crash. Test in Task 1.
3. **A removed photo shared or chosen again**: accepted, not "Those photos are already in the list." Test in Task 1.
4. **Cancel on the second of two Download dialogs**: the first file stays saved; no message. Test in Task 2.
5. **Download tapped twice, or Share tapped while Download runs**: one run only. Test in Task 2.

---

### Task 1: Swipe to delete with Undo

**Files:**
- Modify: `lib/app/modules/stock_sheet/stock_sheet_controller.dart`
- Modify: `lib/app/modules/stock_sheet/widgets/review_list.dart`
- Modify: `lib/app/modules/stock_sheet/stock_sheet_screen.dart` (the `ReviewList(...)` call ~line 421)
- Test: `test/unit/stock_sheet_controller_test.dart`, `test/widget/stock_sheet_review_list_test.dart`, `test/widget/stock_sheet_screen_test.dart`

**Interfaces:**
- Produces: `ReviewEntry? removeAt(int index)` (null when out of range or the list is changing); `void restore(ReviewEntry entry, int index)` (inserts at `index.clamp(0, review.length)`; ignored if an entry with the same path is already listed); `bool get canRemove` (false while `adding`, `rechecking`, `fixing` or `busy`).
- Produces: `ReviewList` gains `required void Function(int index) onRemove` and `bool removeEnabled = true`.

- [ ] **Step 1: Failing tests**
  - Controller: `removeAt drops the entry and returns it`; `removeAt does nothing while photos are being added` (returns null, list unchanged); `restore puts the entry back at its index`; `restore clamps the index after the list shrank`; `a removed photo can be added again` (remove `a.jpg`, then `addPhotos` with a copy that has `a.jpg`'s fingerprint → added, not `alreadyListedMessage`).
  - Review list widget: `swiping a row end-to-start calls onRemove with its index`; `no swipe when removeEnabled is false` (drag left, `onRemove` not called, row still present).
  - Screen widget: `swipe shows "Photo removed." and Undo restores the row` (finds the photo's row again at the same position).
- [ ] **Step 2: Run, expect FAIL** — `flutter test test/unit/stock_sheet_controller_test.dart test/widget/stock_sheet_review_list_test.dart test/widget/stock_sheet_screen_test.dart`.
- [ ] **Step 3: Implement** — controller methods above (removal does not delete the copy; clean-up at close still covers it); `Dismissible(key: ValueKey('dismiss-${entry.path}'), direction: removeEnabled ? DismissDirection.endToStart : DismissDirection.none, background/secondaryBackground: red700 + white `Icons.delete_outline`)` around each row, keeping the existing `ValueKey(path)` for reordering; the screen passes `onRemove` that calls `removeAt`, then shows a `SnackBar` via `ScaffoldMessenger` with text "Photo removed." and a `SnackBarAction` "Undo" calling `restore`, and `removeEnabled: controller.canRemove` inside an `Obx`.
- [ ] **Step 4: Run, expect PASS**; then `flutter test` and `flutter analyze` (no new errors or warnings).
- [ ] **Step 5: Commit** — `feat(stock-sheet): swipe to remove a photo from the list, with Undo`.

### Task 2: Download the generated files

**Files:**
- Modify: `pubspec.yaml` (add `file_picker`; pick the newest version whose iOS package has `Package.swift` and whose Flutter floor is ≤ 3.50; note the resolved version and the SPM check in the commit body)
- Modify: `lib/app/modules/stock_sheet/stock_sheet_controller.dart`
- Modify: `lib/app/modules/stock_sheet/stock_sheet_screen.dart` (finished-state footer ~line 506-530)
- Test: `test/unit/stock_sheet_controller_test.dart`, `test/widget/stock_sheet_screen_test.dart`

**Interfaces:**
- Produces: `typedef FileSaver = Future<bool> Function(String fileName, Uint8List bytes);` (true when saved, false when the user cancelled; throws on failure); `StockSheetController({..., FileSaver? saveFile})`, default calls `FilePicker.platform.saveFile(fileName: fileName, bytes: bytes)` and returns `result != null`; `final downloading = false.obs;`; `Future<String?> download()` returning the message to show (`"Saved <name>."`, `"Saved 2 files."`, `"Couldn't save the file. Try again."`) or null (cancelled, nothing to do, or already running).
- `static const String saveFailedMessage = "Couldn't save the file. Try again.";`

- [ ] **Step 1: Failing tests**
  - Controller (fake saver recording `(name, bytes)` calls; files written as today):
    - `download saves each file in order with its name` (Excel + PDF → names `Items-…xlsx` then `Items-…pdf`, returns "Saved 2 files.");
    - `one file returns "Saved <name>."`;
    - `cancelling the second dialog keeps the first and returns null` (saver: true, false → 2 calls, returns null);
    - `a saver error returns saveFailedMessage and stops`;
    - `download while running or while sharing does nothing` (second call returns null, saver called once; `sharing.value = true` → no saver call);
    - `downloading is true during the run and false after`.
  - Screen widget: `finished state shows Download beside Share files`; `tapping Download shows the returned message`; `footer fits at 360 dp` (`tester.view.physicalSize = const Size(360*3, 800*3)`, `devicePixelRatio = 3`, no overflow error).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** — `download()` reads each `XFile` in `files` (`readAsBytes()`), calls the saver per file, stops on `false` (return null) or on an exception (log, return `saveFailedMessage`); guard `if (downloading.value || sharing.value || files.isEmpty) return null;`; `shareAgain` also returns early while `downloading`. Footer: `AsyncFilledButton` Share files (Expanded) · an outlined Download control driven by `downloading` (`AsyncIconButton`/outlined button with `Icons.download_outlined` and the label "Download"; icon-only below 400 dp width is the builder's call) · Done; the screen shows the returned message with `AppNotification.success` (saved) or `.warning` (failure).
- [ ] **Step 4: Run, expect PASS**; then `flutter test` and `flutter analyze` (no new errors or warnings).
- [ ] **Step 5: Commit** — `feat(stock-sheet): Download the generated files to a chosen folder`.

### Task 3: Mac build, release and device checks

- [ ] **Step 1: Mac Simulator build** — bundle the branch to the Mac (base: a commit the Mac has, e.g. `1a20bc4d`), create a scratch worktree (`git worktree add --detach ~/StudioProjects/<name> <ref>`), `flutter pub get` (record the `file_picker` / `file_picker`-iOS version Flutter 3.45 resolves and that its `Package.swift` exists), `pod install` in `ios/`, then `xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug -destination id=75F8FF47-1E6D-4DF3-B073-818FF17E8B64 build` → `** BUILD SUCCEEDED **`. Never touch the Mac's release checkout. Remove the scratch worktree and helper refs afterwards.
- [ ] **Step 2: Simulator check with the user** (through RustDesk): swipe a row away and Undo it; generate a file and Download it (the Files save sheet on the Simulator).
- [ ] **Step 3: Release** — merge into `release/play-store` with `--no-ff` (re-fetch; clean; no `MERGE_HEAD`; expected tip), bump MINOR with `dart run tool/bump_version.dart --write`, refresh `whatsnew/whatsnew-en-GB`; **ask the user before pushing**; restore the Mac checkout's `pubspec.lock` if it blocks the fast-forward; run `release-headless.sh` until `RESULT: OK uploaded …`; **ask before pushing the `v*` tag** (it starts the Play release).
- [ ] **Step 4: Device checks (user):** Mac TestFlight — swipe/Undo, Download Excel + PDF to Downloads and to OneDrive; iPhone — Download to Files; Android (Pixel, Play internal or the release) — Download through the system picker.
- [ ] **Step 5:** Update `share-to-stock-sheet-feature.md` memory and commit any doc note.
