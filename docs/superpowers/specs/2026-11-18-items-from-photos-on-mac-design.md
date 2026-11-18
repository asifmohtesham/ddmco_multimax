# Items from photos on the Mac: design

Date: 18 November 2026. Status: for the user's approval.
Builds on: `docs/superpowers/specs/2026-11-17-share-to-stock-sheet-design.md` (the screen, its review
list and output) and `docs/ios_share_extension_setup.md` (the iOS share extension, shipped in 2.42.0+130).

## Intent

Office staff at a Mac (macOS Tahoe 26.6.2, Apple silicon) turn photos of item labels into the Items
Excel/PDF. The photos were taken on phones and synced into OneDrive, so they sit in Finder folders, many as
cloud placeholders that are not yet downloaded. Staff work folder by folder: start a list from one folder,
add photos from another, then export. Today they cannot: the phone flow is the only way in.

On the Mac, Multimax is the iPhone/iPad app running on Apple silicon (installed from the App Store or
TestFlight); there is no native macOS build, and this design does not add one.

### What the Mac test of 2.42.0 (130) showed (18/11/2026)

- Finder's Share menu **does** list Multimax and starts the share extension.
- The extension then never finishes: the App Group folder
  (`~/Library/Group Containers/group.com.ddmco.multimax`) stayed empty, its view stayed invisible
  (the plugin clears every background so only a dimmed Finder shows), and Finder looked frozen until the
  extension process was ended.
- Likely cause (not proven; the Mac's unified log showed nothing for the process): the plugin's
  `RSIShareViewController` calls `loadItem(forTypeIdentifier: "public.image")` and accepts the result only as
  a `URL` or a `UIImage`. Anything else (for example `Data`) is ignored without an error, and the request is
  never completed. It also has no time-out and no visible state.
- Barcode reading from photos **works on the Mac**: the user checked it with Dashboard → search → "Search by
  image" on 2.42.0 (130), which uses the same `mobile_scanner.analyzeImage` as this screen.

## Goals

1. **Finder Share works on the Mac**, and keeps working from Photos on iPhone and iPad.
2. **Choose files…**: pick photos from any folder the system file dialog reaches (OneDrive included), both
   to start a list and to add to an open one.
3. **Drag and drop**: photos dragged from Finder onto the Multimax window go into the list.
4. **Open the screen without a share**: a start state on "Items from photos", reachable from the **Item**
   list screen and from the **Dashboard** without adding clutter.
5. Appending keeps today's behaviour: while a list is open, new photos (from any of these routes) bring up
   "Add these N photos to the list, or start again?"; Add appends within the 100-photo limit.
6. **A photo already in the list is not added again, judged by its content** (user's decision), whatever
   folder or route it came from. Every new route copies files under new names, so today's same-path check
   alone would let the same Finder photo in twice.

## Non-goals

- A native macOS app (`macos/` stays unbuilt).
- Any change to reading codes, checking stock or the Excel/PDF output. The review list changes only in its
  duplicate check (goal 6).
- Drag and drop on Android, or between apps on iPhone.
- Talking to OneDrive directly (its own API or sign-in); the system dialogs and Finder do the downloading.

## Anti-goals (failure even if it "works")

- A share or drop that hangs, shows nothing, or loses photos without saying so. Every route ends in the
  screen, the add-or-start-again question, or a visible message.
- A new card or banner on the Dashboard.
- A second, Mac-only flow: every route lands in the same screen and the same controller methods as today.

## Constraints

- iOS deployment target 15.0. iOS plugins resolve through Swift Package Manager only; the Mac's Flutter is
  pre-release 3.45 with SPM on. New plugins must support SPM.
- The app half of `receive_sharing_intent` 1.9.0 stays. Its contract, which our extension must follow:
  - App Group from the `AppGroupId` Info.plist key (`group.com.ddmco.multimax`).
  - `UserDefaults(suiteName: appGroup)` key `ShareKey`: JSON array of objects
    `{ "path": <file URL, absolute string, percent-decoded>, "mimeType": <e.g. image/jpeg>, "type": "image" }`
    (the plugin's `SharedMediaFile`, encoded with `JSONEncoder`). `ShareMessageKey` may be absent.
  - The app is opened with `ShareMedia-com.ddmco.multimax:share`; the plugin reads `ShareKey` when that
    URL arrives (cold start and warm) and `ShareIntakeService` takes it from there.
- Each proof on the Mac costs one TestFlight build (a build number). The Simulator cannot read barcodes
  from photos, cannot test Finder, and cannot test drag from Finder.
- Images only, at most 100 per share (the extension's activation rule; the controller's `maxPhotos`).

## Approaches

### Finder Share (decided by the user: option 1)

1. **Our own share screen in Swift** (chosen). Replace `RSIShareViewController` with our own
   `ShareViewController` that loads each photo as a *file* (`NSItemProvider.loadFileRepresentation`), copies
   it into the App Group folder, writes `ShareKey` in the plugin's format, opens the app, and fails visibly.
2. Patch the plugin (a private copy of `receive_sharing_intent`): same fix, but carried through every
   plugin upgrade.
3. Leave the share broken on the Mac and rely on Choose files and drag and drop: ruled out, Multimax would
   stay in Finder's Share menu and freeze Finder.

### Drag and drop (builder's choice, my recommendation)

1. **Our own drop handler in Swift** (recommended): a `UIDropInteraction` on the Flutter view in the Runner,
   accepting `public.image`, loading each item as a file, copying it into the app's temporary folder, and
   passing the paths to Dart over a method channel. No new dependency.
2. `super_drag_and_drop`: cross-platform, but brings a large native layer (Rust-built binaries) into an
   SPM-only build on a pre-release Flutter, for one drop target on one platform.

### Choose files (builder's choice, my recommendation)

1. **`file_selector`** (Flutter team; iOS uses the system document picker, which copies the chosen files
   into the app, downloading OneDrive placeholders first). Check its SPM support before adding it.
2. `file_picker`: also fine if `file_selector` turns out not to fit (SPM, multi-select, image filter).

## Design

### 1. Share screen (ShareExtension)

- `ios/ShareExtension/ShareViewController.swift` becomes a plain `UIViewController`; it no longer imports
  `receive_sharing_intent`. The extension target drops the `receive-sharing-intent` package product and its
  `XCLocalSwiftPackageReference` (the Runner still gets the plugin through
  `FlutterGeneratedPluginSwiftPackage`).
- It shows a small visible card ("Sending N photos to Multimax…" with a spinner and Cancel), not a clear
  view. Storyboard or code is the builder's call; keep `NSExtensionMainStoryboard` or switch to
  `NSExtensionPrincipalClass` (one, not both).
- For each attachment conforming to `public.image`: `loadFileRepresentation(forTypeIdentifier:
  UTType.image.identifier)`, copy the temporary file into the App Group folder under a unique name that keeps
  the extension (the temporary file is deleted when the callback returns), in the original order.
- When all are done (a dispatch group):
  - none copied: show "Couldn't read these photos." with OK, then `cancelRequest`;
  - some copied: write `ShareKey` (only the copied ones), open the app, `completeRequest`. If some failed,
    the app is still opened; the count shown in the app tells the user.
- **Never hang**: a time-out (my call: 120 seconds, long enough for a few OneDrive downloads) ends with
  "Multimax couldn't get these photos in time. Try fewer, or download them first." and `cancelRequest`.
  Cancel on the card does the same without a message.
- **Opening the app**: the plugin's method (walk the responder chain to `UIApplication` and call
  `open(_:options:completionHandler:)`, or `openURL:` before iOS 18). Whether this opens the app on the Mac
  is **not known**. If it does not, the photos would sit in `ShareKey` until the next share; see Risks.

### 2. Drag and drop (Runner, Mac first)

- Install a `UIDropInteraction` on the Flutter view once the scene's window exists (in the scene delegate
  or a small plugin registered from `AppDelegate`). Accept drops that carry `public.image`; show the copy
  cursor.
- On drop: load each as a file, copy into `NSTemporaryDirectory()/dropped/` with unique names, then call
  Dart over `MethodChannel('com.ddmco.multimax/drop')` with the list of paths.
- Dart: `ShareIntakeService` listens and calls its existing `deliver(paths)`, so a drop behaves exactly like
  a share: it opens "Items from photos" (after sign-in if needed), or asks add-or-start-again on an open
  list, or shows the busy message.

### Clean-up of copied photos (my call)

Today's clean-up deletes only files under `getTemporaryDirectory()`. The new copies live in the App Group
folder (share) and `NSTemporaryDirectory()/dropped/` (drop), so they would pile up on the Mac. Widen the
clean-up to those two folders, at the same moment as today (when the run ends or the screen closes), and
also sweep files older than a day in both on app start, for copies left by a crash.
- Non-image drops are refused by the interaction (no copy cursor).
- iPad gets drag and drop for free from the same code; that is fine.

### 3. Choose files…

- Opens the system file dialog for images, multiple selection. On the Mac that is the Finder-style dialog
  (OneDrive in the sidebar); on iPhone/iPad the Files app; on Android the system picker.
- Offered in two places on "Items from photos":
  - the **start state** (below);
  - the existing "+" menu in the review list's app bar, as a third item **Choose files…** after "Take a photo"
    and "Choose from gallery". It goes through the same `addPhotos(paths)` path as the gallery.

### Duplicates by content

`StockSheetController` keeps a content fingerprint (SHA-256 of the file's bytes; computing it off the UI
isolate is the builder's call) for every photo in the run: the first share, photos added, and photos held
for the add-or-start-again question. A new photo whose fingerprint is already known is skipped, exactly as a
same-path photo is skipped today; the path check stays. The add-or-start-again question counts only the
genuinely new photos, and if none are new the existing "Those photos are already in the list." message is
shown. Applies on every platform.

### 4. Start state of "Items from photos"

Today the screen opened without photos shows nothing (`StockSheetPhase.idle` renders an empty box). It
becomes a start state:

```
┌ Items from photos ─────────────────────┐
│                                        │
│   [photo-stack icon]                   │
│   Choose photos of item labels to      │
│   list their stock as Excel or PDF.    │
│                                        │
│   [ Choose files… ]        (filled)    │
│   [ Choose from gallery ]  (outlined)  │
│   [ Take a photo ]         (outlined)  │
│                                        │
│   On a Mac you can also drag photos    │
│   here or share them from Finder.      │
└────────────────────────────────────────┘
```

- Picking photos starts the normal run (`StockSheetController` with those paths, as a share does).
- "Take a photo" is hidden where there is no camera (the Mac). How to detect "iOS app on Mac"
  (`ProcessInfo.isiOSAppOnMac` over a channel, or camera availability) is the builder's call. The Mac line
  of text shows only on the Mac.
- The screen's other states, the share hand-over and the 100-photo limit are unchanged.

### 5. Entry points

- **Item list screen** (`ItemListAppBar`): an action icon (photo-stack, tooltip "Items from photos") that opens
  the screen with no photos.
- **Who sees the icons** (my call): the screen has no up-front permission check today; it says "You don't
  have access to stock levels." only after the stock check is refused. The icons use the guard the side
  menu already uses for the Stock Balance report (`_rep('Stock Entry')` in `workspace_menu.dart`), since the
  screen's stock figures come from that report. No new permission rule.
- **Dashboard**: no new card. A small icon button **in the existing scan bar** at the bottom of the Dashboard
  (`BarcodeInputWidget`, beside the camera), tooltip "Items from photos". It shows wherever the bar shows,
  including the Mac, where the camera button is irrelevant but present today. My call; the alternative is a
  second icon on the "Scan to start" card.
- Route stays `AppRoutes.STOCK_SHEET`; opening it with no arguments shows the start state.

## Verification

- Dart: widget tests for the start state (buttons, Mac-only text and hidden camera via an injected flag),
  the "+" menu's third item, both entry points, and the drop channel calling `deliver` (fake channel).
  Controller tests for a start-state pick and for a drop while reviewing (add-or-start-again).
- iOS Simulator: share from Photos still opens the screen (regression of the new Swift share screen);
  Choose files from the Files app; the start state.
- Mac, one TestFlight build:
  1. Finder: select two local photos and two OneDrive placeholders, Share, Multimax: the card shows, the
     app opens on "Items from photos", the codes are read.
  2. While the list is open, share from another folder: add-or-start-again appears; Add appends.
  3. Drag photos from Finder onto the window: same as a share.
  4. Choose files… from a OneDrive folder, from the start state and from "+".
  5. Item list icon and Dashboard scan-bar icon open the start state.
  6. Export Excel and PDF.
- iPhone (same TestFlight build): share from Photos, and barcode reading (still unverified on iOS from the
  2.42.0 release).

## Risks and open points

- **The app may not open from the share on the Mac.** If the responder-chain `open` does nothing there, the
  photos stay in `ShareKey`. Fallback (my call: **built up front**, so one TestFlight build answers the
  question either way): our extension also writes a share id (`MultimaxShareId`, a UUID) beside `ShareKey`.
  On app start and resume, a small Runner method channel checks whether that id is newer than the last one
  handled; if so, and no `ShareMedia-…:share` URL has delivered it, it hands the paths to
  `ShareIntakeService` and records the id. The plugin's own path marks the id handled too, so a share is
  never delivered twice. The card says "Opening Multimax…" and, if the app has not come forward after a
  few seconds, "Switch to Multimax to continue."
- The cause of the freeze is inferred, not observed; the new share screen removes every suspect
  (type coercion, no time-out, invisible view), which is why it is chosen over a targeted patch.
- `ShareKey` contract drift: the extension writes the plugin's JSON by hand. Keep `receive_sharing_intent`
  pinned (as now) and re-check the contract on any upgrade. The existing pin test
  (`test/unit/ios_share_extension_package_test.dart`) checks the extension's package path; once the
  extension no longer links the plugin, replace it with a note or a test that the pin is still exact.
- iPad app on Mac and drops from Finder: reported not to work in 2019; to be proved in the TestFlight build.
- Each Mac attempt costs a build number; batch all Mac checks into one build where possible.

## Left to the builder

Storyboard vs code for the share card; the exact time-out; channel and folder names; how the app knows it
runs on a Mac; `file_selector` vs `file_picker`; icon choice; test layout.

## Release

New screens and flows on iOS (and the start state and entry points on Android too): MINOR, per
`docs/versioning_conventions.md`. Play and App Store as usual (this one is not App Store only).
