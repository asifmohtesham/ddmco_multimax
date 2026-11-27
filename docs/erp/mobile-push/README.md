# Mobile push (FCM) — POS Upload delivery alerts

Push notifications to the Multimax app for POS Upload delivery events. Telegram Updates
stays the record. FCM is best-effort.

```
ERP status change ─► Webhook (exists) ─► n8n Events (dedupes)
                                             │  push branch (to build)
                                             ├─► ERP: enabled Mobile Push Device rows for the recipients
                                             └─► FCM HTTP v1 ─► Android (iOS later, via APNs)
App sign-in / launch ─► mobile_push_register ─► ERP "Mobile Push Device"
App sign-out / switch off ─► mobile_push_unregister
```

## Firebase

- Project `multimax-fb26b`; Android apps `com.ddmco.multimax` and `com.ddmco.multimax.smoke`
  (debug side-by-side build).
- `android/app/google-services.json` is **git-ignored** (this repo is public). Locally, copy it
  from the Firebase console (the download taken after registering both apps lists both).
  CI writes it from the `GOOGLE_SERVICES_JSON_BASE64` repo secret (`release.yml`).
- iOS: not set up. Needs an APNs key in Firebase, `GoogleService-Info.plist`, the
  `aps-environment` entitlement and the `remote-notification` background mode. Until then
  `PushService` only starts on Android.

## ERP (this folder)

| Record | Purpose |
|---|---|
| DocType **Mobile Push Device** (`records/01-…json`) | One row per installed app: `user`, `enabled`, `platform`, `app_id`, `app_version`, `device_model`, `last_seen`, `last_error`, `token` (unique). System Manager only — users write through the API methods. |
| Server Script API `mobile_push_register` (`scripts/register.py`) | Upserts by token for the session user, re-enables it and stamps `last_seen`. A token that belonged to another user moves to the caller. |
| Server Script API `mobile_push_unregister` (`scripts/unregister.py`) | Disables the caller's own row for that token. Unknown tokens are not an error. |

Apply (idempotent; before-images go to `before/<site>-<ts>/`):

```bash
ERP_KEY=<key>:<secret> python docs/erp/mobile-push/apply.py --site staging --dry-run
ERP_KEY=<key>:<secret> python docs/erp/mobile-push/apply.py --site staging
```

Rollback: delete the two Server Scripts and the DocType (no other record depends on them).

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
    "android": { "priority": "high", "notification": { "channel_id": "pos_delivery", "tag": "KA-2026-03835" } }
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
| ERP DocType + API methods | **staging** done and tested 2026-11-27; live pending |
| App token registration, tap-to-open, settings switch | built, not released |
| n8n push branch (Events + Overdue) | not started |
| iOS | not started |
