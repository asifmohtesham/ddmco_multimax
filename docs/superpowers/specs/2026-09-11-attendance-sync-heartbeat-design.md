# Attendance sync heartbeat — design (sub-project #0)

Date: 2026-09-11 · App branch: `claude/attendance-sync-heartbeat` (off `release/play-store` @ `edef2f8a`,
v2.16.0+57) · Agent: `C:\Users\asifm\biotime-erpnext-sync` on KA-IT-SYS6 (`ssh sys6.it.ka`, no git).

## 1. Why

Sub-project #2 (attendance notifications) must not tell an employee "you haven't checked in" when
the real problem is the terminal or the sync agent. An Employee-role user can read only their own
Employee Checkin rows, so their phone cannot tell "I didn't punch" from "punches aren't arriving".
`Shift Type.last_sync_of_checkin` cannot serve as the signal: "Automatically update Last Sync of
Checkin" stays ticked, so HRMS advances it at shift end whether or not punches arrived.

#0 publishes a heartbeat that every signed-in user can read: is the terminal talking to BioTime, and
is the agent successfully delivering punches to ERPNext.

## 2. Facts this design rests on (verified 2026-09-11)

- Agent: `agent/biotime-pull.py`, run by Windows task **"BioTime to ERPNext attendance sync"** as
  `C:\ZKBioTime\Python311\python.exe biotime-pull.py --daemon` (start-in `agent\`, triggers: system
  start-up and logon, runs as `asifm`). The daemon polls BioTime every `FAST_INTERVAL`=5 s inside
  `07:45-08:45, 11:55-12:45, 13:15-14:45, 19:45-20:45`, else `SLOW_INTERVAL`=900 s.
- The agent posts punches with `ERP_TOKEN`, an **HR Manager** user's key, to
  `hrms…employee_checkin.add_log_based_on_employee_field`. `state.json` holds `last_upload_time`
  (watermark), `last_id`, `last_run` — `last_run` is written on every successful cycle, including
  "nothing new"; a failed push exits 1 and leaves it untouched.
- BioTime 8.5 `GET /iclock/api/terminals/` (token auth) returns, per terminal: `sn, alias, state,
  last_activity, push_time, transfer_interval, …`. One terminal: `KA-WH1-BIO1`, SN `AYHO225260052`.
  While online, `last_activity` was 1–8 s old across three samples 40 s apart (`transfer_interval` 1).
- The meaning of BioTime's `state` codes is **not documented** (the Swagger JSON is not served), so
  online/offline is derived from `last_activity` age, not from `state`.
- `agent/register-task.ps1`, `README.md` and `PLAN.md` are **out of date**: they describe a 15-minute
  repeating task running `python biotime-pull.py` with a 10-minute execution limit. Re-running
  `register-task.ps1` would silently replace the live daemon.
- `asif@multimax.cloud` holds System Manager; no DocType named `Attendance Sync Status` exists (404).
- Employee role can read Shift Type but gets 403 on Holiday List; HR Manager reads both.

## 3. ERPNext: `Attendance Sync Status` (custom Single DocType)

Module **HR**, `custom = 1`, `issingle = 1`, **Track Changes off** (frequent saves create no Version
rows). Created by one `POST /api/resource/DocType` with the System Manager key, then read back.

| Field | Type | Source |
|---|---|---|
| `terminal_online` | Check | `last_activity` age ≤ `TERMINAL_ONLINE_MINUTES` (5) |
| `terminal_last_seen` | Datetime | BioTime `last_activity` |
| `terminal_alias` | Data | BioTime `alias` |
| `agent_last_run` | Datetime | `state.json.last_run` (last **successful** cycle) |
| `last_upload` | Datetime | `state.json.last_upload_time` (how far punches have been delivered) |

All fields read-only in the form. Times are naive Asia/Dubai (site time zone; terminal `terminal_tz` 4).

| Role | Permission |
|---|---|
| Employee | Read |
| HR User | Read |
| HR Manager | Read, Write (the agent's key) |
| System Manager | Read, Write |

## 4. Agent change (`agent/biotime-pull.py`)

- New `publish_heartbeat(force=False)`, called from `run_daemon()` after **every** cycle (success,
  "nothing new", or a failed push), wrapped so that any error logs one `heartbeat error: …` line and
  returns — it never touches the watermark, never exits, never retries in a loop.
- It reads BioTime `/iclock/api/terminals/` at most every `TERMINAL_POLL_SECONDS` (60); with several
  terminals it uses the newest `last_activity`. The raw `state` is logged when it changes.
- If BioTime itself cannot be reached, there is no terminal reading: the heartbeat is **not**
  published (no guessed values). Punches cannot sync either, so `agent_last_run` stops advancing and
  the consumer rule (§5) turns "unknown" within 20 minutes — the correct outcome.
- It publishes (`PUT /api/resource/Attendance%20Sync%20Status/Attendance%20Sync%20Status` with
  `ERP_TOKEN`) when `terminal_online` flips, or when `HEARTBEAT_MIN_INTERVAL` (300 s) has passed since
  the last publish (≈ 300 writes/day), or when `force`.
- The publish decision is a pure function (`should_publish(prev_online, online, last_published, now,
  min_interval)`) so it can be asserted without network access.
- New settings are code defaults, overridable in `.env`: `HEARTBEAT_MIN_INTERVAL=300`,
  `TERMINAL_ONLINE_MINUTES=5`, `TERMINAL_POLL_SECONDS=60`. No `.env` change is required.
- New flags: `--heartbeat-once` (force one publish, print the payload — never the token) and
  `--selftest` (asserts on `should_publish`: first run publishes, flip publishes, within-interval
  suppresses, after-interval publishes).
- The existing sync path (`main()`, watermark, push logic) is unchanged.

## 5. Consumer rule (implemented by #2 in the app)

The terminal is "syncing" only when all hold, evaluated on the device clock:

1. `now − agent_last_run ≤ 20 min` (15-minute slow cycle plus margin),
2. `terminal_online == 1`,
3. `now − terminal_last_seen ≤ 20 min`.

If any fails — or the document cannot be read — the app treats the sync as **unknown**: no
"you haven't checked in" reminder is shown, and System Managers get the terminal-quiet alert.

## 6. Deploy and rollback (KA-IT-SYS6)

Each step is confirmed with the user before it runs.

1. Back up `agent\biotime-pull.py` → `agent\biotime-pull.py.bak-2026-09-11` (no git on the machine).
2. Create the DocType (§3) with the System Manager key; read it back (fields, permissions, singles).
3. Edit the agent (§4); run `--selftest`, then `--heartbeat-once`; read the document back.
4. Restart the daemon: `schtasks /End /TN "BioTime to ERPNext attendance sync"` then `/Run`. Confirm
   `daemon start` in `sync.log`, a first heartbeat, and a refreshed document within 5 minutes.
5. Update `README.md` / `PLAN.md`: document the heartbeat, correct "every 15 min" to the daemon, and
   warn not to re-run `register-task.ps1` until it matches the live task.

Rollback: restore the `.bak`, restart the task. The DocType can stay; nothing depends on it until #2.

## 7. Testing

- `--selftest` assertions on `should_publish` (the agent has no test suite; this is its one check).
- Live: `--heartbeat-once` round-trip (BioTime read + ERPNext write with the agent's own key), then
  the restarted daemon refreshing the document.
- Offline behaviour is verified by reasoning over `last_activity` age (the terminal is not taken
  offline deliberately); #2's own tests cover the consumer rule with fixed timestamps.

## 8. Out of scope

- The false-Absent fix (agent maintaining `last_sync_of_checkin`; auto-update unticked) — declined
  for now; may follow once the heartbeat is proven.
- Putting the agent folder under git (recommended, not requested).
- Fixing `register-task.ps1` to match the live daemon task (documented as a warning only).
- Any app change — the app reads the document in #2.

## 9. Follow-ups

- Rotate the System Manager API key used for step 2, and adnan's key shared earlier.
- #2 attendance notifications consume §5.
