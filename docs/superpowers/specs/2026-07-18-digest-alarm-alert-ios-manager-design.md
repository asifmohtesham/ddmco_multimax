# Digest Notifications — Alarm Alerting, iOS Reminders, Manager Gate — Design

**Date:** 2026-07-18
**Status:** Approved (brainstorm complete, pending implementation plan)
**Base:** `origin/release/play-store` @ `ee930539` (v2.12.2+53)
**Extends:** the shipped feature in `2026-07-16-scheduled-draft-notifications-design.md` (released 2.11.0+50)

## Purpose

Three enhancements to the shipped scheduled draft-document digest:

1. **Alarm-like alerting** — when the digest fires (notifications allowed), the
   device alerts with sound + vibration, with a per-user **toggle** between an
   *insistent alarm* style and a *standard* heads-up style.
2. **iOS support** — deliver the digest on iOS as reliable **static scheduled
   reminders** (generic text, no live counts — an iOS platform limitation).
3. **Manager-only gate** — the whole feature is available only to users with a
   *Manager* role.

**Seconds editing is explicitly out of scope** (dropped during brainstorm):
the digest fires via inexact background scheduling, so second precision is not
meaningful. Time editing stays hours + minutes.

## Decisions (from brainstorm)

| Question | Decision |
|---|---|
| Alert intensity | Per-user toggle: `alarm` (insistent) or `standard` (once) |
| "Manager" definition | Any role whose name contains "manager" (case-insensitive) — reuses the dashboard rule (`home_controller.dart:213`) |
| Seconds | Dropped — time stays HH:mm |
| iOS | Static scheduled local notifications, generic text, no counts |
| iOS alert style | `alarm` → Time-Sensitive interruption level; `standard` → active. No looping (no iOS equivalent) |
| Default alert style | `alarm` (honours the "alert like an alarm" request); user can switch to `standard` |

## Manager gate

Add a pure getter to the `User` model (`lib/app/data/models/user_model.dart`):

```dart
bool get isManager =>
    roles.any((r) => r.toLowerCase().contains('manager'));
```

Pure and dependency-free → usable in the UI **and** the Android background
isolate (which reads the persisted `User` via `StorageService.getUser()`). It
mirrors the dashboard's existing "manager persona" rule; the dashboard's own
copy is left untouched (no unrelated refactor).

Gate applied at every layer so it cannot leak:

- **Settings entry** (`user_area_screen.dart`): the "Notifications" row shows
  only when `!kIsWeb && (Platform.isAndroid || Platform.isIOS) && user.isManager`.
- **`DigestScheduler.rearm()`**: treats "not a manager" like "disabled" —
  cancels all scheduled work and returns. So a manager who enables the digest
  and later loses the role is silently stopped at the next launch/tick re-arm.
- **`runDigestTask()`** (Android worker): early-returns if the persisted user
  is not a manager — defense-in-depth for an already-queued task.
- Login and launch re-arm already funnel through `rearm()`, inheriting the gate.

## Alert styles

New per-user pref `notif_digest_alarm_style::<user>` (String, `'alarm'` |
`'standard'`, default `'alarm'`) on `StorageService`, following the existing
`key::user` convention.

The style is applied at post/schedule time (it changes *how* the notification
alerts, not *when* it fires), so changing it does **not** require a re-arm —
it just persists.

### Android — two channels

Android locks a channel's importance/sound/vibration at creation, and the
released `pending_documents` channel is default-importance. So:

- **Delete** the old `pending_documents` channel at worker init
  (`deleteNotificationChannel`, best-effort) so it doesn't linger as a stale,
  silent entry in the user's app-notification settings.
- **Create** two new channels (idempotent, up-front):
  - `pending_documents_alarm` — `Importance.max`,
    `audioAttributesUsage: AudioAttributesUsage.alarm` (alarm volume, cuts
    through), `enableVibration: true` with a strong repeating pattern,
    `playSound: true`.
  - `pending_documents_alert` — `Importance.high`,
    `audioAttributesUsage: AudioAttributesUsage.notification`,
    `enableVibration: true` with a single pulse, `playSound: true`.

At post time the worker reads the style pref and:
- `alarm` → post on `pending_documents_alarm` with
  `additionalFlags: Int32List.fromList([4])` (FLAG_INSISTENT — loops the sound
  until the user opens or dismisses).
- `standard` → post on `pending_documents_alert`, no insistent flag.

Notification id stays `kDigestNotificationId = 1001` (a new digest replaces the
previous). New constants: `kDigestAlarmChannelId`, `kDigestAlertChannelId`.
No new permission — `VIBRATE` is merged from the plugin; alarm-audio and
FLAG_INSISTENT need no special permission. (`VIBRATE` is added to the manifest
explicitly for self-documentation, matching the `POST_NOTIFICATIONS` precedent.)

Android delivery is unchanged: WorkManager background fetch with **live counts**.

### iOS — static scheduled reminders

iOS cannot run code at fire time (background execution is OS-discretionary), so
the digest is delivered as **pre-scheduled local notifications** that fire
reliably even when the app is closed:

- **Mechanism**: `flutter_local_notifications.zonedSchedule` with
  `matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime` — one repeating
  weekly notification per enabled *weekday × time*. With ≤7 days × ≤4 times = ≤28
  scheduled notifications, well under iOS's 64-pending limit.
- **Generic text** (no counts, because no code runs at fire time): title
  `Pending documents`, body `You have documents to review — open Multimax`.
- **Alert style → interruption level**: `alarm` →
  `InterruptionLevel.timeSensitive` (breaks through Focus) + sound; `standard`
  → `InterruptionLevel.active` + sound. No looping.
- **Ids**: a reserved range distinct from `1001`, computed per (weekday, time
  index), so the set can be fully cancelled and rescheduled on re-arm.
- **New dependency + setup**: `flutter_timezone` to read the device's local
  zone name, plus `tz.initializeTimeZones()` + `tz.setLocalLocation(...)` at
  startup (zonedSchedule requires a configured local timezone). Harmless on
  Android; required on iOS.
- **Entitlement**: `com.apple.developer.usernotifications.time-sensitive` added
  to `ios/Runner/Runner.entitlements`.
- **Permission**: the notification-permission request branches by platform —
  iOS calls `IOSFlutterLocalNotificationsPlugin.requestPermissions(alert,
  badge, sound)`. No background modes needed (scheduled local notifications
  don't require them).

There is **no iOS background isolate and no iOS digest worker** — iOS scheduling
happens entirely from the main isolate on re-arm.

## Scheduler platform branching

`DigestScheduler.rearm()` gains a platform branch, keeping the Android worker's
scheduling path plugin-free:

- **Guard (both platforms)**: if the user is null, not a manager, digest
  disabled, or the schedule can never fire → cancel everything (Android
  WorkManager task **and** any iOS reminders) and return.
- **Android** → register the one-off WorkManager task (as today).
- **iOS** → cancel the reserved reminder-id range, then `zonedSchedule` the
  current enabled weekday × time set with the style-mapped interruption level.

For unit-testability, the iOS scheduling is placed behind a seam analogous to
the existing `WorkScheduler` (e.g. `ReminderScheduler`), so tests verify the
computed weekday × time / id set without invoking the plugin. `rearm()` on the
Android background-isolate path never touches the iOS seam.

## Settings UI

- **Entry**: gated as above (manager + Android-or-iOS).
- **Screen** (`notification_settings_screen.dart`): master switch, Times, and
  Days on both platforms. **Documents (per-doctype) section is Android-only**
  (hidden on iOS — the iOS text is generic, so doctype selection has no effect
  there). An **Alert style** control (segmented `Standard` / `Alarm`, reusing
  `SettingsSegmented`) shows on both platforms when the master switch is on.
- **Controller** (`notification_settings_controller.dart`): add an `alarmStyle`
  observable + `setAlarmStyle(...)` (persist only, no re-arm); the
  permission-request seam branches by platform (Android POST_NOTIFICATIONS vs
  iOS Darwin `requestPermissions`); permission denial reverts the master switch
  as today.

## Error handling & edge cases

- **Android**: unchanged — silent failure, catch-all → `failed`, `rearm()` in a
  `finally`, session-expiry copy, per-doctype 403 skip.
- **iOS permission denied**: revert the master switch + warn (same as Android).
- **iOS tz/schedule failure**: best-effort — log and skip; never crash the app.
- **Manager role lost** while enabled: next `rearm()` cancels on both platforms.
- **Old-channel deletion**: idempotent/best-effort; failure is ignored.
- **Style change**: persists immediately; takes effect on the next fired digest
  (Android) / next re-arm's scheduled set (iOS).

## Testing

- **Unit**:
  - `User.isManager` — true for `Stock Manager`/`Purchase Manager`/`System
    Manager`/`sales manager`; false for `Stock User`/empty roles.
  - `DigestScheduler.rearm()` — cancels (schedules nothing) when the user is not
    a manager, on both platform paths.
  - iOS reminder-set computation — the correct (weekday, time) → id set is
    produced for a given prefs combination, via the `ReminderScheduler` seam.
  - `NotificationSettingsController.setAlarmStyle` — persists the style;
    permission-denied reverts and does not enable.
- **Untestable glue** (channel creation, `deleteNotificationChannel`,
  `zonedSchedule`, FLAG_INSISTENT, Darwin details): verified by `flutter
  analyze` + on-device smoke on **both** an Android and an iOS device.
- **Manual smoke**:
  - Android: manager enables → alarm style → forced tick loops sound + vibrates
    until dismissed; standard style → single sound + vibration; non-manager sees
    no Notifications entry.
  - iOS: manager enables → a scheduled reminder fires at the chosen time with
    the app closed, generic text, Time-Sensitive when style=alarm; Documents
    section absent.

## Non-goals

Seconds precision · live counts on iOS · iOS looping/insistent alarm or Critical
Alerts (needs an Apple entitlement) · Android full-screen-intent alarm ·
server-side push · custom bundled alarm sound (uses the device default tone).

## Versioning

New backward-compatible capability (toggle + iOS support + role gate) → **MINOR**
bump at release time per `docs/versioning_conventions.md` (do not bump in this
work; releases are cut separately).
