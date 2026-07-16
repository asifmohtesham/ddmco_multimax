# Scheduled Draft-Document Notifications — Design

**Date:** 2026-07-16
**Status:** Approved (brainstorm complete, pending implementation plan)
**Base:** `release/play-store` @ v2.10.3+49

## Purpose

Let each user schedule recurring digest notifications about documents that
need action: Purchase Orders, Purchase Receipts, Delivery Notes and Stock
Entries in **Draft** (`docstatus = 0`), and POS Uploads that are **open for
fulfilment** (`status in ['Pending', 'In Progress']`).

The digest is an OS-level Android notification that fires at user-chosen
times even when the app is closed, shows live per-doctype counts, and stays
silent when nothing is pending.

## Decisions (from brainstorm)

| Question | Decision |
|---|---|
| Trigger model | Recurring digest at user-chosen times (no per-doc reminders, no staleness thresholds in v1) |
| Delivery | OS notifications via background execution, app closed included |
| Document scope | Everything the logged-in user's ERPNext permissions can see — no owner filter |
| POS Upload "not Completed" | `Pending` + `In Progress` only (matches existing fulfilment-selector semantics) |
| Approach | Client-side background fetch (`workmanager`) + local notification (`flutter_local_notifications`); no server changes, no FCM |
| Platforms | Android only in v1 (fleet is Zebra/Android); feature hidden elsewhere |

## Architecture

Four units, all new except the prefs extension:

### 1. DigestPrefs (extend `StorageService`)

Per-user persisted settings using the existing `key::user` convention
(cf. `dashboard_tasks_first::user`):

- `notif_digest_enabled::<user>` — bool, default false
- `notif_digest_times::<user>` — list of `"HH:mm"` strings, default `["09:00"]`, max 4
- `notif_digest_days::<user>` — list of weekday ints 1–7 (Mon–Sun), default all
- `notif_digest_doctypes::<user>` — list of enabled doctype keys, default all five

### 2. DigestService (`lib/app/data/services/digest_service.dart`)

**GetX-free, self-contained** — it must run in a background isolate where no
GetX bindings exist. It:

- builds its own Dio client from the stored base URL and the on-disk
  `PersistCookieJar` (same path the app already uses),
- runs one count query per enabled doctype via
  `/api/method/frappe.client.get_count`:
  - PO / PR / DN / SE → `[[doctype, "docstatus", "=", 0]]`
  - POS Upload → `[["POS Upload", "status", "in", ["Pending", "In Progress"]]]`
- returns a `DigestResult`: per-doctype counts, or `authExpired` /
  `networkFailed` markers.

### 3. DigestScheduler

Computes the next fire instant from prefs — the soonest future
(enabled weekday × time) in device-local time — and registers a **one-off
WorkManager task** with that initial delay, network-required constraint, and
a fixed unique work name (cancel-then-schedule, so exactly one pending task
exists at any time). One-off chaining is used because WorkManager periodics
cannot express "daily at 09:00 and 16:00".

Re-armed: after every fire, on every app launch, and on every settings
change. Cancelled (plus notification cleared) on logout.

### 4. Background entry point (`digestCallbackDispatcher`)

Top-level function registered with `workmanager`. At each tick it:

1. initializes storage in the isolate,
2. calls `DigestService`,
3. posts the notification via `flutter_local_notifications`
   (fixed notification ID — a new digest replaces the previous one),
4. asks `DigestScheduler` to arm the next occurrence.

### Data flow

Settings screen → DigestPrefs → `DigestScheduler.rearm()` → WorkManager →
(tick, app possibly dead) → `digestCallbackDispatcher` → `DigestService`
counts → notification if any count > 0 → re-arm.

Tapping the notification opens the app (dashboard). No deep links in v1.

### New dependencies / platform changes

- `workmanager`, `flutter_local_notifications` (versions pinned at plan time)
- `POST_NOTIFICATIONS` in AndroidManifest + Android 13+ runtime request flow
- One notification channel: "Pending documents"

## Settings UI

New **Notifications** row in User Area → Preferences (bell icon), navigating
to `NotificationSettingsScreen` following the Theme / Session Defaults module
pattern (screen + controller + binding + route). Contents:

- **Master switch** — "Scheduled digest". Turning it on triggers the
  `POST_NOTIFICATIONS` runtime request; on denial the switch reverts with a
  snackbar pointing to system settings.
- **Times** — chip row, add/remove via Material time picker, cap 4,
  default 09:00.
- **Days** — seven weekday toggle chips, all on by default.
- **Documents** — five switch rows (PO, PR, DN, SE, POS Upload), all on by
  default. No permission gating in the UI — the worker skips 403s.
- Every change persists immediately and re-arms the scheduler (no save
  button, matching Session Defaults).

## Notification content

One notification, channel "Pending documents":

- Title: `Pending documents (8)` — total across enabled doctypes.
- Body (BigTextStyle), one clause per non-zero doctype:
  `3 draft Stock Entries · 2 draft Purchase Orders · 3 POS Uploads to fulfil`
- All counts zero → **no notification** (silent tick).
- Auth expired → `Session expired — open Multimax to resume digests`
  (same notification ID).

## Error handling

Guiding principle: a background digest must never nag about its own failures.

- **Network unreachable / server 5xx** → skip silently; the next scheduled
  tick is the retry. No retry storm.
- **Auth expired** (401/403 on all queries) → session-expired notification;
  later failures replace it (same ID), never stack.
- **Per-doctype 403** (no read permission) → skip that doctype, count the rest.
- **Broken chain** (crash, force-stop) → app-launch re-arm self-heals.
  WorkManager itself survives reboots.
- **Logout** → cancel scheduled work, clear notification; prefs remain for
  that user's next login.

## Edge cases

- Times are device-local; DST absorbed because each next-occurrence is
  computed fresh at re-arm.
- Settings change with a task queued → cancel-then-schedule by unique work
  name keeps exactly one pending task.
- WorkManager inexactness (± minutes) accepted; network constraint defers
  ticks to when connectivity returns.

## Testing

- **Unit:** next-occurrence computation (times / days / DST boundaries);
  digest message formatting (plurals, zero suppression, ordering);
  `DigestService` filter construction and 401 / 403 / network fault handling
  against mocked Dio.
- **Manual smoke (release gate):** enable digest → forced near-term tick with
  drafts present shows correct counts; no drafts → silent; expired session →
  session-expired notification; reboot → digest still fires.

## Non-goals (v1)

Per-document reminders · staleness thresholds · deep links into filtered
lists · in-app bell / notification center · iOS support · FCM / server push.
