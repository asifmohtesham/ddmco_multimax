# Attendance backend handoff (for the Attendance screens)

How the ERPNext side records attendance, written for the attendance screens in this app.
From **Monday 2026-11-30** attendance is **daily clocked hours**: one Attendance row per
employee per day, with the taps paired into hours and checked against the employee's
expected hours. Days before that keep the two-shift model (Morning / Afternoon, section 7),
and the app still displays them.

Source of truth for the backend design: `C:\Users\asifm\biotime-erpnext-sync\docs\
CLOCKED-HOURS-DESIGN.md` (sections 3 and 7.4) and the live reference
`docs\BIOTIME-ERPNEXT-REFERENCE.md` in the same repository. The Server Script that stamps the
hours is `clocked-hours\attendance-stamp.server-script.py`; its worked examples are in
`clocked-hours\test-attendance-stamp.py`, and `test/unit/attendance_logic_test.dart` checks the
app against the same examples.

## 1. Where the data comes from

```
ZKTeco P999 terminal (warehouse entry)        every tap is a time stamp; no IN/OUT key
   -> BioTime 9.5 (KA-IT-SYS6)
   -> sync agent (Windows service BioTimeErpSync)   forwards each punch, log_type EMPTY
   -> ERPNext "Employee Checkin" (one row per tap)
   -> HRMS hourly job, ~22:00-23:00 -> "Attendance" (ONE row per employee per DAY)
   -> Server Script (Attendance, Before Submit) stamps taps, missing punch, net, expected,
      shortfall on that row
```

- Backend: ERPNext / HRMS **16.53.2** on `erp.multimax.cloud`. Time zone Asia/Dubai; all
  timestamps are naive local strings `YYYY-MM-DD HH:mm:ss`.
- The app reads ERPNext only. It never writes attendance.

## 2. Master data

Days of the week do not vary: Monday to Saturday, Sunday off.

| Shift Type (pattern) | Who | Start-End | Day window | Midday break Mon-Thu, Sat | Friday break | Expected |
|---|---|---|---|---|---|---|
| `Standard` | everyone not named below | 08:00-20:00 | 06:00-22:00 | 12:15-13:30 | 12:00-14:30 | 10 h |
| `Late Start` | Esa Shabandri (HR-EMP-00025) | 10:00-18:00 | 06:00-22:00 | none | 12:00-14:30 | 8 h |
| `Early Finish` | Tajammul Ahmed, Mohammed Fatheen VM (HR-EMP-00026/27) | 08:00-19:00 | 06:00-22:00 | 12:15-13:30 | 12:00-14:30 | 8 h |

All three: auto attendance on; **Alternating entries as IN and OUT**; working hours =
**Every Valid Check-in and Check-out** (sum of pairs); late entry after a 15-minute grace;
early exit off; half-day / absent thresholds 0; **Holiday List empty** (section 4).

- **Who is on which pattern: `Employee.default_shift`.** No Shift Schedules, no Shift
  Assignments. A dated Shift Assignment exists only where someone is on another pattern for a
  period; while Active it overrides the default.
- **Custom fields on Shift Type** (the pattern's definition):

| Field | Type | Meaning |
|---|---|---|
| `custom_expected_hours` | Float | minimum hours per working day; empty/0 = not a clocked pattern |
| `custom_expected_hours_friday` | Float | Friday's figure; empty = same as the other days |
| `custom_break_start` / `custom_break_end` | Time | weekday break; empty = no break |
| `custom_break_start_friday` / `custom_break_end_friday` | Time | Friday break; when either is empty Friday uses the weekday break |

- **Custom fields on Attendance** (stamped by the Server Script, read-only):

| Field | Type | Meaning |
|---|---|---|
| `custom_punch_count` | Int | taps counted for the day |
| `custom_missing_punch` | Check | odd number of taps |
| `custom_net_hours` | Float | paired hours less any time inside the break window |
| `custom_expected_hours` | Float | the pattern's expected hours for that weekday, as they stood that day |
| `custom_shortfall_hours` | Float | expected − net, never below 0; 0 on Absent |

  The script leaves a row of a Shift Type with no expected hours alone (all five fields stay
  empty / 0), so the old Morning / Afternoon rows are never stamped.

## 3. How one day becomes hours (design 3.4)

1. All of an employee's taps between 06:00 and 22:00 belong to that day. A tap outside the
   window is stored but not counted.
2. In time order, the 1st and 2nd tap are a pair, the 3rd and 4th, and so on. `log_type` is
   ignored (it is empty on new punches anyway).
3. **Net hours** = for each pair, its length less any part inside that day's break window.
   Break time never counts, tapped or not. Time before the pattern's start or after its end
   counts. Each pair is rounded to 2 decimals, as HRMS rounds `working_hours`.
4. An unpaired last tap adds nothing; the day is a **Missing punch**.
5. **Expected hours are a minimum**: only a shortfall is reported, never overtime.
   Shortfall applies to Present / Half Day (a late day is Present in HRMS).
6. Late = first tap after start + 15 min (08:15; Late Start 10:15).
7. A day with no taps is marked Absent the following night; Sundays are skipped.

| Taps (Standard, Monday) | Net | Against 10 h | Flag |
|---|---|---|---|
| 08:00, 12:15, 13:30, 20:00 | 10.75 | met | |
| 08:00, 20:00 | 10.75 | met | |
| 08:00, 12:15, 13:30, 18:00 | 8.75 | short 1.25 | |
| 08:00, 13:30, 20:00 | 4.25 | short 5.75 | Missing punch |
| Standard Friday 08:00, 20:00 | 9.50 | short 0.50 | |
| Late Start Friday 10:00, 18:00 | 5.50 | short 2.50 | |

## 4. Holidays

The clocked patterns leave **Holiday List empty**. HRMS 16 then resolves the list per date
from the submitted **Holiday List Assignments**: the latest one starting on or before the
date, the employee's own first, then the company's. Today: `Multimax 2026` from 2026-01-01
and `Multimax 2027` from 2027-01-01, company `Multimax`. (Since 2026-11-16 the four old Shift
Types also have an empty Holiday List.)

The app (`AttendanceProvider.fetchHolidays`):

- a Shift Type that names a list: that Holiday List, as before;
- no list: the company's Holiday List Assignments for the range (fields `applicable_for` =
  Company, `assigned_to` = the employees' `company`, `holiday_list`, `from_date`,
  `docstatus` = 1), each list applying from its `from_date` until the next one starts
  (`holidayListPeriods`), then those lists' dates. Employee-level assignments are not read:
  one set of holidays serves the whole list screen;
- the **Employee role** cannot read Holiday List or Holiday List Assignment (403): both paths
  fall back to HRMS's own calendar for the logged-in employee,
  `hrms.api.get_attendance_calendar_events`, for the same range.

Ranges: the list screen reads last year and this year; the Dashboard this year; the month
screen the month on view.

## 5. Calls, in this app's terms

The logged-in user needs **HR User** (or HR Manager) to read everyone's Employee Checkin and
Attendance; the Employee role sees only its own rows. The screen is gated on `Attendance`.

```
getDocumentList('Employee',
  fields: ['name','employee_name','attendance_device_id','default_shift','status',
           'department','image','company'],
  filters: {'status': 'Active'}, limit: 0)

getDocumentList('Shift Type',            // every employee's default_shift, plus any named by
  fields: [...standard fields, 'holiday_list',  //  an Attendance row or Shift Assignment
           'custom_expected_hours','custom_expected_hours_friday',
           'custom_break_start','custom_break_end',
           'custom_break_start_friday','custom_break_end_friday'],
  filters: {'name': ['in', names]})

getDocumentList('Employee Checkin',
  fields: ['name','employee','employee_name','time','log_type','device_id','shift','attendance'],
  filters: {'time': ['between', [day 00:00:00, day 23:59:59]]}, orderBy: 'time asc')

getDocumentList('Attendance',
  fields: ['name','employee','employee_name','attendance_date','status','working_hours',
           'in_time','out_time','late_entry','early_exit','shift','leave_type',
           'custom_punch_count','custom_missing_punch','custom_net_hours',
           'custom_expected_hours','custom_shortfall_hours'],
  filters: {'docstatus': 1, 'attendance_date': ['between', [from, to]]})

getDocumentList('Shift Assignment', ...)  // still read: overrides, and the two-shift history
getDocumentList('Holiday List Assignment', ...)   // section 4
getDocument('Attendance Sync Status', 'Attendance Sync Status')   // pipeline health
```

**A site without the custom fields.** Frappe refuses a list request that names an unknown
field. `AttendanceProvider._listWithOptional` (and the same helper in
`AttendanceNotifyService`) retries an error response without the `custom_*` fields; when that
works the fields are remembered as absent for the session. A connection error is not
retried. With no fields: every Shift Type has `isClocked == false`, every Attendance row
`isClocked == false`, and the screens behave exactly as before this change.

## 6. What the screens show

`attendance_logic.dart` is the single place the rules live.

| Day | Source | Shown |
|---|---|---|
| Today, clocked pattern, no Attendance row yet | the day's punches, `clockedDay` | Present / Late from the first tap; **net so far** against expected ("Net 4h 15m of 10h"). An odd count is normal while the day runs (the person is in). |
| Today after the window closes (22:00), no row yet | the punches | as above, plus **Missing punch** on an odd count and the final shortfall |
| Past day, stamped row (`AttendanceRecord.isClocked`) | the Attendance row | status from HRMS; net, expected, shortfall and missing punch from the custom fields (not recomputed) |
| Past day, unstamped row (old shift, or no fields) | the Attendance row | as before: status, in/out, `working_hours` |
| Two-shift day (history, or a two-shift Shift Assignment) | per shift | unchanged two-shift path (section 7) |

- **`AttendanceStatus.missingPunch`** ("Missing punch", yellow pill): a clocked day that is
  over with an odd number of taps, or a stamped row with `custom_missing_punch` = 1 on a
  Present / Late day. Late minutes stay on the flag line. Counted toward Present and in
  `AttendanceCounts.missing`; its own status filter; in the month strip tally and the month
  screen summary.
- **Cards** (`EmployeeAttendanceCard`): In / Out / "Net 6h 10m of 10h · short 1h 15m".
- **Detail sheet**: the employee's own pattern (not the screen's focus shift), its break for
  that day, and a Net / Expected / Shortfall panel (`ClockedHoursPanel`).
- **Month screen**: each row shows net hours "of" expected, and "Short …" as a flag; the
  summary adds "· N missing punch" and the month's total shortfall.
- **Shift catalogue**: every employee's `default_shift` is loaded (`defaultShiftNames`), so
  Late Start and Early Finish people get their own times and late cut-off today.
- **Reminders** (`attendance_notify_rules.dart`): with no Shift Assignment or Attendance row
  naming a shift, the employee's `default_shift` is used (never `General`). Heads-up at
  cut-off − 10 min, missed check-in at the cut-off, and at end + 10 min an odd number of taps
  asks for the missing tap ("Tap out before you leave"). The 07:30 recap names "missing
  punch" and "short 1h 15m" for stamped rows instead of "no check-out".

## 7. Before 2026-11-30: two shifts per day

From 2026-09-12 to 2026-11-29 each working day was two shifts, `Morning` (08:00-12:15, window
06:00-13:00) and `Afternoon` (13:30-20:00, window 13:00-22:00), with Friday variants
`Morning (Fri)` / `Afternoon (Fri)` split at 13:15. Each Employee Checkin was labelled IN or
OUT by the agent, and HRMS wrote one Attendance row per shift. Rows before 2026-09-12 are
single-row days with `shift = General`.

The app keeps that display path for history: `resolveShifts` takes the Shift Assignments (or
the day's own Attendance-row shift names), `shiftForPunch` puts each punch in the shift whose
window holds it, `deriveShiftStatus` gives each shift its own status, `No check-out` marks an
IN with no OUT once a shift's window has closed, and the card / sheet / month view show a line
per shift. Those rows carry no custom fields, so nothing of section 6 applies to them.

## 8. Known gaps the screen should tolerate

- **Holiday List Assignment field names** (`applicable_for`, `assigned_to`, `from_date`,
  `holiday_list`) are taken from HRMS 16's doctype and were not read against the live site
  from this app. A wrong name fails the request, which falls back to the HRMS calendar
  (correct for anyone linked to an employee; a System Manager without one sees no holidays).
- Employee-level Holiday List Assignments are not read (none exist today).
- A late-arriving punch (terminal offline) can change a day after its row exists; HR cancels
  that day's Attendance and HRMS re-marks it (design 3.7). The app shows whatever row exists.
- Today's figures come from the punches the app can see. Taps before 06:00 or after 22:00 are
  shown in the timeline but not counted, as in HRMS.
- Expected hours make every Standard and Late Start Friday a shortfall (design 3.2). That is
  the agreed rule, not a bug.
- On-device check still to do with a System Manager, an HR User and an Employee-role user.
