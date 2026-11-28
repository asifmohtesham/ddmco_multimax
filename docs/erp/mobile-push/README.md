# Mobile push (FCM) — POS Upload delivery alerts

Push notifications to the Multimax app for POS Upload delivery events. Telegram Updates
stays the record. FCM is best-effort.

```
ERP status change ─► Webhook (exists) ─► n8n Events (dedupes)
                                             │  push branch (to build)
                                             ├─► ERP: enabled Mobile Push Device rows for the recipients
                                             └─► FCM HTTP v1 ─► Android, and iOS via APNs
App sign-in / launch ─► mobile_push_register ─► ERP "Mobile Push Device"
App sign-out / switch off ─► mobile_push_unregister
```

## Firebase

- Project `multimax-fb26b`; Android apps `com.ddmco.multimax` and `com.ddmco.multimax.smoke`
  (debug side-by-side build).
- `android/app/google-services.json` is **git-ignored** (this repo is public). Locally, copy it
  from the Firebase console (the download taken after registering both apps lists both).
  CI writes it from the `GOOGLE_SERVICES_JSON_BASE64` repo secret (`release.yml`).
- iOS: the APNs auth key is uploaded to Firebase (Cloud Messaging). `ios/Runner/GoogleService-Info.plist`
  is **git-ignored** too; the project references it, and the Mac release script
  (`~/multimax-ios-release` on the Mac) copies it in for each build. Release/Profile sign with
  `aps-environment = production` (`Runner.entitlements`), Debug with `development`
  (`RunnerDebug.entitlements`). The app ID has Push Notifications on; the App Store profile is
  "Multimax App Store Headless v3". The app registers with `platform = ios` and waits for the
  APNs token before asking FCM for its token.

## ERP (this folder)

| Record | Purpose |
|---|---|
| DocType **Mobile Push Device** (`records/01-…json`) | One row per installed app: `user`, `enabled`, `platform`, `app_id`, `app_version`, `device_model`, `last_seen`, `last_error`, `token` (unique). System Manager only — users write through the API methods. |
| Server Script API `mobile_push_register` (`scripts/register.py`) | Upserts by token for the session user, re-enables it and stamps `last_seen`. A token that belonged to another user moves to the caller. |
| Server Script API `mobile_push_unregister` (`scripts/unregister.py`) | Disables the caller's own row for that token. Unknown tokens are not an error. |
| Server Script API `mobile_push_recipients` (`scripts/recipients.py`) | For the sender: enabled devices of enabled users holding any of `roles` (comma-separated), minus `exclude`. System Manager only, because it returns tokens. |
| Server Script API `mobile_push_mark_invalid` (`scripts/mark-invalid.py`) | For the sender: disables a device FCM rejected and stores `last_error`. System Manager only. |

Apply (idempotent; before-images go to `before/<site>-<ts>/`):

```bash
ERP_KEY=<key>:<secret> python docs/erp/mobile-push/apply.py --site staging --dry-run
ERP_KEY=<key>:<secret> python docs/erp/mobile-push/apply.py --site staging
```

Rollback: delete the four Server Scripts and the DocType (no other record depends on them).

## n8n sender

The sender is n8n credential **Firebase FCM (multimax-fb26b)** (`googleApi` service account, scope
`firebase.messaging`, allowed domain `fcm.googleapis.com` only). Both delivery workflows
(`../pos-upload-delivery/n8n/`) get the same six-node branch:

`Build push alert` → `Read push recipients` → `One message per phone` → `Send push` → `Find dead tokens` → `Disable dead token`

- The branch is a second output of the node that feeds Telegram, so the Telegram alert does not depend on it.
  Every push node continues on error.
- Events: Out for Delivery goes to Stock Managers only. Delivered and Delivery Return go to Delivery
  Dispatchers and Stock Managers. The user who recorded the action is always excluded.
- Overdue: each overdue POS goes to both roles.
- Ready to dispatch (To Deliver on DN submit) is **not** sent: the ERP Webhook does not fire for it today.

## App (`lib/app/data/services/push_service.dart`)

- Started in `main.dart`. A Firebase start failure only turns push off for that run.
- Registers after every sign-in or session restore, for users with **Delivery Dispatcher** or
  **Stock Manager** whose "POS delivery alerts" switch (Notifications settings, on by default)
  is on. Withdraws the phone when the switch goes off or the role goes away, and before sign-out.
  - A 404 (site without the methods) is ignored and retried on the next launch.
- Android channel `pos_delivery` ("POS delivery", high importance). It is also FCM's default
  channel in the manifest.
- Foreground alerts show as an in-app banner with **Open**. Tapping a tray alert opens the
  POS Upload form, also when the alert launched the app.

### Message contract for the sender

```json
{
  "message": {
    "token": "<Mobile Push Device.token>",
    "notification": { "title": "POS Upload delivered", "body": "KA-2026-03835 · <customer>" },
    "data": { "doctype": "POS Upload", "name": "KA-2026-03835", "event": "Delivered" },
    "android": { "priority": "high", "notification": { "channel_id": "pos_delivery", "tag": "KA-2026-03835" } },
    "apns": { "headers": { "apns-collapse-id": "KA-2026-03835", "apns-priority": "10" }, "payload": { "aps": { "sound": "default" } } }
  }
}
```

- `data.doctype` + `data.name` drive tap-to-open. Other doctypes are ignored.
- Keep amounts out of title and body, because they show on the lock screen.
- On FCM `UNREGISTERED` / `INVALID_ARGUMENT` for a token, set that row `enabled = 0` and write
  `last_error`.

## Status

| Step | State |
|---|---|
| Firebase project + Android apps | done (2026-11-27) |
| CI secret `GOOGLE_SERVICES_JSON_BASE64` | set 2026-11-27 |
| ERP DocType + API methods | staging and **live** done and tested 2026-11-27 (live 23:28 Dubai; ZZTEST row deleted) |
| App token registration, tap-to-open, settings switch | released in 2.66.0+169 (Play alpha). Tap-to-open passed on the XCover's Play app 2026-11-28 (background, killed, open). |
| n8n push branch (Events + Overdue) | **live** 2026-11-27 23:46 Dubai (Events b35dd949, Overdue 1b474087); tested end to end first |
| iOS | 2026-11-28: app ID push + profile v3, app code, Mac release script done; waiting on the APNs key + `GoogleService-Info.plist`. `apns` block in the repo workflow copies, **not yet on live n8n**. |
