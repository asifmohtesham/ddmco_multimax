# App update prompts

Multimax checks for a newer store release after the signed-in Home screen first
renders. This includes restored sessions and fresh sign-ins. Subsequent checks
run on foreground resume when more than 12 hours have elapsed since the last
attempt in that session. An in-flight check prevents another from starting.
Check and store errors go to the debug log and do not interrupt app use.

## Android

The release build of `com.ddmco.multimax` checks only if
`PackageInfo.installerStore` is `com.android.vending`. Debug builds, the
`com.ddmco.multimax.smoke` build and sideloads skip the check.

When Play offers a flexible update, Play supplies the consent sheet and downloads
the update in the background. Declining suppresses that version code for 24
hours. A different version code is eligible at the next check.

When Play finishes downloading, a persistent banner offers **Restart** and
**Dismiss**. Users can keep scanning. Restart asks Play to install the update and
shows a spinner while the request is in progress. Dismiss closes the banner for
the current foreground visit. A pending download shows the banner again on
resume, even within 12 hours. A check on a later launch also recovers an already
downloaded update. If a check discovers a previous download still in progress, a
resume can refresh its status before the regular 12-hour offer check.

## iOS

A release build must report `com.apple` from `PackageInfo.installerStore` and
have a production App Store receipt on disk. The receipt matters because
`package_info_plus` also reports `com.apple` when there is no receipt. TestFlight
(`com.apple.testflight`), simulator (`com.apple.simulator`), missing installer
data, debug builds and Xcode installs without a production receipt are excluded.

A dedicated HTTP client looks up `com.ddmco.multimax` on
`itunes.apple.com`. It uses the device region in lowercase and retries once
without the region when the regional lookup returns zero results. The app
compares dot-separated numeric version parts and prompts only for a strictly
newer App Store version. An iOS prompt waits until a later scheduled check if a
dialog or modal bottom sheet is already open.

**Update** opens the release's App Store link in an external app. **Later** or
dismissing the dialog suppresses that store version for 24 hours.

## Local storage

The app's default GetStorage box stores both preferences across restarts and
sign-ins. Each value maps a version string to the UTC epoch timestamp in
milliseconds when it was declined or snoozed.

| Key | Version string |
| --- | --- |
| `app_update_play_declines` | Play version code |
| `app_update_app_store_snoozes` | App Store version |

## Store testing

- **Android** · Install an older Play-signed build that already includes this
  feature through Play internal app sharing or an internal testing track. Make
  a higher version code available to the same tester. With internal app sharing,
  open the newer build's sharing link and leave the update available in Play.
  Open Home in the installed build. Exercise Play consent, decline and the
  per-version snooze. Accept the update, scan while it downloads, then dismiss
  the banner and resume the app before using Restart. A debug sideload will
  never see a Play update.
- **iOS** · Use an older App Store build that already includes this feature
  while a higher version is available in the device region. Verify Later,
  dismissal, and the external App Store link. Confirm that a TestFlight build and
  an Xcode install skip the check.

The feature covers Google Play flexible updates and public App Store releases.
macOS, Windows, Linux, web, immediate Play updates, and managed or alternate
distribution channels are outside its scope. Automated tests use store and
storage fakes. The store testing above exercises distribution, consent, download
and install behavior on real devices.
