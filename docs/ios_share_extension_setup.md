# iOS Share Extension (share photos to "Items from Photos")

Set up and verified on 18 November 2026 (release 2.42.0+130). Spec:
`docs/superpowers/specs/2026-11-17-share-to-stock-sheet-design.md` section 6.6.

The user selects photos in Photos, taps Share and chooses Multimax. The `ShareExtension` target
(`RSIShareViewController` from `receive_sharing_intent` 1.9.0) copies the images into the App Group
container, opens the app through the URL scheme `ShareMedia-com.ddmco.multimax`, and the plugin hands the
paths to `ShareIntakeService`, which opens the "Items from Photos" screen (route `STOCK_SHEET`).

## What is in the repository

- `ios/ShareExtension/`: `ShareViewController.swift` (subclass of `RSIShareViewController`, no overrides),
  `Info.plist` (share-services extension, images only, at most 100; `AppGroupId = $(CUSTOM_GROUP_ID)`;
  version keys `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)`), `ShareExtension.entitlements`
  (App Group `$(CUSTOM_GROUP_ID)`), `Base.lproj/MainInterface.storyboard`.
  The storyboard route (`NSExtensionMainStoryboard`) is used; do not add `NSExtensionPrincipalClass`.
- `ios/Runner/Runner.entitlements`: App Group `$(CUSTOM_GROUP_ID)` beside the time-sensitive notifications key.
- `ios/Runner/Info.plist`: `AppGroupId = $(CUSTOM_GROUP_ID)` and the URL scheme
  `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)`.
- `ios/Runner.xcodeproj/project.pbxproj` (made with the `xcodeproj` Ruby gem 1.28.1, not in Xcode):
  - target `ShareExtension` (app extension, bundle id `com.ddmco.multimax.ShareExtension`, iOS 15.0, team
    `9SMYC6R3PR`, Debug / Release / Profile), its configurations based on `Flutter/Generated.xcconfig` so
    `FLUTTER_BUILD_NAME` / `FLUTTER_BUILD_NUMBER` resolve and the extension's version always equals the app's
    (App Store validation requires it);
  - `LD_RUNPATH_SEARCH_PATHS` includes `@executable_path/../../Frameworks`; `SKIP_INSTALL = YES`;
  - links the Swift package product `receive-sharing-intent` through an `XCLocalSwiftPackageReference` to
    `Flutter/ephemeral/Packages/.packages/receive_sharing_intent-1.9.0` (see "Plugin upgrades");
  - `CUSTOM_GROUP_ID = group.com.ddmco.multimax` in all configurations of Runner and ShareExtension;
  - Runner depends on ShareExtension and embeds it in an "Embed Foundation Extensions" copy phase placed
    **before** "Thin Binary" (after it, Xcode reports a dependency cycle).
- No CocoaPods change: the plugin is a Swift package only, and Swift Package Manager is enabled in the Mac's
  Flutter (`flutter config --enable-swift-package-manager`). The Podfile holds only the Flutter pod.

The extension binary is about 300 KB and does not load Flutter (the linker strips it), so the appex has no
`Frameworks` folder (Apple rejects one).

## Plugin upgrades

Flutter links each plugin's Swift package under `ios/Flutter/ephemeral/Packages/.packages/<name>-<version>`
(the version is in the folder name so Xcode re-reads the manifest after an upgrade). The extension's package
reference therefore names the version. `receive_sharing_intent` is pinned to `1.9.0` in `pubspec.yaml`, and
`test/unit/ios_share_extension_package_test.dart` fails when `pubspec.lock` and the Xcode project disagree.
To upgrade: change the pin, run `flutter pub get`, edit the `relativePath` of
`XCLocalSwiftPackageReference "receive_sharing_intent"` in `project.pbxproj`, and rebuild on the Mac.

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
