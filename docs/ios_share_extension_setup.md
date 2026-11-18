# iOS Share Extension (share photos to "Items from Photos")

Set up on 18 November 2026 (release 2.42.0+130); share screen rewritten for the Mac the same day
(release 2.43.0). Specs: `docs/superpowers/specs/2026-11-17-share-to-stock-sheet-design.md` section 6.6 and
`docs/superpowers/specs/2026-11-18-items-from-photos-on-mac-design.md`.

The user selects photos in Photos (or in Finder on a Mac, where Multimax runs as its iPad app), taps Share
and chooses Multimax. Our own `ShareViewController` loads each photo as a file, copies it into the App Group
container, writes the `receive_sharing_intent` hand-over record and opens the app through the URL scheme
`ShareMedia-com.ddmco.multimax`; the plugin's app half hands the paths to `ShareIntakeService`, which opens
"Items from Photos" (route `STOCK_SHEET`). The Runner's `IntakeBridge` also takes photos dragged onto the
window and shares whose URL never brought the app forward.

## What is in the repository

- `ios/ShareExtension/`: `ShareViewController.swift` (our own `UIViewController`; no plugin code):
  a visible card "Sending N photos to Multimax…" with Cancel; `loadFileRepresentation` per image (retried
  once as `public.image`), copies named `<UUID>.<ext>` in the App Group root; writes `ShareKey` (JSON array
  of `{path, mimeType, type: "image"}`, the plugin's `SharedMediaFile`) and `MultimaxShareId` (UUID), then
  opens the app; nothing copied → "Couldn't read these photos."; 120 s time-out with its own message;
  `isModalInPresentation` so a swipe-down can't skip clean-up. Also
  `Info.plist` (share-services extension, images only, at most 100; `AppGroupId = $(CUSTOM_GROUP_ID)`;
  version keys `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)`), `ShareExtension.entitlements`
  (App Group `$(CUSTOM_GROUP_ID)`), `Base.lproj/MainInterface.storyboard`.
  The storyboard route (`NSExtensionMainStoryboard`) is used; do not add `NSExtensionPrincipalClass`.
- `ios/Runner/IntakeBridge.swift` (registered in `AppDelegate.didInitializeImplicitFlutterEngine`), channel
  `com.ddmco.multimax/intake` (Dart: `lib/app/data/services/native_intake.dart`): `isRunningOnMac`,
  `sharedFolders` (App Group root and `NSTemporaryDirectory()`; Dart deletes only the copies it was given
  inside them), `takeStrandedShare` / `markShareHandled` (`MultimaxShareId` against
  `MultimaxHandledShareId` in the app's own defaults; entries missing or older than 24 h are dropped), drag
  and drop (`UIDropInteraction` on the Flutter view → `tmp/dropped/` → `dropped`, or `dropFailed` when
  nothing could be copied), and a start-up sweep of image files older than 24 h in the App Group root,
  `tmp/dropped/` and `tmp/<bundle id>-Inbox/` (never recursive, never `Library/`).
- `ios/Runner/Runner.entitlements`: App Group `$(CUSTOM_GROUP_ID)` beside the time-sensitive notifications key.
- `ios/Runner/Info.plist`: `AppGroupId = $(CUSTOM_GROUP_ID)` and the URL scheme
  `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)`.
- `ios/Runner.xcodeproj/project.pbxproj` (made with the `xcodeproj` Ruby gem 1.28.1, not in Xcode):
  - target `ShareExtension` (app extension, bundle id `com.ddmco.multimax.ShareExtension`, iOS 15.0, team
    `9SMYC6R3PR`, Debug / Release / Profile), its configurations based on `Flutter/Generated.xcconfig` so
    `FLUTTER_BUILD_NAME` / `FLUTTER_BUILD_NUMBER` resolve and the extension's version always equals the app's
    (App Store validation requires it);
  - `LD_RUNPATH_SEARCH_PATHS` includes `@executable_path/../../Frameworks`; `SKIP_INSTALL = YES`;
  - links no package (until 18/11/2026 it linked `receive-sharing-intent`; see "Plugin upgrades");
  - `CUSTOM_GROUP_ID = group.com.ddmco.multimax` in all configurations of Runner and ShareExtension;
  - Runner depends on ShareExtension and embeds it in an "Embed Foundation Extensions" copy phase placed
    **before** "Thin Binary" (after it, Xcode reports a dependency cycle).
- No CocoaPods change: the plugin is a Swift package only, and Swift Package Manager is enabled in the Mac's
  Flutter (`flutter config --enable-swift-package-manager`). The Podfile holds only the Flutter pod.

The extension binary is about 300 KB and does not load Flutter (the linker strips it), so the appex has no
`Frameworks` folder (Apple rejects one).

## Plugin upgrades

The extension writes the plugin's hand-over record by hand, so `receive_sharing_intent` stays pinned to
exactly `1.9.0` in `pubspec.yaml` (its app half force-unwraps a record it cannot decode).
`test/unit/ios_share_extension_contract_test.dart` checks the pin, the keys and field names the Swift code
writes, and that the extension no longer links the plugin. To upgrade: read the new version's
`SharedMediaFile` and URL handling, adjust `ShareViewController.swift` and `IntakeBridge.swift` if they
changed, then move the pin and rebuild on the Mac.

## Apple side (team 9SMYC6R3PR), done 18 November 2026

| Object | Id | How |
|---|---|---|
| App Group `group.com.ddmco.multimax` ("Multimax") | | developer.apple.com (the App Store Connect API has no App Group resource) |
| App ID `com.ddmco.multimax.ShareExtension` ("Multimax Share Extension") | `2DNFTB28X8` | API |
| App Groups capability on `com.ddmco.multimax` (`KV439YAX6F`) and on the extension | | API; group ticked on both in the portal |
| Profile "Multimax App Store Headless v2" (Runner) | `5488JJUF52` | API, certificate `84CG79D48X` |
| Profile "Multimax ShareExtension App Store Headless" | `LVA8D4T2H2` | API, certificate `84CG79D48X` |

Both profiles carry `group.com.ddmco.multimax` and expire on **14 November 2027**, with the certificate. Adding
the capability made the old profile "Multimax App Store Headless" (`F4CPRQK2VP`) INVALID; it is no longer used.

## Headless release (on the Mac, `~/multimax-ios-release/`, not in this repository)

`release-headless.sh` signs both targets: for the build only, it adds manual signing after the line
`PRODUCT_BUNDLE_IDENTIFIER = <exact bundle id>;` of each target, with that target's own profile, checks that
each profile landed in all three configurations, and restores the project file afterwards. It still refuses to
run if the project file has local changes. `ExportOptionsHeadless.plist` maps both bundle ids to their
profiles. Backups of both files: `*.bak-20261118-shareext`.

## Verified

- Unsigned device build (`flutter build ios --release --no-codesign`): `Runner.app/PlugIns/ShareExtension.appex`
  present, version and build equal to the app's, `AppGroupId` resolved, no `Frameworks` folder.
- iOS 26.5 Simulator (iPhone 17 Pro), Debug build from `xcodebuild -destination id=<udid>`: photos shared from
  Photos opened Multimax on the screen (user's own test through RustDesk), and the images were in the App
  Group container.
- Signed export with both profiles: see the release log of 2.42.0+130.
- 2.43.0 work (18/11/2026), iOS 26.5 Simulator: share from Photos through the new share screen, the Item list
  and Dashboard entry points, the start state and "Choose files…" (user's check through RustDesk). Finder
  Share, drag and drop, OneDrive placeholders and barcode reading on the Mac are checked on the TestFlight
  build (plan Task 9).

Not verifiable on the Simulator: reading barcodes from the photos. `mobile_scanner` refuses `analyzeImage` on
the iOS Simulator (Vision needs the GPU), so the screen shows "Reading barcodes from photos isn't supported on
this device." there. Check it on a real iPhone (TestFlight) before submitting for review.

## Mac quirks seen on 18 November 2026

- Xcode 27.2 needed its first-launch components (`sudo xcodebuild -runFirstLaunch`, admin password) before
  the Simulator or devices worked ("CoreSimulator is out of date").
- Xcode 27 has no Simulator.app; the Simulator window is in **DeviceHub**
  (`/Applications/Xcode.app/Contents/Applications/DeviceHub.app`).
- `flutter build ios --simulator` (Flutter 3.45 pre-release) failed with "Could not compute dependency
  graph"; `xcodebuild -workspace Runner.xcworkspace -scheme Runner -destination id=<udid> build` works.

## Smoke test on a device

1. Install from TestFlight. In Photos select several photos of item labels, Share, Multimax: the app opens on
   "Items from Photos" and reads the codes.
2. Share while Multimax is already open (warm start): same result.
3. Share while signed out: the app asks for sign-in, then continues with the same photos.
4. Select 101 photos, or a PDF or link: Multimax is not offered.
