# App Store Publishing Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the Multimax Flutter app (`com.ddmco.multimax`) to the Apple App Store.

**Architecture:** The app is a Flutter project already configured for iOS with all icon sizes present and camera permission declared. Two config bugs (bundle ID mismatch and display name) must be fixed first, then the standard Apple sign-and-ship pipeline applies: Developer Portal → App Store Connect → Xcode Archive → Upload → Review.

**Tech Stack:** Flutter 3.x, Xcode 15+, App Store Connect, Apple Developer Program, Transporter (or Xcode Organizer for upload)

> **Platform note:** Tasks 1–2 edit project files and can run on any OS. Tasks 3–16 require a Mac with Xcode, a paid Apple Developer Program membership ($99/year), and access to App Store Connect.

---

## Critical Findings From Codebase Audit

| Item | Current State | Required State |
|---|---|---|
| iOS bundle ID | `com.ddmco.Multimax` | `com.ddmco.multimax` (match Android/Play Store) |
| iOS display name | `Ddmco Multimax` | `Multimax` |
| `CFBundleName` | `multimax` | `Multimax` |
| DataWedge on iOS | Silent fail (already caught) | No change needed |
| Camera permission | ✓ configured | — |
| App icons | ✓ all sizes present | — |
| iOS deployment target | 13.0 | ✓ acceptable |

---

## Phase 1 — Code & Configuration Fixes

### Task 1: Fix iOS Bundle Identifier

**Files:**
- Modify: `ios/Runner.xcodeproj/project.pbxproj` (lines ~373, 552, 574)

The Xcode project uses `com.ddmco.Multimax`. The Play Store and Android app use `com.ddmco.multimax`. They must match for a unified identity and to avoid App Review confusion.

- [ ] **Step 1: Open project.pbxproj and replace bundle ID**

File: `ios/Runner.xcodeproj/project.pbxproj`

Find every occurrence of:
```
PRODUCT_BUNDLE_IDENTIFIER = com.ddmco.Multimax;
```
Replace with:
```
PRODUCT_BUNDLE_IDENTIFIER = com.ddmco.multimax;
```

There are two occurrences (Debug and Release build configs for the Runner target). Leave the `RunnerTests` bundle IDs as `com.ddmco.multimax.RunnerTests` (update those too from `com.ddmco.Multimax.RunnerTests`).

Run this replace-all command to do it in one shot:
```powershell
(Get-Content ios\Runner.xcodeproj\project.pbxproj) `
  -replace 'com\.ddmco\.Multimax\.RunnerTests', 'com.ddmco.multimax.RunnerTests' `
  -replace 'com\.ddmco\.Multimax', 'com.ddmco.multimax' |
  Set-Content ios\Runner.xcodeproj\project.pbxproj
```

- [ ] **Step 2: Verify the replacement**

```powershell
Select-String -Path ios\Runner.xcodeproj\project.pbxproj -Pattern "PRODUCT_BUNDLE_IDENTIFIER"
```

Expected output (4 lines total):
```
...PRODUCT_BUNDLE_IDENTIFIER = com.ddmco.multimax;
...PRODUCT_BUNDLE_IDENTIFIER = com.ddmco.multimax.RunnerTests;
...PRODUCT_BUNDLE_IDENTIFIER = com.ddmco.multimax.RunnerTests;
...PRODUCT_BUNDLE_IDENTIFIER = com.ddmco.multimax.RunnerTests;
```

No line should still say `Multimax`.

- [ ] **Step 3: Commit**

```bash
git add ios/Runner.xcodeproj/project.pbxproj
git commit -m "fix: align iOS bundle ID with Android (com.ddmco.multimax)"
```

---

### Task 2: Fix iOS App Display Name

**Files:**
- Modify: `ios/Runner/Info.plist`

`CFBundleDisplayName` is "Ddmco Multimax" and `CFBundleName` is "multimax". Both need to show "Multimax" consistently to match the Play Store listing.

- [ ] **Step 1: Edit Info.plist display name**

File: `ios/Runner/Info.plist`

Find:
```xml
	<key>CFBundleDisplayName</key>
	<string>Ddmco Multimax</string>
```
Replace with:
```xml
	<key>CFBundleDisplayName</key>
	<string>Multimax</string>
```

- [ ] **Step 2: Edit Info.plist bundle name**

In the same file, find:
```xml
	<key>CFBundleName</key>
	<string>multimax</string>
```
Replace with:
```xml
	<key>CFBundleName</key>
	<string>Multimax</string>
```

- [ ] **Step 3: Verify**

```powershell
Select-String -Path ios\Runner\Info.plist -Pattern "CFBundleDisplayName|CFBundleName" -Context 0,1
```

Expected:
```
CFBundleDisplayName → Multimax
CFBundleName        → Multimax
```

- [ ] **Step 4: Commit**

```bash
git add ios/Runner/Info.plist
git commit -m "fix: set iOS display name to Multimax"
```

---

## Phase 2 — Apple Developer Portal Setup

> **Requires:** Safari/Chrome on Mac, Apple ID, paid Apple Developer Program membership.

### Task 3: Confirm Apple Developer Program Enrollment

- [ ] **Step 1: Check enrollment status**

Go to: `https://developer.apple.com/account`

Sign in with your Apple ID. Look for the banner that says **"Member"** with your team name. If it says "Enroll", you are not enrolled — enrollment takes 24-48 hours and costs $99/year.

If not enrolled:
1. Click **Enroll**
2. Select **Individual** (if publishing under your own name) or **Organization** (if publishing as DDMCO)
3. For Organization: you need a **D-U-N-S Number** (free, takes 1-5 business days from dnb.com if you don't have one)
4. Complete payment

- [ ] **Step 2: Note your Team ID**

After sign-in, go to: `Membership Details`

Copy your **Team ID** (10-character alphanumeric string like `A1B2C3D4E5`). You'll need it for signing.

---

### Task 4: Create App ID in Developer Portal

An App ID reserves your bundle identifier on Apple's servers.

- [ ] **Step 1: Navigate to Identifiers**

Go to: `https://developer.apple.com/account/resources/identifiers/list`

Click **+** (top-right).

- [ ] **Step 2: Register the App ID**

| Field | Value |
|---|---|
| Type | App IDs |
| Select a type | App |
| Bundle ID | Explicit |
| Bundle ID value | `com.ddmco.multimax` |
| Description | `Multimax` |
| Capabilities | Enable: **Push Notifications** (if needed in future), **Access Wi-Fi Information** (leave off unless needed) |

Click **Continue** → **Register**.

---

### Task 5: Create Distribution Certificate

You need an **Apple Distribution** certificate to sign the IPA for App Store upload.

- [ ] **Step 1: Check if you already have one**

Go to: `https://developer.apple.com/account/resources/certificates/list`

Look for a certificate of type **Apple Distribution**. If one exists and isn't expired, skip to Task 6. If not, continue:

- [ ] **Step 2: Generate a CSR on your Mac**

Open **Keychain Access** → Menu bar: **Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority**

| Field | Value |
|---|---|
| User Email Address | your Apple ID email |
| Common Name | Multimax Distribution |
| CA Email Address | leave blank |
| Request is | Saved to disk |

Save the `.certSigningRequest` file to Desktop.

- [ ] **Step 3: Upload CSR and download certificate**

Back at the Developer Portal, click **+** → select **Apple Distribution** → **Continue** → upload the `.certSigningRequest` → **Continue** → **Download**.

Double-click the downloaded `.cer` file — it installs into Keychain Access automatically.

---

### Task 6: Create App Store Provisioning Profile

- [ ] **Step 1: Create profile**

Go to: `https://developer.apple.com/account/resources/profiles/list`

Click **+** → Under **Distribution**, select **App Store Connect** → **Continue**.

| Field | Value |
|---|---|
| App ID | `com.ddmco.multimax` |
| Certificate | Select the Apple Distribution certificate from Task 5 |
| Profile Name | `Multimax App Store` |

Click **Generate** → **Download**.

- [ ] **Step 2: Install the profile**

Double-click the downloaded `.mobileprovision` file. Xcode picks it up automatically.

---

## Phase 3 — App Store Connect Setup

### Task 7: Create the App in App Store Connect

- [ ] **Step 1: Navigate to My Apps**

Go to: `https://appstoreconnect.apple.com/apps`

Click the **+** button → **New App**.

| Field | Value |
|---|---|
| Platforms | iOS |
| Name | `Multimax` |
| Primary Language | English |
| Bundle ID | `com.ddmco.multimax` (select from dropdown — must match Task 4) |
| SKU | `MULTIMAX-IOS-001` (any unique internal string) |
| User Access | Full Access |

Click **Create**.

---

### Task 8: Prepare App Metadata

All fields below are required before submission.

- [ ] **Step 1: Fill in App Information**

Navigate to: App Store Connect → Multimax → **App Information**

| Field | Value |
|---|---|
| Category | Business (Primary) |
| Secondary Category | Productivity (optional) |
| Content Rights | Does not contain, display, or access third-party content |
| Age Rating | 4+ (no objectionable content) |

- [ ] **Step 2: Fill in Version Information** (under the 1.0 Prepare for Submission section)

| Field | Suggested Content |
|---|---|
| App Name | Multimax |
| Subtitle (30 chars) | Warehouse & Supply Chain |
| Promotional Text (170 chars) | Manage stock, purchase orders, delivery notes, job cards and packing slips — all from your mobile device. |
| Description (4000 chars) | *(see template below)* |
| Keywords (100 chars) | warehouse,stock,erpnext,frappe,delivery,packing,barcode,scanner,supply chain,fulfillment |
| Support URL | A URL your company controls, e.g. `https://www.ddmco.com/support` |
| Marketing URL | Optional |

**Description template:**
```
Multimax is a mobile fulfillment app for supply-chain teams running Frappe/ERPNext.

Key features:
• Stock entry — material transfers and receipts with rack-level precision
• Purchase orders — receive and inspect incoming goods
• Delivery notes — pick, pack and dispatch outbound shipments
• Work orders & job cards — track manufacturing progress on the shop floor
• Packing slips — barcode-driven packing verification
• Barcode scanning — hardware scanner (Zebra DataWedge) and built-in camera scanner

Connects securely to your company's ERPNext instance via HTTPS. Login credentials are provided by your system administrator.
```

- [ ] **Step 3: Fill in Review Information**

This is the most critical section for an enterprise app. App Review cannot test the app without credentials.

Navigate to: App Store Connect → Multimax → **App Review Information**

| Field | Value |
|---|---|
| Sign-In Required | Yes |
| Demo Account Username | *(provide a real read-only ERPNext test account on erp.multimax.cloud)* |
| Demo Account Password | *(the password for that account)* |
| Notes for App Review | "This is an internal warehouse management app. The login screen connects to a private ERPNext instance at erp.multimax.cloud. Please use the demo credentials above to log in. The app requires a valid ERPNext session to function — all data is pulled from the ERP backend over HTTPS." |

> **IMPORTANT:** Create a dedicated demo/reviewer account in ERPNext before submission. The account should have read permissions on at least Stock Entry, Purchase Order, and Delivery Note doctypes so reviewers can navigate the app.

---

### Task 9: Privacy Policy

Apple requires a Privacy Policy URL for any app that accesses personal data or device hardware (camera permission triggers this).

- [ ] **Step 1: Create a privacy policy page**

Host a privacy policy at a stable URL your company controls (e.g. `https://www.ddmco.com/privacy`). Minimum required content:

```
Privacy Policy — Multimax

Data collected: None stored by the app developer.
This app connects to your organization's private ERPNext server.
All data (inventory, orders, users) is stored on that server.
Camera is used only for barcode scanning within the app.
No data is shared with third parties.

Contact: [your company email]
Last updated: 2026-05-20
```

- [ ] **Step 2: Add URL to App Store Connect**

In App Store Connect → Multimax → **App Information**:

| Field | Value |
|---|---|
| Privacy Policy URL | `https://www.ddmco.com/privacy` (your hosted page) |

---

### Task 10: Prepare Screenshots

App Review will reject without screenshots. Required sizes for 2026 App Store:

| Device | Size | Required? |
|---|---|---|
| iPhone 6.9" (iPhone 16 Pro Max) | 1320×2868 px | Yes (or 6.7") |
| iPhone 6.7" (iPhone 14/15 Plus, Pro Max) | 1290×2796 px | Yes |
| iPad 13" (M4 iPad Pro) | 2064×2752 px | Only if iPad supported |

You need **3–10 screenshots** per size. Minimum: 3.

- [ ] **Step 1: Take screenshots on a Mac with iOS Simulator**

```bash
# On Mac, open Simulator
open -a Simulator

# Boot iPhone 15 Pro Max (6.7")
xcrun simctl boot "iPhone 15 Pro Max"

# Run the app in the simulator (from your project directory)
flutter run -d "iPhone 15 Pro Max"
```

Navigate through the app and press `Cmd+S` in Simulator to save screenshots to Desktop.

Suggested screens to capture (3 minimum):
1. Login / Connect to Instance screen
2. Home dashboard or module list
3. A stock entry or purchase order form in use

- [ ] **Step 2: Upload screenshots to App Store Connect**

In App Store Connect → Multimax → **iOS App** → **1.0 Prepare for Submission**

Drag and drop screenshots into the correct device slot. You can reuse 6.7" screenshots for 6.9" if dimensions match; otherwise you may need to scale.

---

## Phase 4 — Mac Build Environment

### Task 11: Set Up Mac Build Environment

> All remaining tasks run on Mac.

- [ ] **Step 1: Install Xcode**

```bash
# Check if Xcode is installed
xcode-select -p
# Expected: /Applications/Xcode.app/Contents/Developer

# If not installed, download from Mac App Store (search "Xcode")
# Accept license after install:
sudo xcodebuild -license accept
```

- [ ] **Step 2: Install Flutter on Mac**

```bash
# Check existing Flutter
flutter --version

# If not installed, download from https://flutter.dev/docs/get-started/install/macos
# Then add to PATH in ~/.zshrc:
export PATH="$HOME/flutter/bin:$PATH"
```

- [ ] **Step 3: Clone/pull the repo and get dependencies**

```bash
cd ~/StudioProjects/ddmco_multimax   # or wherever you clone it
git pull origin release/play-store-beta-1-build-5
flutter pub get
```

- [ ] **Step 4: Verify Flutter doctor**

```bash
flutter doctor -v
```

All items must be green. Resolve any issues before proceeding. Common fixes:
- `cocoapods not installed`: `sudo gem install cocoapods`
- `Xcode not found`: install Xcode via App Store
- `Android toolchain` warning: safe to ignore for iOS-only build

- [ ] **Step 5: Install CocoaPods dependencies**

```bash
cd ios
pod install
cd ..
```

Expected: `Pod installation complete!`

---

## Phase 5 — Xcode Signing Configuration

### Task 12: Configure Code Signing in Xcode

- [ ] **Step 1: Open in Xcode**

```bash
open ios/Runner.xcworkspace
```

> Open the `.xcworkspace` file, NOT `.xcodeproj` — CocoaPods requires the workspace.

- [ ] **Step 2: Configure signing**

In Xcode: Select the **Runner** project in the navigator → Select the **Runner** target → **Signing & Capabilities** tab.

| Setting | Value |
|---|---|
| Automatically manage signing | OFF (recommended for App Store) |
| Team | Select your Apple Developer team |
| Bundle Identifier | `com.ddmco.multimax` |
| Provisioning Profile | `Multimax App Store` (from Task 6) |

Switch to the **Release** scheme: In the build configuration dropdown at the top, select **Release** and repeat if different settings appear.

- [ ] **Step 3: Verify the build compiles**

```bash
flutter build ios --release --no-codesign
```

Expected: `Built build/ios/iphoneos/Runner.app`

If there are errors, fix them before proceeding to archive.

---

## Phase 6 — Build & Upload

### Task 13: Build the IPA

- [ ] **Step 1: Build signed IPA**

```bash
flutter build ipa --release
```

This runs `xcodebuild archive` and creates:
- Archive: `build/ios/archive/Runner.xcarchive`
- IPA: `build/ios/ipa/Multimax.ipa`

Expected output ends with: `Built IPA to build/ios/ipa.`

If signing fails ("No profiles for..."), open Xcode Organizer and archive from there instead (Product → Archive), which gives more diagnostic info.

- [ ] **Step 2: Verify the IPA exists**

```bash
ls -lh build/ios/ipa/
```

Expected: a file named `Multimax.ipa`, size typically 20–80 MB for a Flutter app.

---

### Task 14: Upload IPA to App Store Connect

Option A — Xcode Organizer (easiest):

- [ ] **Step 1: Open Organizer**

In Xcode: **Window → Organizer** → select your archive → **Distribute App**

Choose: **App Store Connect** → **Upload** → Next through the dialogs, accepting defaults → **Upload**.

Wait for "Upload Successful" message (1–5 minutes).

Option B — Transporter app (alternative):

- [ ] **Step 1: Download Transporter from Mac App Store**

Search "Transporter" by Apple Inc. (free).

- [ ] **Step 2: Drag IPA into Transporter**

Open Transporter → sign in with Apple ID → drag `build/ios/ipa/Multimax.ipa` into the window → **Deliver**.

- [ ] **Step 3: Wait for email confirmation**

Apple sends an email to your Apple ID address when the build finishes processing (~15–30 minutes). Subject: "Your submission was received".

---

## Phase 7 — TestFlight Beta (Recommended Before Full Submission)

### Task 15: Internal TestFlight Testing

- [ ] **Step 1: Wait for build to appear in App Store Connect**

Go to: App Store Connect → Multimax → **TestFlight** tab

Once the build processes (~30 min), it appears here. A yellow dot means "Missing Compliance" — click it and answer export compliance questions:

| Question | Answer |
|---|---|
| Does your app use encryption? | Yes (HTTPS) |
| Is it exempt? | Yes — standard HTTPS/TLS qualifies for the Encryption Exemption (EAR 740.17(b)) |

- [ ] **Step 2: Add internal testers**

TestFlight → **Internal Testing** → **+** → add Apple IDs of testers (must be members of your Apple Developer team).

- [ ] **Step 3: Testers install via TestFlight app**

Testers open the **TestFlight** app on their iPhone → find Multimax → **Install**.

- [ ] **Step 4: Validate core flows on real device**

Test on a real iPhone (not simulator) before App Store submission:
- [ ] Login to `erp.multimax.cloud` succeeds
- [ ] Home dashboard loads modules
- [ ] Camera barcode scanner opens and scans
- [ ] Stock Entry form submits without error
- [ ] PDF generation and share sheet work
- [ ] App does not crash on first launch

---

## Phase 8 — App Store Submission

### Task 16: Submit for App Review

- [ ] **Step 1: Select the build in App Store Connect**

App Store Connect → Multimax → **iOS App** → **1.0 Prepare for Submission**

Scroll to **Build** section → click **+** → select the TestFlight build you just validated.

- [ ] **Step 2: Confirm all metadata is complete**

Check that all fields have a green checkmark:
- [ ] App screenshots (at least 6.7" iPhone)
- [ ] Description and keywords
- [ ] Support URL
- [ ] Privacy Policy URL
- [ ] Review credentials (demo account in Review Information)
- [ ] Export Compliance answered
- [ ] Content rights answered
- [ ] Age rating set

- [ ] **Step 3: Submit for review**

Click **Add for Review** → review the summary → **Submit to App Review**.

- [ ] **Step 4: Monitor review status**

App Store Connect → Multimax → **Activity** tab shows review progress.

Typical timelines (as of 2026): 24–48 hours. You receive email updates at each stage change.

Common rejection reasons for this type of app and how to avoid them:
| Rejection Reason | Prevention |
|---|---|
| 2.1 — App completeness (can't log in) | Ensure demo credentials work and are in Review Notes |
| 4.2 — Minimum functionality (too limited) | Show the full module list loads and at least one workflow is functional |
| 5.1.1 — Privacy policy missing | Verify privacy URL is live and loads before submitting |

- [ ] **Step 5: Respond to rejection (if any)**

If Apple rejects, read the Resolution Center message carefully. Reply with a fix or explanation. Resubmit from the same Prepare for Submission page.

---

## Appendix: Enterprise Alternative (Apple Business Manager)

If Multimax is deployed only to DDMCO employees and you don't want the app publicly visible on the App Store, consider **Custom Apps via Apple Business Manager**:

1. Enroll your organization in Apple Business Manager (business.apple.com) — free.
2. In App Store Connect, set distribution to **Custom App Distribution** (not public App Store).
3. Share the app with your Business Manager account.
4. Deploy silently to company devices via MDM (Jamf, Mosyle, etc.) — no App Review for consumer-facing requirements like minimum functionality.

This path still requires App Review but the bar is lower for internal enterprise tools that require login.

---

## Checklist Summary

```
Phase 1 — Code Fixes (any OS)
  [ ] Task 1: Fix iOS bundle ID → com.ddmco.multimax
  [ ] Task 2: Fix display name → Multimax

Phase 2 — Apple Developer Portal (browser + Mac for CSR)
  [ ] Task 3: Confirm Developer Program enrollment
  [ ] Task 4: Create App ID com.ddmco.multimax
  [ ] Task 5: Create Apple Distribution certificate
  [ ] Task 6: Create App Store provisioning profile

Phase 3 — App Store Connect (browser)
  [ ] Task 7: Create app in ASC
  [ ] Task 8: Fill in all metadata
  [ ] Task 9: Create and link privacy policy
  [ ] Task 10: Take and upload screenshots

Phase 4 — Mac Build Environment
  [ ] Task 11: Xcode, Flutter, CocoaPods ready

Phase 5 — Signing
  [ ] Task 12: Xcode signing configured

Phase 6 — Build & Upload
  [ ] Task 13: flutter build ipa --release succeeds
  [ ] Task 14: IPA uploaded via Transporter or Xcode

Phase 7 — TestFlight
  [ ] Task 15: Internal testers validate on real device

Phase 8 — Submission
  [ ] Task 16: Submit for App Review
```
