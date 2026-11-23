# Items from Photos: swipe to delete and Download (design)

Date: 18 November 2026. Size: a small change. Status: for the user's approval.
Builds on `docs/superpowers/specs/2026-11-18-items-from-photos-on-mac-design.md` (released in 2.43.0+131).

## Why

Office staff on the Mac (and phone users) asked for two things after using 2.43.0:
1. **Swipe to delete** in the review list: get rid of a wrong or duplicate photo outright, not just switch it
   off (the switch keeps the row and leaves it out of the file).
2. **Download**: save the generated Excel/PDF straight to a folder. Today the only route is **Share files**,
   whose "Save to Files" panel on the Mac is cramped.

## Goals

- In the review list, swiping a photo's row from right to left removes it from the list; an **Undo** in the
  snackbar puts it back where it was. A removed photo can be added again later (it no longer counts as
  "already in the list").
- After a file is generated, a **Download** button beside **Share files** saves the file(s) to a place the user
  picks, on Mac, iPhone and Android.

## Non-goals

- Swipe on the finished list (the user chose the review list only).
- Saving both files with one dialog (the user chose option 1 below).
- Any change to reading codes, stock checks or the file contents.

## Approaches (Download)

1. **`file_picker`'s save function** — chosen by the user. One dependency; the system save UI on each platform
   (Mac: the standard Save dialog with Downloads, OneDrive and other folders; iPhone: Files' save sheet;
   Android: the system "Save to" picker). With Excel + PDF the user gets two dialogs in turn.
2. Own native code (one folder picker for both files on iOS/Mac, Android's folder picker): one dialog for both,
   but about a hundred lines of Swift and Kotlin, each provable only on devices. Not chosen.

## Design

### Swipe to delete (review list, `lib/app/modules/stock_sheet/widgets/review_list.dart`)

- Each row is wrapped in a `Dismissible` keyed by the photo's path, direction end-to-start only. Background:
  a delete icon on the status red (fill `AppColors.red700`, white icon, per the contrast rules).
- On dismiss the controller removes the entry (new `ReviewEntry? removeAt(int index)`), and the screen shows a
  snackbar "Photo removed." with **Undo**, which calls `restore(entry, index)` (clamped to the list length).
- Swiping is disabled while the list is changing (photos being added, a code being fixed, stock being
  re-checked) or a file is being generated — the same conditions that disable **Generate file** today.
- The removed photo stops counting for duplicates (the duplicate check looks at the current list), so it can
  be shared, chosen or dropped in again. Its copy is still deleted when the screen closes, so Undo keeps working
  until then.
- Removing the last photo leaves an empty list; **Generate file** is already disabled with nothing on the
  sheet.

### Download (finished state, `items_from_photos_screen.dart` footer and `items_from_photos_controller.dart`)

- Footer in the finished state: **Share files** (filled) · **Download** (outlined, download icon) · **Done**.
  On a narrow phone the Download button may show its icon only; the layout must not overflow at 360 dp.
- `ItemsFromPhotosController` gains `final downloading = false.obs;` and `Future<void> download()`, with an
  injectable saver `Future<bool> Function(String fileName, Uint8List bytes)` (default: `file_picker`'s
  `FilePicker.platform.saveFile(fileName:, bytes:)`, true when a location was chosen). It saves each file in
  `files` in turn, with its existing `Items-<yyyyMMdd-HHmm>` name and extension. Busy flag + re-entry guard as
  the project's async rules require; Share and Download are not both active at once.
- Outcomes:
  - all saved: success notice "Saved Items-…xlsx." (one) or "Saved 2 files." (two);
  - the user cancels a dialog: stop there, no message (files saved before the cancel stay saved);
  - an error: warning "Couldn't save the file. Try again." and stop.
- Dependency: `file_picker` (supports Swift Package Manager since 8.3.0). The Mac builds iOS with Flutter
  3.45, so check that `pub get` there resolves a version with `ios/.../Package.swift`, as was done for
  `file_selector`. The app's Info.plist already has `NSPhotoLibraryUsageDescription`, which the plugin's iOS
  code references.

## Verification

- Widget/unit tests: swipe removes the row and Undo restores it at the same position; swipe disabled while
  adding; a removed photo can be added again; Download saves each file through a fake saver in order, stops on
  cancel without a message, shows the success and failure messages, and guards re-entry; the footer fits at
  360 dp.
- Mac Simulator build (as before), then one TestFlight build: Download on the Mac (Save dialog, OneDrive) and
  on an iPhone (Files); Android on the Pixel (system picker). MINOR release.

## Left to the builder

Icon choice, exact snackbar duration, whether the Download button drops its label on narrow screens.
