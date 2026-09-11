# Attendance backend handoff (for the Attendance monitoring screen)

State of the ERPNext side as of 2026-09-11, written for the attendance screens in this app.
Those screens exist but still assume one shift a day; section 6 lists what has to change.
Everything below was verified against `https://erp.multimax.cloud`.
The sync project itself lives in `C:\Users\asifm\biotime-erpnext-sync` (see its PLAN.md).

**The working day is two shifts, Morning and Afternoon, each with its own check-in and
check-out.** This replaces the single 08:00-20:00 "General" shift from 2026-09-12 on.
Design the screen around (employee, date, shift), not (employee, date).

## 1. Where the data comes from

```
ZKTeco P999 terminal (KA-WH1-BIO1, warehouse entry)
   -> BioTime 9.5 (KA-IT-SYS6, office LAN)
   -> sync agent (daemon: every 5 s around shift starts/ends, else every 15 min)
   -> ERPNext "Employee Checkin" (one row per punch, log_type IN or OUT)
   -> HRMS scheduler, hourly -> "Attendance" (one row per employee per SHIFT per day)
```

- Backend versions: Frappe 15.120 / ERPNext 15.121 / HRMS 15.64.
- The agent posts each punch through the HRMS endpoint `add_log_based_on_employee_field`,
  which maps BioTime `emp_code` to `Employee.attendance_device_id` and rejects duplicate
  employee + timestamp.
- Time zone is Asia/Dubai. All timestamps are naive local strings, `YYYY-MM-DD HH:mm:ss`.
- No n8n, no webhooks. The app reads ERPNext only.

## 2. Master data in place

Working pattern: Sat-Thu 08:00-12:15 and 13:30-20:00; Friday 08:00-12:00 and 14:30-20:00;
Sunday off.

| Shift Type | Start-End | Check-in opens | Check-out closes | Days |
|---|---|---|---|---|
| `Morning` | 08:00-12:15 | 06:00 | 13:00 | Mon-Thu, Sat |
| `Afternoon` | 13:30-20:00 | 13:00 | 22:00 | Mon-Thu, Sat |
| `Morning (Fri)` | 08:00-12:00 | 06:00 | 13:15 | Fri |
| `Afternoon (Fri)` | 14:30-20:00 | 13:15 | 22:00 | Fri |

All four: auto attendance on; Alternating IN/OUT; working hours = first check-in to last
check-out; late entry and early exit flagged after a 15-minute grace; half-day and absent
hour thresholds 0; holiday list `Multimax 2026`; Process Attendance After 2026-09-12.
The check-in/out windows touch but never overlap: every punch from 06:00 to 22:00 belongs to
exactly one shift, and the day splits at **13:00 (Friday 13:15)**.

| Object | Value |
|---|---|
| HR Settings | `allow_multiple_shift_assignments` = 1 (required for two shifts a day) |
| Shift Schedules (weekly, submitted) | `Morning Sat-Thu`, `Afternoon Sat-Thu`, `Morning Friday`, `Afternoon Friday` |
| Shift Schedule Assignments | 64: each of the 16 tracked employees on all four schedules. HRMS's hourly job turns them into **Shift Assignments** (one per employee per shift, from 2026-09-12, rolled 90 days ahead). |
| Tracked employees | 16 with an `attendance_device_id` (`HR-EMP-00001..13`, `00021`, `00022`, `00025`); the 10 others have none and never get attendance rows |
| `General` shift | Retired on the night of 2026-09-11: auto attendance off, removed as Default Shift. Rows dated up to 2026-09-11 keep `shift = General`. |
| Holiday List | `Multimax 2026`, every Sunday, company default and on every shift |
| Company | `Multimax` |
| Device | one terminal, serial `AYHO225260052`, alias `KA-WH1-BIO1` |

## 3. The doctypes to read

### Employee Checkin (raw punches, near real time)

A row from 2026-09-11, exactly as the API returns it (before the change):

```json
{"name":"EMP-CKIN-09-2026-000079","employee_name":"Aslam Gangawali","time":"2026-09-11 07:59:32",
 "log_type":"","shift":"General","shift_start":"2026-09-11 08:00:00","shift_end":"2026-09-11 20:00:00"}
```

From 2026-09-12 the same punch arrives with `"log_type":"IN"`, `"shift":"Morning"` and
`shift_start`/`shift_end` = `08:00:00`/`12:15:00`. (Expected shape; no such row exists yet.)

- **`log_type` is `IN` or `OUT`** for punches the agent sends from 2026-09-11 13:20 on. Earlier
  rows have `""`. The terminal sends the same "Check In" state for every plain tap, so the
  agent assigns the direction:
  - it splits the day at 13:00 (Friday 13:15);
  - within each half, taps alternate IN, OUT, IN…;
  - a second tap within 3 minutes of the previous one repeats its direction (double tap);
  - a state chosen on the terminal (Check-Out, Break, Overtime) wins over the alternation.
- `shift` names the shift HRMS matched the punch to; `shift_start`/`shift_end` are that
  shift's times on that date.
- `attendance` is filled once the scheduler has linked the punch to an Attendance row.

### Attendance (one per employee per shift per day, generated hourly)

Fields the screen will use: `employee`, `employee_name`, `attendance_date`, **`shift`**,
`status` (`Present`, `Absent`, `On Leave`, `Half Day`, `Work From Home`), `working_hours`,
`in_time`, `out_time`, `late_entry` (0/1), `early_exit` (0/1), `leave_type`, `docstatus`
(1 = submitted, only these count).

- **A full working day is two rows**, one Morning (or Morning (Fri)) and one Afternoon.
  Always key and group by `shift`; never assume one row per date.
- A shift's row appears after that shift's check-out window closes (Morning after 13:00 /
  13:15, Afternoon after 22:00) and the hourly job has run.
- **Absent is generated, not observed, and it is per shift**: someone who worked the morning
  but not the afternoon gets Morning = Present and Afternoon = Absent.
- **Missing check-out**: a shift with only a check-in is still `Present`, with `in_time` set,
  `out_time` empty and `working_hours` 0. Show this as "No check-out"; do not treat it as a
  complete shift.
- `late_entry` = 1 when the shift's first punch is later than start + 15 min (08:15, 13:45,
  Friday 14:45). `early_exit` = 1 when the last punch is earlier than end − 15 min.
- The 23 existing rows (up to 2026-09-11) are single-row days with `shift = General`.
  Render them as one full-day row.

### Attendance Sync Status (single doc, health of the pipeline)

```json
{"terminal_online":1,"terminal_last_seen":"2026-09-11 13:29:57","terminal_alias":"KA-WH1-BIO1",
 "agent_last_run":"2026-09-11 13:30:04","last_upload":"2026-09-11 13:30:04"}
```

The agent updates it every 5 minutes and whenever the terminal goes on- or offline. Use it to
tell "nobody punched" from "the terminal or agent is down". If `agent_last_run` is more than
~20 minutes old, or `terminal_online` is 0, show a banner and do not mark people "Not in".

## 4. What "today" should be computed from

Attendance for a shift does not exist until its check-out window closes. The live screen
derives today from Employee Checkin, **per shift**:

1. Which shifts apply today: the employee's Shift Assignments covering today (one Morning-type
   and one Afternoon-type on working days, none on Sunday). Take start/end/grace from those
   Shift Types; don't hardcode times.
2. Put each of today's checkins into Morning if its time is before the split (13:00; Friday
   13:15), else Afternoon.
3. For each (employee, shift):

| Situation | Show |
|---|---|
| Holiday (Sunday or Holiday List) | Holiday |
| Before the shift start + grace, no IN | Not yet in |
| After the shift start + grace, no IN | Not in (absent so far) |
| IN, no OUT, shift still running | In since `<first IN>` (late if after start + grace) |
| IN and OUT | Done `<first IN>`–`<last OUT>`; early exit if the last OUT is before end − grace |
| IN, no OUT, and the shift has ended | **No check-out** |
| No `attendance_device_id` | Not tracked (exclude or grey out) |

For past days read Attendance and trust `status`, `in_time`, `out_time`, `late_entry` and
`early_exit` per `shift`. Rows with an empty `log_type` (before 2026-09-11 13:20) only have
times: treat the first as IN and the last as OUT.

Freshness: during 07:30-08:45, 11:55-12:45, 13:15-14:45 and 19:45-20:45 a punch is in
Employee Checkin within about 10 seconds; at other times within 15 minutes.

## 5. Calls, in this app's terms

The app already logs in with a session cookie (`ApiProvider.loginWithFrappe`) and wraps the
REST API; use the same wrappers. The logged-in user needs the **HR User** role (or HR Manager)
to read Employee Checkin, Attendance and Shift Assignment for everyone; an `Employee`-role user
only sees their own rows. Gate the screen with `DocTypeGuard` on `Attendance`.

Tracked employees (also the row list for the screen):

```
getDocumentList('Employee',
  fields: ['name','employee_name','attendance_device_id','status','department','image'],
  filters: {'status': 'Active', 'attendance_device_id': ['is', 'set']},
  orderBy: 'employee_name asc', limit: 0)
```

Shifts that apply on a date (today, or any day of the history view):

```
getDocumentList('Shift Assignment',
  fields: ['employee','shift_type','start_date','end_date'],
  filters: [['docstatus','=',1], ['status','=','Active'], ['start_date','<=','2026-09-12'],
            ['end_date','>=','2026-09-12']],   // plus rows whose end_date is empty
  limit: 0)
```

Frappe's list filters are ANDed, so fetch open-ended assignments with a second call
(`['end_date','is','not set']`) and merge.

Shift settings, fetched once and cached:

```
getDocumentList('Shift Type',
  fields: ['name','start_time','end_time','late_entry_grace_period','early_exit_grace_period',
           'begin_check_in_before_shift_start_time','allow_check_out_after_shift_end_time','color'],
  filters: {'name': ['in', ['Morning','Afternoon','Morning (Fri)','Afternoon (Fri)']]})
```

Today's punches (one call, then group by employee and shift client-side):

```
getDocumentList('Employee Checkin',
  fields: ['name','employee','employee_name','time','log_type','device_id','shift','attendance'],
  filters: {'time': ['>=', '2026-09-12 00:00:00']},
  orderBy: 'time asc', limit: 0)
```

Attendance for a date range (history / calendar view):

```
getDocumentList('Attendance',
  fields: ['name','employee','employee_name','attendance_date','shift','status','working_hours',
           'in_time','out_time','late_entry','early_exit','leave_type'],
  filters: {'docstatus': 1, 'attendance_date': ['between', ['2026-09-01','2026-09-30']]},
  orderBy: 'attendance_date desc, employee_name asc, in_time asc', limit: 0)
```

Pipeline health:

```
getDocument('Attendance Sync Status', 'Attendance Sync Status')
```

Holidays (to label Sundays and any added public holidays):

```
getDocument('Holiday List', 'Multimax 2026')   -> data.holidays[] {holiday_date, description, weekly_off}
```

Monthly summary via the report runner the app already uses
(`/api/method/frappe.desk.query_report.run`):

```
report_name: 'Monthly Attendance Sheet'
filters: {"month": "09", "year": "2026", "company": "Multimax", "summarized_view": 1}
```

Not yet checked with two shifts: the report counts Attendance rows, so expect a full day to
count twice from 2026-09-12. Verify against the Attendance list before showing its totals.

Realtime option: `FrappeSocket` can subscribe to the `Employee Checkin` doctype room
(`doctype_subscribe`) and refresh today's view on `list_update`; a 60-second poll is an
acceptable first version.

## 6. The existing screens and what two shifts change

Built 2026-09-09 to 2026-09-11 against the single General shift (merged in `c6228378` and
`9fec58c3`):

- `lib/app/data/providers/attendance_provider.dart` and `lib/app/data/models/attendance_models.dart`
  (`ShiftRules`, whose fallback is `General` 08:00-20:00, 15 min grace)
- `lib/app/modules/hr/attendance/`: the monitor (`attendance_controller.dart`,
  `attendance_logic.dart`, `attendance_screen.dart`, `widgets/`) and the month view (`month/`)
- Dashboard: `lib/app/modules/home/home_controller.dart`, `widgets/dashboard_attendance_card.dart`,
  `widgets/my_attendance_card.dart`

What breaks or goes stale with two shifts:

| Where | Today | Needed |
|---|---|---|
| Shift lookup: `attendance_controller.dart:150`, `home_controller.dart:264` | The first employee's `default_shift`, else `General` | `default_shift` is cleared on the night of 2026-09-11. Resolve each employee's shifts per date from Shift Assignment (section 5) and load all four Shift Types. Until then the app falls back to the General Shift Type, which still exists: 08:00-20:00, late after 08:15. Nothing crashes, but afternoons are never judged. |
| Ledger join: `attendance_controller.dart:88`, `home_controller.dart:298` | `{for (r in ledger) r.employee: r}` | Two Attendance rows per employee per day; the map keeps whichever comes last, and the query has no shift tie-break, so a day can show only the Afternoon's Absent. Key by (employee, shift). |
| `deriveDayStatus` in `attendance_logic.dart` | One status per day. A ledger row overrides punches, even today. OUT = last punch when the count is even. | Derive per shift (section 4). The Morning row exists from ~13:00 while the Afternoon is still running, so a ledger row only settles its own shift. Use `log_type` when set; fall back to punch-count parity only for rows with an empty `log_type`. |
| `PunchTimeline` in `widgets/employee_detail_sheet.dart` | IN/OUT by index | Show `log_type`; group punches under Morning and Afternoon. |
| Dashboard cards, `myAttendanceHeadline` | "Shift starts 08:00", late after 08:15 | The current or next shift's times; the Afternoon cut-off is 13:45 (Friday 14:45). |
| Month view | One `ShiftRules` for the whole month | Friday has different times; there are two ledger rows per date. |
| Status set (`AttendanceStatus`) | No "missing check-out" state | Add **No check-out** (IN with no OUT after the shift ended), with its own colour; it is the case HR has to chase. |
| Tests: `test/unit/attendance_logic_test.dart`, `test/widget/*attendance*` | Single shift | Add two-shift, Friday and no-check-out cases. |

Keep the existing conventions: `AppColors` ramp for status colours (x700 light, x300 dark),
`Scrollbar`, bottom-inset padding, and an end-of-list marker with count summaries (per shift),
never a sum of anything numeric.

## 7. Known gaps the screen should tolerate

- **Staff do not check out yet.** On 2026-09-11 all 7 people who checked in had no punch at
  the 12:00 break, with the terminal online. Until four taps a day are enforced, expect
  "No check-out" on most shifts. That is real data; don't hide it.
- The terminal's default key still says Check-In all day. Switching it to Check-Out on a
  timetable has to be set on the device (Personalize > Punch State Options / Shortcut Key
  Mappings). The agent's IN/OUT labels work either way.
- Shift Assignments from 2026-09-12 appear only after HRMS's hourly job runs. If today has no
  Shift Assignment for someone, fall back to the weekday rule in section 2 and log it.
- Five people exist in BioTime but not in ERPNext (Jaffer Potey, Ashal, Hunain, Khalid,
  Ehtisham); the agent drops their punches as "unmatched". The ten ERPNext employees without a
  device ID are not on any shift and get no attendance.
- Tanveer's mapping (BioTime "Tanveer Mulla" to ERPNext "Tanveer Shaikh") is a first-name match.
- URL-encode spaces in resource paths (`Employee%20Checkin`); Dio does this already, curl does not.
