# Attendance Sync Heartbeat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Tasks 2–4 change production (ERPNext and the office sync PC): the controller runs them itself, stopping for the user's explicit go-ahead before every step marked ⚠️. Never hand them to a subagent.**

**Goal:** The BioTime sync agent publishes terminal and agent health to a new ERPNext Single DocType, `Attendance Sync Status`, that every signed-in user can read.

**Architecture:** A custom Single DocType (module HR, Track Changes off) is created once by REST with a System Manager key. The agent's daemon loop gains `publish_heartbeat()`, which reads BioTime's terminals API at most every 60 s and `PUT`s the document when the terminal flips online/offline or every 300 s, using the agent's existing HR Manager `ERP_TOKEN`. Heartbeat errors are logged and swallowed; the sync path is untouched.

**Tech Stack:** Python 3.10+ stdlib only (agent runs BioTime's bundled `C:\ZKBioTime\Python311\python.exe`; local checks use Python 3.10.11), Frappe v15 REST, OpenSSH (`ssh`/`scp`) to KA-IT-SYS6.

**Spec:** `docs/superpowers/specs/2026-09-11-attendance-sync-heartbeat-design.md`

## Global Constraints

- **Never print, log, commit or write to any file** the values of `BIOTIME_TOKEN`, `ERP_TOKEN`, the agent `.env`, or the System Manager key. When reading remote files, redact lines matching `key|secret|password|passwd|pwd|token`.
- Python code must run on **3.10 and 3.11** and use the **standard library only** (the agent has no virtualenv).
- **Do not change** `main()`, the watermark logic, `push_to_erpnext`, or `push_to_n8n`.
- DocType name exactly `Attendance Sync Status`; fields exactly `terminal_online` (Check), `terminal_last_seen` (Datetime), `terminal_alias` (Data), `agent_last_run` (Datetime), `last_upload` (Datetime).
- Defaults exactly: `HEARTBEAT_MIN_INTERVAL=300`, `TERMINAL_ONLINE_MINUTES=5`, `TERMINAL_POLL_SECONDS=60` (overridable in `.env`, no `.env` change required).
- **Do not re-run `agent\register-task.ps1`** — it would replace the live daemon task with the old 15-minute mode.
- Remote shell is Windows `cmd`: quote the whole remote command as `'cmd /c "..."'`; run Python by piping a script on stdin to `C:\ZKBioTime\Python311\python.exe -`. Always pass `-o BatchMode=yes` to `ssh`/`scp`.
- Paths: remote agent `C:\Users\asifm\biotime-erpnext-sync\agent\`; local working folder `C:/Users/asifm/StudioProjects/agent-heartbeat/` (baseline copy `biotime-pull.py.baseline`, sha256 prefix `4eb13a57566a860c`, 310 lines, 13,183 bytes).
- The agent folder has no git: its "commit" is the `.bak` backup plus the recorded sha256 of the deployed file.

---

## File Structure

| File | Where | Responsibility | Task |
|---|---|---|---|
| `biotime-pull.py` | local work folder → deployed to `agent\` | + heartbeat config, `is_online`, `should_publish`, `terminal_status`, `publish_heartbeat`, `selftest`, `--selftest` / `--heartbeat-once` flags, call in `run_daemon` | 1, 3 |
| DocType `Attendance Sync Status` | ERPNext | the heartbeat record | 2 |
| `biotime-pull.py.bak-2026-09-11` | `agent\` | rollback copy | 3 |
| `README.md`, `PLAN.md` | agent repo root | document heartbeat, daemon mode, register-task warning | 4 |

---

### Task 1: Heartbeat code in the local working copy

**Files:**
- Create: `C:/Users/asifm/StudioProjects/agent-heartbeat/biotime-pull.py` (copy of the baseline, then edited)
- Test: built-in `--selftest` flag in the same file

**Interfaces:**
- Produces (used by Task 3):
  - `is_online(last_activity: str, now: datetime, minutes: int) -> bool`
  - `should_publish(prev_online: bool | None, online: bool, last_published: datetime | None, now: datetime, min_interval: int) -> bool`
  - `terminal_status(now: datetime) -> tuple[bool, str, str, object] | None` — `(online, last_activity, alias, state)`
  - `publish_heartbeat(force: bool = False) -> dict | None` — the payload it sent, or `None`
  - CLI: `--selftest` (exit 0 and print `selftest ok`), `--heartbeat-once` (print payload JSON; exit 0 if sent, 1 if not)

- [ ] **Step 1: Create the working copy**

```bash
cd "C:/Users/asifm/StudioProjects/agent-heartbeat" && cp biotime-pull.py.baseline biotime-pull.py && wc -l biotime-pull.py
```
Expected: `310 biotime-pull.py`

- [ ] **Step 2: Write the failing self-test**

In `biotime-pull.py`, directly **above** the line `def _in_fast_window(now):`, insert:

```python
# ---------------------------------------------------------------- self-test

def selftest():
    """Pure checks of the heartbeat decisions; no network, no tokens needed."""
    t0 = datetime(2026, 9, 11, 8, 0, 0)
    # online = last contact no older than the threshold
    assert is_online("2026-09-11 07:59:56", t0, 5)
    assert is_online("2026-09-11 07:55:00", t0, 5)
    assert not is_online("2026-09-11 07:54:59", t0, 5)
    # publish: first reading, flips, and once the interval has elapsed
    assert should_publish(None, True, None, t0, 300)
    assert not should_publish(True, True, t0, t0 + timedelta(seconds=299), 300)
    assert should_publish(True, True, t0, t0 + timedelta(seconds=300), 300)
    assert should_publish(True, False, t0, t0 + timedelta(seconds=5), 300)
    assert should_publish(False, True, t0, t0 + timedelta(seconds=5), 300)
    print("selftest ok")


```

Replace the whole `if __name__ == "__main__":` block at the end of the file:

```python
if __name__ == "__main__":
    if "--daemon" in sys.argv:
        run_daemon()
    else:
        main()
```

with:

```python
if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    elif "--heartbeat-once" in sys.argv:
        sent = publish_heartbeat(force=True)
        print(json.dumps(sent, indent=2))
        sys.exit(0 if sent else 1)
    elif "--daemon" in sys.argv:
        run_daemon()
    else:
        main()
```

- [ ] **Step 3: Run the self-test to verify it fails**

Run: `cd "C:/Users/asifm/StudioProjects/agent-heartbeat" && python biotime-pull.py --selftest`
Expected: FAIL with `NameError: name 'is_online' is not defined`

- [ ] **Step 4: Add the heartbeat settings**

Directly **below** the line `SLOW_INTERVAL = int(os.environ.get("SLOW_INTERVAL", "900"))`, insert:

```python
# heartbeat -> ERPNext Single DocType "Attendance Sync Status", read by the Multimax app to tell a
# quiet terminal or agent from a missed punch. Published on online/offline flips, otherwise at most
# every HEARTBEAT_MIN_INTERVAL s; BioTime's terminal list is read at most every TERMINAL_POLL_SECONDS.
HEARTBEAT_URL = ERP_URL + "/api/resource/Attendance%20Sync%20Status/Attendance%20Sync%20Status"
HEARTBEAT_MIN_INTERVAL = int(os.environ.get("HEARTBEAT_MIN_INTERVAL", "300"))
TERMINAL_ONLINE_MINUTES = int(os.environ.get("TERMINAL_ONLINE_MINUTES", "5"))
TERMINAL_POLL_SECONDS = int(os.environ.get("TERMINAL_POLL_SECONDS", "60"))
```

- [ ] **Step 5: Add the heartbeat functions**

Directly **above** the `# ---------------------------------------------------------------- self-test` line added in Step 2, insert:

```python
# ---------------------------------------------------------------- heartbeat

def is_online(last_activity, now, minutes):
    """BioTime's state codes are undocumented, so online = last terminal contact is recent."""
    return now - datetime.strptime(last_activity, FMT) <= timedelta(minutes=minutes)


def should_publish(prev_online, online, last_published, now, min_interval):
    """Publish on the first reading, on an online/offline flip, or once min_interval s have passed."""
    if prev_online is None or last_published is None:
        return True
    if online != prev_online:
        return True
    return (now - last_published).total_seconds() >= min_interval


def terminal_status(now):
    """(online, last_activity, alias, state) of the most recently active terminal, or None."""
    url = f"{BIOTIME_URL}/iclock/api/terminals/?page_size=50"
    rows = get_json(url, {"Authorization": f"Token {BIOTIME_TOKEN}"}, retries=1).get("data", [])
    rows = [r for r in rows if r.get("last_activity")]
    if not rows:
        return None
    t = max(rows, key=lambda r: r["last_activity"])
    online = is_online(t["last_activity"], now, TERMINAL_ONLINE_MINUTES)
    return online, t["last_activity"], t.get("alias") or t.get("sn") or "", t.get("state")


# last terminal poll, its reading, last publish time/online value, last logged BioTime state
_hb = {"polled": None, "status": None, "published": None, "online": None, "state": None}


def publish_heartbeat(force=False):
    """Push terminal + agent health to ERPNext. Never raises: the sync must not depend on it."""
    try:
        now = datetime.now()
        if force or _hb["polled"] is None or (now - _hb["polled"]).total_seconds() >= TERMINAL_POLL_SECONDS:
            _hb["polled"], _hb["status"] = now, None  # a failed poll also waits a full interval
            _hb["status"] = terminal_status(now)
        status = _hb["status"]
        if status is None:
            return None  # BioTime unreachable or no terminal: publish nothing rather than guess
        online, last_seen, alias, state = status
        if state != _hb["state"]:
            log(f"heartbeat: terminal {alias} state {state!r}")
            _hb["state"] = state
        if not (force or should_publish(_hb["online"], online, _hb["published"], now,
                                        HEARTBEAT_MIN_INTERVAL)):
            return None
        st = json.loads(STATE_FILE.read_text()) if STATE_FILE.exists() else {}
        payload = {
            "terminal_online": 1 if online else 0,
            "terminal_last_seen": last_seen,
            "terminal_alias": alias,
            "agent_last_run": (st.get("last_run") or "").replace("T", " ") or None,
            "last_upload": st.get("last_upload_time"),
        }
        req = urllib.request.Request(
            HEARTBEAT_URL, data=json.dumps(payload).encode(), method="PUT",
            headers={"Authorization": f"token {ERP_TOKEN}", "Content-Type": "application/json",
                     "Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=30):
            pass
        _hb["published"], _hb["online"] = now, online
        return payload
    except Exception as e:  # heartbeat must never break the sync loop
        log(f"heartbeat error: {e}")
        return None


```

- [ ] **Step 6: Call it from the daemon loop**

In `run_daemon()`, replace:

```python
        except Exception as e:
            log(f"cycle error: {e}")
        time.sleep(FAST_INTERVAL if fast else SLOW_INTERVAL)
```

with:

```python
        except Exception as e:
            log(f"cycle error: {e}")
        publish_heartbeat()
        time.sleep(FAST_INTERVAL if fast else SLOW_INTERVAL)
```

- [ ] **Step 7: Run the self-test to verify it passes**

Run: `cd "C:/Users/asifm/StudioProjects/agent-heartbeat" && python -m py_compile biotime-pull.py && python biotime-pull.py --selftest`
Expected: `selftest ok`, exit 0.

- [ ] **Step 8: Confirm the sync path is unchanged**

Run:
```bash
cd "C:/Users/asifm/StudioProjects/agent-heartbeat" && diff biotime-pull.py.baseline biotime-pull.py | grep '^<'; sha256sum biotime-pull.py
```
Expected: exactly one removed line, `<     if "--daemon" in sys.argv:` (it became an `elif` in the new `__main__` block); every other change is an addition. Nothing inside `main()`, `push_to_erpnext`, `push_to_n8n`, `pull_uploaded_between` or the watermark code changes. Record the printed sha256 for Task 3.

(No commit: the agent folder has no git. The working copy stays in the local folder until Task 3 deploys it.)

---

### Task 2: Create the `Attendance Sync Status` DocType ⚠️ (production)

**Files:** none (ERPNext metadata via REST)

**Interfaces:**
- Produces: `GET/PUT https://erp.multimax.cloud/api/resource/Attendance%20Sync%20Status/Attendance%20Sync%20Status` with the five fields; Employee/HR User read, HR Manager/System Manager read+write.

- [ ] **Step 1: ⚠️ Ask the user to confirm the create call** (show the payload below; the System Manager key comes from the user in chat and is held only in a shell variable).

- [ ] **Step 2: Create it**

```bash
K='<system manager key:secret from the user>'
curl -s -X POST -H "Authorization: token $K" -H "Content-Type: application/json" \
  https://erp.multimax.cloud/api/resource/DocType -d @- <<'JSON' | head -c 300
{
  "doctype": "DocType",
  "name": "Attendance Sync Status",
  "module": "HR",
  "custom": 1,
  "issingle": 1,
  "track_changes": 0,
  "description": "Heartbeat written by the BioTime sync agent on KA-IT-SYS6. Read by the Multimax app to tell a quiet terminal or agent from a missed punch.",
  "fields": [
    {"fieldname": "terminal_online", "fieldtype": "Check", "label": "Terminal Online", "read_only": 1},
    {"fieldname": "terminal_last_seen", "fieldtype": "Datetime", "label": "Terminal Last Seen", "read_only": 1},
    {"fieldname": "terminal_alias", "fieldtype": "Data", "label": "Terminal", "read_only": 1},
    {"fieldname": "agent_last_run", "fieldtype": "Datetime", "label": "Agent Last Successful Run", "read_only": 1},
    {"fieldname": "last_upload", "fieldtype": "Datetime", "label": "Punches Uploaded Up To", "read_only": 1}
  ],
  "permissions": [
    {"role": "Employee", "read": 1},
    {"role": "HR User", "read": 1},
    {"role": "HR Manager", "read": 1, "write": 1},
    {"role": "System Manager", "read": 1, "write": 1}
  ]
}
JSON
```
Expected: JSON starting `{"data":{"name":"Attendance Sync Status"` (HTTP 200).

- [ ] **Step 3: Read it back**

```bash
curl -s -H "Authorization: token $K" "https://erp.multimax.cloud/api/resource/DocType/Attendance%20Sync%20Status" \
  | python -c "import json,sys; d=json.load(sys.stdin)['data']; print(d['issingle'], d['custom'], d['module'], d['track_changes']); print([ (f['fieldname'], f['fieldtype']) for f in d['fields']]); print([ (p['role'], p.get('read'), p.get('write')) for p in d['permissions']])"
curl -s -o /dev/null -w "record: HTTP %{http_code}\n" -H "Authorization: token $K" "https://erp.multimax.cloud/api/resource/Attendance%20Sync%20Status/Attendance%20Sync%20Status"
```
Expected:
```
1 1 HR 0
[('terminal_online', 'Check'), ('terminal_last_seen', 'Datetime'), ('terminal_alias', 'Data'), ('agent_last_run', 'Datetime'), ('last_upload', 'Datetime')]
[('Employee', 1, 0), ('HR User', 1, 0), ('HR Manager', 1, 1), ('System Manager', 1, 1)]
record: HTTP 200
```

- [ ] **Step 4: Tell the user to rotate the System Manager key (`asif@multimax.cloud`) and adnan's API key, both of which were pasted into chat.**

---

### Task 3: Deploy the agent change on KA-IT-SYS6 ⚠️ (production)

**Files:**
- Create (remote): `agent\biotime-pull.py.bak-2026-09-11`
- Modify (remote): `agent\biotime-pull.py` ← local working copy from Task 1

**Interfaces:**
- Consumes: Task 1's file and CLI flags; Task 2's DocType.

- [ ] **Step 1: Check the live file still matches the baseline**

```bash
ssh -o BatchMode=yes sys6.it.ka 'cmd /c "certutil -hashfile C:\Users\asifm\biotime-erpnext-sync\agent\biotime-pull.py SHA256"' 2>&1 | tr -d '\r' | grep -E '^[0-9a-f ]{64,}$' | tr -d ' ' ; sha256sum "C:/Users/asifm/StudioProjects/agent-heartbeat/biotime-pull.py.baseline" | cut -d' ' -f1
```
Expected: the two hashes are identical. If not, **stop** — someone changed the live agent; re-baseline and redo Task 1 on top of it.

- [ ] **Step 2: ⚠️ Confirm with the user, then back up the live file**

```bash
ssh -o BatchMode=yes sys6.it.ka 'cmd /c "copy /Y C:\Users\asifm\biotime-erpnext-sync\agent\biotime-pull.py C:\Users\asifm\biotime-erpnext-sync\agent\biotime-pull.py.bak-2026-09-11"'
```
Expected: `1 file(s) copied.`

- [ ] **Step 3: ⚠️ Upload the new file**

```bash
scp -o BatchMode=yes "C:/Users/asifm/StudioProjects/agent-heartbeat/biotime-pull.py" sys6.it.ka:"C:/Users/asifm/biotime-erpnext-sync/agent/biotime-pull.py"
ssh -o BatchMode=yes sys6.it.ka 'cmd /c "certutil -hashfile C:\Users\asifm\biotime-erpnext-sync\agent\biotime-pull.py SHA256"' 2>&1 | tr -d '\r' | grep -E '^[0-9a-f ]{64,}$' | tr -d ' '
```
Expected: the remote hash equals the sha256 recorded in Task 1 Step 8. The running daemon keeps its old code in memory until Step 6.

- [ ] **Step 4: Self-test and one forced heartbeat with the agent's own interpreter and keys**

```bash
ssh -o BatchMode=yes sys6.it.ka 'cmd /c "cd /d C:\Users\asifm\biotime-erpnext-sync\agent && C:\ZKBioTime\Python311\python.exe biotime-pull.py --selftest && C:\ZKBioTime\Python311\python.exe biotime-pull.py --heartbeat-once"'
```
Expected: `selftest ok`, then a JSON payload with `"terminal_online": 1`, `terminal_last_seen` within the last minute, `"terminal_alias": "KA-WH1-BIO1"`, and non-null `agent_last_run` / `last_upload`; exit 0. If it prints `null`, read the last `heartbeat error:` line of `sync.log` (redacted) and fix before continuing.

- [ ] **Step 5: Read the record back with the System Manager key**

```bash
curl -s -H "Authorization: token $K" "https://erp.multimax.cloud/api/resource/Attendance%20Sync%20Status/Attendance%20Sync%20Status" \
  | python -c "import json,sys; d=json.load(sys.stdin)['data']; print({k: d.get(k) for k in ('terminal_online','terminal_last_seen','terminal_alias','agent_last_run','last_upload')})"
```
Expected: the same values as Step 4's payload. **If the fields are empty**, the server ignored writes to `read_only` fields: set `read_only: 0` on the five fields (`PUT /api/resource/DocType/Attendance%20Sync%20Status` with the full `fields` list from Task 2 minus `read_only`), then repeat Step 4–5.

- [ ] **Step 6: ⚠️ Confirm with the user, then restart the daemon**

```bash
ssh -o BatchMode=yes sys6.it.ka "powershell -NoProfile -Command \"Stop-ScheduledTask -TaskName 'BioTime to ERPNext attendance sync'; Start-Sleep 3; Start-ScheduledTask -TaskName 'BioTime to ERPNext attendance sync'; Start-Sleep 5; Get-ScheduledTask -TaskName 'BioTime to ERPNext attendance sync' | Select-Object -ExpandProperty State\""
```
Expected: `Running`.

- [ ] **Step 7: Verify the live daemon publishes**

```bash
ssh -o BatchMode=yes sys6.it.ka 'cmd /c "powershell -NoProfile -Command Get-Content -Tail 15 C:\Users\asifm\biotime-erpnext-sync\agent\sync.log"'
```
Expected: a fresh `daemon start: …` line, normal `delta:` / `nothing new` cycles, a `heartbeat: terminal KA-WH1-BIO1 state '1'` line, and **no** `heartbeat error`. Then, 6 minutes later, repeat Task 3 Step 5: `terminal_last_seen` and `agent_last_run` must have advanced.

- [ ] **Step 8: Rollback (only if Step 4–7 fail and cannot be fixed)**

```bash
ssh -o BatchMode=yes sys6.it.ka 'cmd /c "copy /Y C:\Users\asifm\biotime-erpnext-sync\agent\biotime-pull.py.bak-2026-09-11 C:\Users\asifm\biotime-erpnext-sync\agent\biotime-pull.py"'
```
then Step 6's restart command. The DocType can stay.

---

### Task 4: Update the agent's README and PLAN

**Files:**
- Modify (remote, via local copies): `C:\Users\asifm\biotime-erpnext-sync\README.md`, `C:\Users\asifm\biotime-erpnext-sync\PLAN.md`

- [ ] **Step 1: Pull local copies**

```bash
cd "C:/Users/asifm/StudioProjects/agent-heartbeat" && scp -o BatchMode=yes sys6.it.ka:"C:/Users/asifm/biotime-erpnext-sync/README.md" README.md && scp -o BatchMode=yes sys6.it.ka:"C:/Users/asifm/biotime-erpnext-sync/PLAN.md" PLAN.md && cp README.md README.md.orig && cp PLAN.md PLAN.md.orig
```

- [ ] **Step 2: Edit README.md**

Replace the sentence beginning `How it works: \`agent/biotime-pull.py\` runs every 15 minutes on a machine inside the office` … through `Only outbound HTTPS leaves the LAN.` with:

```markdown
How it works: `agent/biotime-pull.py --daemon` runs permanently on a machine inside the office
LAN (BioTime at 10.255.254.62 is only reachable there), started by the Windows task at start-up
and logon. It polls every 5 s inside the shift windows (07:45-08:45, 11:55-12:45, 13:15-14:45,
19:45-20:45) and every 15 minutes otherwise, asks BioTime for punches uploaded since the last
run, posts each one to ERPNext's HRMS endpoint `add_log_based_on_employee_field`, and records
the new watermark. ERPNext maps the device ID to the Employee, rejects duplicates, and its
hourly scheduler turns the checkins into Attendance through the "General" Shift Type. Only
outbound HTTPS leaves the LAN.

**Heartbeat.** After every cycle the agent reads the terminal list from BioTime (at most once a
minute) and updates the ERPNext Single DocType **Attendance Sync Status** (`terminal_online`,
`terminal_last_seen`, `terminal_alias`, `agent_last_run`, `last_upload`) when the terminal goes
online/offline, or every 5 minutes. Online means BioTime heard from the terminal in the last 5
minutes. The Multimax app reads this to tell a quiet terminal from a missed punch. Heartbeat
errors are logged as `heartbeat error:` and never affect the sync. Check it with
`python agent/biotime-pull.py --heartbeat-once`; `--selftest` checks the decision logic offline.
```

Directly **above** the line `Register the 15-minute task from an elevated PowerShell (task name`, insert:

```markdown
> **Warning (2026-09-11):** the live task was changed by hand to run
> `C:\ZKBioTime\Python311\python.exe biotime-pull.py --daemon` at start-up and logon.
> `register-task.ps1` still registers the old 15-minute, 10-minute-limit task. Do **not** re-run it
> until it is updated, or the daemon (and the heartbeat) will be replaced.
```

- [ ] **Step 3: Edit PLAN.md**

In the status table, replace the row starting `| LAN agent | **Scheduled** |` with:

```markdown
| LAN agent | **Running (daemon)** | `agent/biotime-pull.py --daemon` runs as Windows task "BioTime to ERPNext attendance sync" on this PC (WireGuard 100.111.57.218), started at start-up and logon; 5 s polls in the shift windows, else 15 min. `.env` holds the tokens. |
| Sync heartbeat | **Done 2026-09-11** | The agent updates ERPNext Single DocType "Attendance Sync Status" (terminal online/last seen, agent last run, upload watermark) on online/offline flips or every 5 min; read by the Multimax app. |
```

and replace the row starting `| Terminal health | **Attention** |` with:

```markdown
| Terminal health | OK (2026-09-11) | `KA-WH1-BIO1` is online again (BioTime `last_activity` a few seconds old); watch "Attendance Sync Status". |
```

- [ ] **Step 4: ⚠️ Confirm with the user, then upload**

```bash
cd "C:/Users/asifm/StudioProjects/agent-heartbeat" && diff README.md.orig README.md | head -40; diff PLAN.md.orig PLAN.md | head -20
scp -o BatchMode=yes README.md sys6.it.ka:"C:/Users/asifm/biotime-erpnext-sync/README.md" && scp -o BatchMode=yes PLAN.md sys6.it.ka:"C:/Users/asifm/biotime-erpnext-sync/PLAN.md"
```
Expected: diffs show only the edits above; both uploads succeed.

- [ ] **Step 5: Record completion in the app repo**

Append to `docs/superpowers/specs/2026-09-11-attendance-sync-heartbeat-design.md` a final line
`Deployed 2026-09-11: agent sha256 <hash from Task 1 Step 8>; backup agent\biotime-pull.py.bak-2026-09-11.`
and commit:

```bash
git branch --show-current   # must print claude/attendance-sync-heartbeat
git add docs/superpowers/specs/2026-09-11-attendance-sync-heartbeat-design.md
git commit -m "docs(spec): record attendance sync heartbeat deployment

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```
