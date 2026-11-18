# Items from photos on the Mac: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let office staff feed photos from Finder (Share, drag and drop, Choose files…) into "Items from photos" on the Mac, open the screen without a share, and skip photos already in the list by content.

**Architecture:** The iPhone/iPad app runs on the Mac. A rewritten Swift share screen (no plugin code) hands photos to the app through the `receive_sharing_intent` App Group contract. A new Runner bridge (`IntakeBridge`, method channel `com.ddmco.multimax/intake`) delivers drops, stranded shares and Mac detection to Dart. Every route ends in `ShareIntakeService.deliver` or the controller's existing `offerShare` / `addPhotos`.

**Tech Stack:** Flutter (GetX), Swift (UIKit, iOS 15), `file_selector`, `crypto`, the `xcodeproj` Ruby gem for project edits, the Mac over SSH (`ssh sys6.it.ka 'ssh -o BatchMode=yes mbp.it.ka zsh -s' < script.sh`).

**Spec:** `docs/superpowers/specs/2026-11-18-items-from-photos-on-mac-design.md`

## Global Constraints

- iOS deployment target 15.0; iOS plugins through Swift Package Manager only (check any new plugin ships `ios/<name>/Package.swift`).
- `receive_sharing_intent` stays pinned at exactly `1.9.0`; the app half reads `UserDefaults(suiteName: "group.com.ddmco.multimax")` key `ShareKey` = JSON array of `{"path": <file URL absolute string, percent-decoded>, "mimeType": <String?>, "type": "image"}` after the URL `ShareMedia-com.ddmco.multimax:share` opens the app.
- App Group `group.com.ddmco.multimax`; Info.plist key `AppGroupId`.
- At most 100 photos (`StockSheetController.maxPhotos`); images only.
- Share screen time-out: 120 seconds.
- Copy, verbatim: "Items from photos", "Choose files…", "Choose from gallery", "Take a photo", "Choose photos of item labels to list their stock as Excel or PDF.", "On a Mac you can also drag photos here or share them from Finder.", "Sending N photos to Multimax…", "Couldn't read these photos.", "Multimax couldn't get these photos in time. Try fewer, or download them first.", "Switch to Multimax to continue.", existing "Those photos are already in the list."
- British English in copy, comments and commit messages; Conventional Commits; end commits with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never hardcode surface/ink colours (CLAUDE.md "Contrast / colour usage"); async controls give immediate feedback (CLAUDE.md "Async feedback").
- Read `docs/ios_share_extension_setup.md` before touching `ios/`; the Mac's Xcode 27 quirks are listed there (DeviceHub, `xcodebuild -destination id=<udid>` instead of `flutter build ios --simulator`).

## Review Focus

1. **A photo whose file can't be read for fingerprinting** (OneDrive placeholder that failed to download, deleted file): it must still enter the run and show as unreadable, never throw or vanish. Test in Task 1.
2. **The same photo twice inside one share under two names** (Finder copies, two folders): read once. Test in Task 1.
3. **A stranded share seen by both the URL and the resume check**: delivered once. Test in Task 3.
4. **A drop or stranded share while a sheet is being made**: the busy message, not silence. Test in Task 3.
5. **The start state flashing before a share's photos start** (screen opened with paths): no start panel when paths were given. Test in Task 5.

---

### Task 1: Duplicates by content

**Files:**
- Create: `lib/app/modules/stock_sheet/logic/photo_fingerprint.dart`
- Modify: `lib/app/modules/stock_sheet/stock_sheet_controller.dart` (constructor, `start`, `_newPhotos`, `addPhotos`, `offerShare`, `_hold`, `pendingShareFits`)
- Modify: `pubspec.yaml` (add `crypto: ^3.0.7` as a direct dependency)
- Test: `test/unit/stock_sheet_controller_test.dart`, `test/unit/photo_fingerprint_test.dart`

**Interfaces:**
- Produces: `typedef PhotoFingerprinter = Future<Map<String, String>> Function(List<String> paths);` and `Future<Map<String, String>> fingerprintPhotos(List<String> paths)` (SHA-256 hex of each file's bytes, computed with `Isolate.run`; a file that can't be read maps to `'unreadable:<path>'` so it is unique and kept).
- Produces: `StockSheetController({..., PhotoFingerprinter? fingerprint})`.

- [ ] **Step 1: Write the failing tests**

`photo_fingerprint_test.dart`: `same bytes under two names give the same fingerprint`; `a missing file gets a unique unreadable fingerprint` (expect `'unreadable:/no/such.jpg'`).
`stock_sheet_controller_test.dart` (inject a fake `fingerprint` mapping paths to fixed strings):
- `start reads two copies of the same photo once` — paths `a.jpg`, `b.jpg` with the same fingerprint → decoder called with `['a.jpg']`.
- `addPhotos skips a photo already listed by content` — review holds `a.jpg` (fp `X`); `addPhotos(['c.jpg'])` with `c.jpg` → `X` returns `StockSheetController.alreadyListedMessage`.
- `a held share counts only new photos` — while reviewing, `offerShare(['c.jpg','d.jpg'])` with `c.jpg` a content duplicate → `pendingShare` equals `['d.jpg']`.
- `a held share of only duplicates is not asked` — `offerShare(['c.jpg'])` (duplicate) → `pendingShare` stays empty and the returned future/notification yields `alreadyListedMessage` (see Step 3 for the signal).

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/unit/photo_fingerprint_test.dart test/unit/stock_sheet_controller_test.dart`
Expected: FAIL (undefined `fingerprintPhotos`, unknown parameter `fingerprint`).

- [ ] **Step 3: Implement**

- `fingerprintPhotos` in `photo_fingerprint.dart` with `package:crypto` `sha256`.
- Controller keeps `final Map<String, String> _fingerprintOf = {}` for every photo that entered the run (review, adding, held).
- `start`: fingerprint the batch, keep the first path per fingerprint, then proceed as today.
- `_newPhotos` stays the path filter; add `Future<List<String>> _newByContent(List<String> paths)` that fingerprints `paths` and drops those whose fingerprint is already known or repeated within `paths`. `addPhotos` uses it after `_newPhotos`.
- `offerShare` keeps its synchronous `ShareOffer` return. When it would `_hold`, it now calls `unawaited(_holdNew(paths))`, which filters by content first. If nothing is new it bumps a new counter `final alreadyListed = 0.obs;` (the screen turns each bump into the `alreadyListedMessage` warning, Step 5); otherwise it assigns `pendingShare` as today. Test "only duplicates" asserts `alreadyListed.value == 1`.
- `onClose`/`_clear` clear `_fingerprintOf` where they clear the review.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/photo_fingerprint_test.dart test/unit/stock_sheet_controller_test.dart`
Expected: PASS, and the existing controller tests still pass.

- [ ] **Step 5: Show the warning on screen**

In `stock_sheet_screen.dart` `initState`, add `ever<int>(controller.alreadyListed, (_) => AppNotification.warning(StockSheetController.alreadyListedMessage))` to `_workers`. Widget test in `test/widget/stock_sheet_screen_test.dart`: `a re-shared duplicate shows "Those photos are already in the list."`.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/app/modules/stock_sheet test/unit/photo_fingerprint_test.dart test/unit/stock_sheet_controller_test.dart test/widget/stock_sheet_screen_test.dart
git commit -m "feat(stock-sheet): skip photos already in the list by content"
```

### Task 2: Native intake channel (Dart side)

**Files:**
- Create: `lib/app/data/services/native_intake.dart`
- Test: `test/unit/native_intake_test.dart`

**Interfaces:**
- Produces: `class NativeIntake` with `NativeIntake({MethodChannel? channel})`, a shared `static final NativeIntake instance = NativeIntake();` (one channel handler for the app; every default below uses `NativeIntake.instance`), and
  - `Future<bool> isRunningOnMac()` (cached after the first answer; `false` off iOS or on any error),
  - `Future<List<String>> takeStrandedShare()` (absolute file paths; `[]` off iOS or on error),
  - `Future<void> markShareHandled()`,
  - `Future<List<String>> sharedFolders()` (absolute directory paths; `[]` off iOS),
  - `Stream<List<String>> get drops` (native calls method `dropped` with `List<String>` paths).
- Channel name `com.ddmco.multimax/intake`; method names exactly `isRunningOnMac`, `takeStrandedShare`, `markShareHandled`, `sharedFolders`, and native → Dart `dropped`.

- [ ] **Step 1: Write the failing tests** with `TestDefaultBinaryMessengerBinding` mocks: `isRunningOnMac returns the native answer and caches it` (handler called once for two calls); `a channel error reads as not a Mac`; `takeStrandedShare returns the paths`; `a dropped call is emitted on drops` (use `handlePlatformMessage` with `const StandardMethodCodec().encodeMethodCall(MethodCall('dropped', ['/t/a.jpg']))`, expect `['/t/a.jpg']`).
- [ ] **Step 2: Run to verify they fail** — `flutter test test/unit/native_intake_test.dart`, FAIL (missing file).
- [ ] **Step 3: Implement `NativeIntake`** in `native_intake.dart`; guard every call with `!kIsWeb && Platform.isIOS` and catch `PlatformException`/`MissingPluginException`.
- [ ] **Step 4: Run to verify they pass** — same command, PASS.
- [ ] **Step 5: Commit** — `feat(ios): add the native intake channel for drops and stranded shares`.

### Task 3: ShareIntakeService takes drops and stranded shares

**Files:**
- Modify: `lib/app/data/services/share_intake_service.dart`
- Modify: `lib/main.dart:110` (construct with `NativeIntake`-backed defaults; no change if defaults are wired inside the service)
- Test: `test/unit/share_intake_service_test.dart`

**Interfaces:**
- Consumes: `NativeIntake` (Task 2).
- Produces: new optional constructor parameters `Stream<List<String>>? drops`, `Future<List<String>> Function()? strandedShare`, `Future<void> Function()? markShareHandled`, `Stream<void>? resumes`, `Duration strandedDelay = const Duration(milliseconds: 1500)`. Defaults: `NativeIntake.instance.drops`, `.takeStrandedShare`, `.markShareHandled`, and a stream of `AppLifecycleState.resumed` events (from an `AppLifecycleListener`).

- [ ] **Step 1: Write the failing tests** (fake streams, `fakeAsync`):
  - `a drop is delivered like a share` — drop `['/d/a.jpg']` while on HOME and signed in → `openStockSheet` called with it.
  - `a drop while a sheet is being made shows the busy message` — active sheet whose `offerShare` returns `ShareOffer.refusedBusy` → `notify(ShareIntakeService.busyMessage)`.
  - `a warm share marks the share handled` — warm stream emits → `markShareHandled` called once.
  - `a stranded share is picked up after resume` — `resumes` emits, after `strandedDelay` `strandedShare` returns `['/g/a.jpg']` → delivered.
  - `a share delivered by URL is not picked up again on resume` — warm stream emits, then resume: `strandedShare` fake returns `[]` once `markShareHandled` was called; expect exactly one delivery.
- [ ] **Step 2: Run to verify they fail** — `flutter test test/unit/share_intake_service_test.dart`.
- [ ] **Step 3: Implement**: subscribe to `drops` → `deliver`; wrap warm and initial deliveries so non-empty ones call `markShareHandled`; on each resume wait `strandedDelay`, then `deliver(await strandedShare())`. Cancel all subscriptions in `onClose`. Keep `_sharingSupported` gating for the plugin streams only.
- [ ] **Step 4: Run to verify they pass**, plus the whole file's existing tests.
- [ ] **Step 5: Commit** — `feat(share): deliver drops and stranded shares like shares`.

### Task 4: Clean up copies in every intake folder

**Files:**
- Modify: `lib/app/modules/stock_sheet/stock_sheet_controller.dart` (`_deleteSharedCopies`, constructor)
- Test: `test/unit/stock_sheet_controller_test.dart`

**Interfaces:**
- Consumes: `NativeIntake.sharedFolders()` (Task 2).
- Produces: `StockSheetController({..., Future<List<String>> Function()? extraCleanupRoots})`, default `NativeIntake.instance.sharedFolders`.

- [ ] **Step 1: Failing test** `onClose deletes given photos in an extra intake folder but not elsewhere` — temp dirs `root` (temp) and `group` (extra); files `group/x.jpg` and `elsewhere/y.jpg` given via `start`; after `onClose` and a pump, `x.jpg` is gone, `y.jpg` remains.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement**: roots = `[tempDir] + extraCleanupRoots()`; delete a given path if it is within any root (same `p.isWithin` rule).
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `fix(stock-sheet): delete shared and dropped copies outside the cache`.

### Task 5: Start state and Choose files…

**Files:**
- Modify: `pubspec.yaml` (add `file_selector: ^1.0.3`; confirm `file_selector_ios` has `ios/file_selector_ios/Package.swift` in the pub cache, else use `file_picker` with the same `PhotoPicker` shape and note it in the commit)
- Modify: `lib/app/modules/stock_sheet/stock_sheet_screen.dart`
- Create: `lib/app/modules/stock_sheet/widgets/stock_sheet_start_panel.dart`
- Test: `test/widget/stock_sheet_screen_test.dart`

**Interfaces:**
- Consumes: `NativeIntake.isRunningOnMac` (Task 2); `controller.offerShare(List<String>)` (existing).
- Produces: `StockSheetScreen({..., PhotoPicker pickFiles = _chooseFiles, Future<bool> Function() runningOnMac = _runningOnMac})` where `_runningOnMac` calls `NativeIntake.instance.isRunningOnMac()`; `_AddSource.files`; `StockSheetStartPanel({required bool onMac, required VoidCallback onChooseFiles, required VoidCallback onChooseGallery, VoidCallback? onTakePhoto})` (null `onTakePhoto` hides the button).

- [ ] **Step 1: Failing widget tests**:
  - `opened without photos shows the start panel` — texts "Choose photos of item labels to list their stock as Excel or PDF.", "Choose files…", "Choose from gallery", "Take a photo".
  - `on a Mac the camera is hidden and the drag hint shows` — `runningOnMac: () async => true` → no "Take a photo"; finds "On a Mac you can also drag photos here or share them from Finder.".
  - `Choose files… starts a run with the picked files` — `pickFiles` returns `['/f/a.jpg']` → controller `offerShare` receives it (spy controller as in existing tests).
  - `opened with shared photos shows no start panel` — `paths: ['a.jpg']` → "Choose files…" not found after the first frame (Review Focus 5).
  - `the + menu offers Choose files… and adds the picked files` — in review, open the menu, tap "Choose files…" → `addPhotos(['/f/b.jpg'])`.
  - `the + menu hides Take a photo on a Mac`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement**:
  - `_chooseFiles`: `openFiles(acceptedTypeGroups: [XTypeGroup(label: 'Images', extensions: ['jpg','jpeg','png','heic'], mimeTypes: ['image/*'], uniformTypeIdentifiers: ['public.image'])])` → paths; on iOS the picker copies into the app, so OneDrive placeholders arrive downloaded.
  - Start panel shown when `phase == idle` and the screen was opened with no paths (`_openedEmpty`, set in `initState`); buttons call the pickers then `controller.offerShare(paths)`. "Choose files…" is a `FilledButton`, the others `OutlinedButton`. Errors: `"Couldn't open the file dialog."` warning, like the existing gallery/camera messages.
  - "+" menu: third item "Choose files…" (`Icons.folder_open_outlined`) → `_add(_AddSource.files)`; camera item omitted when on a Mac.
- [ ] **Step 4: Run, expect PASS** (and `flutter analyze lib/app/modules/stock_sheet` with no new warnings).
- [ ] **Step 5: Commit** — `feat(stock-sheet): start state and Choose files…`.

### Task 6: Runner bridge (Swift): Mac detection, drops, stranded shares, sweep

**Files:**
- Create: `ios/Runner/IntakeBridge.swift`
- Modify: `ios/Runner/AppDelegate.swift` (`didInitializeImplicitFlutterEngine`: register the bridge with `engineBridge.pluginRegistry.registrar(forPlugin: "IntakeBridge")`)
- Modify: `ios/Runner.xcodeproj/project.pbxproj` (add `IntakeBridge.swift` to the Runner group and Sources phase, with the `xcodeproj` gem as in `docs/ios_share_extension_setup.md`)

**Interfaces:**
- Consumes: channel contract of Task 2; App Group contract (Global Constraints); `MultimaxShareId` written by Task 7.
- Produces (native):
  - `isRunningOnMac` → `ProcessInfo.processInfo.isiOSAppOnMac` (iOS 14+).
  - `sharedFolders` → `[<App Group container path>, NSTemporaryDirectory() + "dropped"]`.
  - `takeStrandedShare` → if group default `MultimaxShareId` differs from the app's `UserDefaults.standard` `MultimaxHandledShareId`, decode `ShareKey` (`[{path,...}]`), convert each file URL to a path, record the id as handled, return the paths; else `[]`.
  - `markShareHandled` → record the current `MultimaxShareId` as handled.
  - Drops: a `UIDropInteraction` on `registrar.viewController?.view`, attached once the view is in a window; `canHandle` only `UTType.image`; `.copy` proposal; on `performDrop` each item `loadFileRepresentation(forTypeIdentifier: UTType.image.identifier)` → copy to `NSTemporaryDirectory()/dropped/<UUID>.<ext>` → when all done, `channel.invokeMethod("dropped", arguments: paths)` (non-empty only).
  - On register: delete image files older than 24 hours in the App Group root and in `dropped/` (never `Library/`).

- [ ] **Step 1: Write the bridge and register it.** No Swift unit tests in this project; Dart Task 2 tests pin the channel contract.
- [ ] **Step 2: Build on the Mac (Simulator)**: bundle the branch to the Mac (as in `docs/ios_share_extension_setup.md`), `flutter pub get`, then `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -destination id=<iOS 26.5 iPhone udid> build`. Expected: `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Check the channel on the Simulator**: install, launch, open "Items from photos" from the Item list (after Task 8) or via a debug route; expect the camera button shown (not a Mac) and no errors in `xcrun simctl spawn <udid> log stream --predicate 'process == "Runner"'`.
- [ ] **Step 4: Commit** — `feat(ios): intake bridge for drops, stranded shares and Mac detection`.

### Task 7: Our own share screen (ShareExtension)

**Files:**
- Modify: `ios/ShareExtension/ShareViewController.swift` (rewrite; no `import receive_sharing_intent`)
- Modify: `ios/ShareExtension/Base.lproj/MainInterface.storyboard` only if the card is built there (else build it in code and keep the storyboard's single view controller)
- Modify: `ios/Runner.xcodeproj/project.pbxproj` (remove the extension's `receive-sharing-intent` product dependency, its build file, and the `XCLocalSwiftPackageReference "receive_sharing_intent"`)
- Modify: `test/unit/ios_share_extension_package_test.dart` → rename to `test/unit/ios_share_extension_contract_test.dart`
- Modify: `pubspec.yaml` comment on the pin (reason is now the `ShareKey` contract)

**Interfaces:**
- Consumes: App Group contract (Global Constraints).
- Produces: group defaults `ShareKey` (contract JSON) and `MultimaxShareId` (UUID string) written together, then the URL `ShareMedia-<host bundle id>:share` opened.

- [ ] **Step 1: Replace the guard test** with `ios_share_extension_contract_test.dart`: `pubspec pins receive_sharing_intent exactly` (`receive_sharing_intent: 1.9.0` line); `the share screen writes the plugin's keys` (Swift source contains `"ShareKey"`, `"MultimaxShareId"`, `"ShareMedia-"`); `the extension no longer links the plugin package` (pbxproj has no `receive_sharing_intent-1.9.0`).
- [ ] **Step 2: Run, expect FAIL** (old Swift, old pbxproj).
- [ ] **Step 3: Rewrite `ShareViewController`** per the spec §1: visible card "Sending N photos to Multimax…" with spinner and Cancel (system colours: `.systemBackground`, `.label`); `loadFileRepresentation` for each `public.image` attachment, copy into the App Group with `<UUID>.<ext>`, order kept, via a `DispatchGroup`; all failed → alert "Couldn't read these photos." then `cancelRequest`; some copied → write `ShareKey` + `MultimaxShareId`, open the app (responder chain to `UIApplication`; `open(_:options:completionHandler:)` on iOS 18+, `openURL:` selector before), wait up to 3 seconds for the host to come forward; if the extension is still visible, change the card text to "Switch to Multimax to continue." and complete after 2 seconds; time-out 120 s → alert "Multimax couldn't get these photos in time. Try fewer, or download them first." then `cancelRequest`.
- [ ] **Step 4: Edit the pbxproj** (Ruby `xcodeproj`): remove the extension's package product dependency, its `PBXBuildFile` and the local package reference; run the contract test, expect PASS.
- [ ] **Step 5: Simulator regression on the Mac**: build as in Task 6 Step 2, install on the iOS 26.5 iPhone Simulator, `xcrun simctl addmedia` two photos, then ask the user (through RustDesk) to share them from Photos to Multimax. Expected: the card shows briefly, Multimax opens on "Items from photos" with 2 photos; the App Group folder (`xcrun simctl get_app_container <udid> com.ddmco.multimax groups`) held the copies.
- [ ] **Step 6: Commit** — `fix(ios): own share screen that never hangs, for Finder on the Mac`.

### Task 8: Entry points (Item list and Dashboard)

**Files:**
- Modify: `lib/app/modules/item/widgets/item_list_app_bar.dart` (`extraActions`)
- Modify: `lib/app/modules/global_widgets/barcode_input_widget.dart` (new `final List<Widget> trailingActions;`, default `const []`, rendered before the camera button in the trailing row, on every platform)
- Modify: `lib/app/modules/home/home_screen.dart:42-48` (pass the Dashboard icon)
- Create: `lib/app/modules/stock_sheet/widgets/items_from_photos_button.dart`
- Test: `test/widget/items_from_photos_button_test.dart`

**Interfaces:**
- Produces: `ItemsFromPhotosButton({super.key, Color? color})` — an `IconButton` (`Icons.photo_library_outlined`, tooltip "Items from photos") wrapped in `DocTypeGuard(doctype: 'Stock Entry', permType: 'report', child: …)`, `onPressed: () => Get.toNamed(AppRoutes.STOCK_SHEET)` (no arguments → start state).

- [ ] **Step 1: Failing widget tests**: `shows the icon with the Items from photos tooltip when allowed`; `hidden without Stock Entry report permission` (use the guard's existing test seam, as in other `DocTypeGuard` tests); `tapping opens the screen with no photos` (GetX test route, expect `Get.currentRoute == AppRoutes.STOCK_SHEET` and `Get.arguments == null`); `BarcodeInputWidget renders trailingActions`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the button, the `trailingActions` slot, and use it in `ItemListAppBar.extraActions` (first in the list) and in `home_screen.dart`'s `BarcodeInputWidget(trailingActions: const [ItemsFromPhotosButton()])`.
- [ ] **Step 4: Run, expect PASS**; `flutter test` (whole suite) and `flutter analyze` with no new errors or warnings.
- [ ] **Step 5: Commit** — `feat(stock-sheet): open Items from photos from the Item list and the Dashboard`.

### Task 9: TestFlight build, Mac and iPhone checks, release

**Files:**
- Modify: `pubspec.yaml` version (MINOR via `dart run tool/bump_version.dart --write`), `whatsnew/whatsnew-en-GB`
- Modify: `docs/ios_share_extension_setup.md` (own share screen, intake bridge, what was verified)
- Memory: `share-to-stock-sheet-feature.md`, `app-store-release-when-mbp-reachable.md`

- [ ] **Step 1:** Merge into `release/play-store` with `--no-ff` (re-fetch; clean; no `MERGE_HEAD`; expected tip), bump (MINOR), refresh `whatsnew`. **No tag yet.** Ask the user before pushing.
- [ ] **Step 2:** After the push, on the Mac: check `git status`, run `release-headless.sh` (header shows the new version), wait for `RESULT: OK uploaded …`.
- [ ] **Step 3: User checklist on the Mac (TestFlight build)**, each with its expected result:
  1. Finder: two local photos and two OneDrive placeholders → Share → Multimax: the card shows, Multimax opens on "Items from photos" with 4 photos, codes read.
  2. List open; share two photos from another folder: "Add these 2 photos to the list, or start again?"; Add appends. Share one of them again: "Those photos are already in the list."
  3. Drag three photos from Finder onto the Multimax window: same as a share.
  4. "Choose files…" from a OneDrive folder, from the start state and from "+".
  5. Item list icon and Dashboard scan-bar icon open the start state; no "Take a photo" on the Mac.
  6. Export Excel and PDF.
  7. If step 1 left Finder's share without Multimax coming forward: switching to Multimax shows the photos (stranded-share fallback).
- [ ] **Step 4: User check on an iPhone (same build):** share label photos from Photos; codes read (open since 2.42.0).
- [ ] **Step 5:** On a full pass, ask the user whether to tag `v<version>` for the Play release (the tag triggers the Play workflow); "Add for Review" stays with the user. On a failure, fix on the branch and repeat Steps 1–3 with the next build number.
- [ ] **Step 6:** Update the setup doc and the two memory files; commit `docs(ios): record the Mac intake routes as built and verified`.
