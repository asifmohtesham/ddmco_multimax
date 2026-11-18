**Unverified: not built or run.** This machine has no Xcode. The files below were written from the
`receive_sharing_intent` 1.9.0 README and its `example/ios` project, and have only been checked as well-formed
plists. Treat the first Mac build as the real test.

# iOS Share Extension setup (share photos to the stock sheet)

Spec: `docs/superpowers/specs/2026-11-17-share-to-stock-sheet-design.md` section 6.6.

## What is already in the repository

- `ios/ShareExtension/ShareViewController.swift`: subclass of `RSIShareViewController`.
- `ios/ShareExtension/Info.plist`: share-services extension; activation rule
  `NSExtensionActivationSupportsImageWithMaxCount = 100` (images only); `AppGroupId = $(CUSTOM_GROUP_ID)`.
- `ios/ShareExtension/ShareExtension.entitlements`: App Group `$(CUSTOM_GROUP_ID)`.
- `ios/ShareExtension/Base.lproj/MainInterface.storyboard`: copied from the plugin example; the extension's
  `Info.plist` names it (`NSExtensionMainStoryboard`) and its view controller class is `ShareViewController`.
- `ios/Runner/Info.plist`: the URL scheme `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)` only. It has no signing
  impact. Every existing key is kept.

`project.pbxproj` is deliberately untouched: the target is created in Xcode (step 1).

**Not yet in the repository, on purpose:** the Runner's App Group entitlement and its `AppGroupId` key. Both
need `CUSTOM_GROUP_ID` defined and a Runner provisioning profile that carries the App Group. Neither exists
yet, so committing them would break the next App Store export. They are added on the Mac in step 2, in the
same sitting as the new profile (step 5).

## Naming

- Runner bundle id: `com.ddmco.multimax`.
- Extension bundle id: `com.ddmco.multimax.ShareExtension`.
- App Group: `group.com.ddmco.multimax`. The 1.9.0 README uses a user-defined build setting `CUSTOM_GROUP_ID`
  (the full group id) in both targets, rather than deriving the id from the bundle id; the files above follow it.

## Podfile: no change

The 1.9.0 README says the plugin is distributed as a Swift Package only ("there is no CocoaPods podspec"; the
package has no `.podspec`). A `target 'ShareExtension'` block in `ios/Podfile` would therefore add nothing, and
before the Xcode target exists it would make `pod install` fail. The Podfile is left unchanged. If the first
build reports "no such module 'receive_sharing_intent'", follow step 3 and the README note on build-phase order
instead. The spec's wording ("add the pod to the extension target") is superseded by this.

## Checklist on the Mac

1. **Xcode target.** File, New, Target, Share Extension, named `ShareExtension`. Bundle id
   `com.ddmco.multimax.ShareExtension`, deployment target 15.0 (same as Runner). When Xcode offers to create a
   scheme, accept. Delete the files Xcode generates (`ShareViewController.swift`, `Info.plist`,
   `MainInterface.storyboard`) and add the ones from `ios/ShareExtension/` instead; set the target's
   *Info.plist File* and *Code Signing Entitlements* build settings to them.
2. **App Group, both targets.** Do this together with step 5: the Runner change below needs the new
   profile, and a release exported in between will fail to sign.
   - Signing & Capabilities: add *App Groups* to Runner and ShareExtension, with `group.com.ddmco.multimax`.
   - Build Settings of **both** targets: add the user-defined setting
     `CUSTOM_GROUP_ID = group.com.ddmco.multimax`.
   - `ios/Runner/Runner.entitlements`: Xcode adds the key when the capability is added; check that it reads
     exactly as below, beside the existing `com.apple.developer.usernotifications.time-sensitive`:

     ```xml
     <key>com.apple.security.application-groups</key>
     <array>
     	<string>$(CUSTOM_GROUP_ID)</string>
     </array>
     ```

   - `ios/Runner/Info.plist`: add the key the plugin reads to find the shared container:

     ```xml
     <key>AppGroupId</key>
     <string>$(CUSTOM_GROUP_ID)</string>
     ```

   - Commit both Runner files with the profile change, not before.
   - The extension uses the storyboard route (`NSExtensionMainStoryboard = MainInterface`). Do **not** add
     `NSExtensionPrincipalClass` to `ios/ShareExtension/Info.plist`, even if Xcode or a guide suggests it:
     the two keys are alternative ways to create the view controller, and only the storyboard one is set.
3. **Plugin for the extension.** Enable SPM (`flutter config --enable-swift-package-manager`), then
   ShareExtension, General, Frameworks and Libraries, add `receive-sharing-intent` from the
   `receive_sharing_intent` Swift package. Move Runner's *Embed Foundation Extensions* phase above
   *Thin Binary*.
4. **Developer portal.** Register the App Group `group.com.ddmco.multimax`; add it to the App ID
   `com.ddmco.multimax`. Create the App ID `com.ddmco.multimax.ShareExtension` with the App Groups capability and
   the same group.
5. **Provisioning profiles.** Regenerate the Runner distribution profile (it must carry the App Group before
   the Runner entitlement from step 2 is committed) and
   create an App Store profile for `com.ddmco.multimax.ShareExtension`. Current certificate and profiles expire on
   14/11/2027; the new profile will have its own expiry, so note it.
6. **Headless release.** `~/multimax-ios-release/release-headless.sh` (on the Mac, not in this repository) now
   signs and exports two targets. Its `ExportOptions.plist` must list a profile for each bundle id under
   `provisioningProfiles`:
   `com.ddmco.multimax` and `com.ddmco.multimax.ShareExtension`. Install both profiles on the Mac before running.

## Smoke test

1. Build and install on a device (Simulator can share, but use a device for the release path).
2. Open Photos, select several photos of barcode labels, Share, choose Multimax. The app opens on the format
   sheet.
3. Share 101 photos: the share sheet should not offer Multimax (activation rule limit).
4. Share a non-image (a PDF or a link): Multimax should not be offered.
5. Share while signed out: the app asks for sign-in, then continues with the same photos.
6. Run the headless release and confirm the archive contains `Multimax.app/PlugIns/ShareExtension.appex`.
