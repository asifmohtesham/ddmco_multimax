# Attendance backend handoff (for the Attendance monitoring screen)

State of the ERPNext side as of 2026-09-09, written for whoever builds the attendance
screen in this app. Everything below was verified against `https://erp.multimax.cloud`.
The sync project itself lives in `C:\Users\asifm\biotime-erpnext-sync` (see its PLAN.md).

## 1. Where the data comes from

```
ZKTeco P999 terminal (KA-WH1-BIO1)  -> BioTime 8.5 (office LAN)  -> agent every 15 min
   -> ERPNext "Employee Checkin" (one row per punch)
   -> HRMS scheduler, hourly -> "Attendance" (one row per employee per day)
```

- Backend versions: Frappe 15.120 / ERPNext 15.121 / HRMS 15.64.
- The agent posts each punch through the HRMS endpoint
  `add_log_based_on_employee_field`, which maps BioTime `emp_code` to
  `Employee.attendance_device_id` and rejects duplicate employee + timestamp.
- Time zone is Asia/Dubai. All timestamps are naive local strings, `YYYY-MM-DD HH:mm:ss`.
- No n8n, no webhooks. The app reads ERPNext only.

## 2. Master data already in place

| Object | Value |
|---|---|
| Employees with a device ID and Default Shift | 16 (`HR-EMP-00001..13`, `00021`, `00022`, `00025`); 10 others have neither and will never get attendance rows |
| Shift Type | `General`, 08:00 to 20:00, check-in window 06:00 to 22:00, late entry after 08:15, auto attendance on, Alternating IN/OUT, working hours = first check-in to last check-out, thresholds 0, Process Attendance After 2026-09-09 |
| Holiday List | `Multimax 2026`, every Sunday, company default and on the shift |
| Company | `Multimax` |
| Device | one terminal, serial `AYHO225260052`, alias `KA-WH1-BIO1` |

Real working pattern (not modelled in HRMS): Mon-Thu and Sat 08:00-12:15 / 13:30-20:00,
Fri 08:00-12:00 / 14:30-20:00, Sunday off. HRMS keeps one Attendance per day and cannot
subtract the break, so `working_hours` includes it.

## 3. The two doctypes to read

### Employee Checkin (raw punches, near real time)

Sample row exactly as the API returns it:

```json
{"name":"EMP-CKIN-09-2026-000027","employee":"HR-EMP-00013","employee_name":"Aslam Gangawali",
 "log_type":"","shift":"General","time":"2026-08-28 07:59:23","device_id":"AYHO225260052",
 "skip_auto_attendance":0,"attendance":"","shift_start":"2026-08-28 08:00:00",
 "shift_end":"2026-08-28 17:00:00","shift_actual_start":"2026-08-28 06:00:00",
 "shift_actual_end":"2026-08-28 21:00:00","offshift":0,"latitude":0.0,"longitude":0.0}
```

- `log_type` is always empty (staff only press Check In; the shift decides IN/OUT by alternation).
- `attendance` is filled once the scheduler has linked the punch to an Attendance row.
- `shift_start`/`shift_end` on old rows show 17:00 because they were created before the
  shift was widened to 20:00; new rows will show 20:00.
- Currently 27 rows, 3 Aug to 28 Aug 2026. The terminal has not uploaded since 28 Aug.

### Attendance (one per employee per day, generated hourly)

Fields the screen will use: `employee`, `employee_name`, `attendance_date`, `status`
(`Present`, `Absent`, `On Leave`, `Half Day`, `Work From Home`), `working_hours`,
`in_time`, `out_time`, `late_entry` (0/1), `early_exit` (0/1), `shift`, `leave_type`,
`docstatus` (1 = submitted, only these count).

- Currently 0 rows. Rows start appearing for dates from 2026-09-09 once the shift's
  check-out window has closed (22:00) and the hourly job has run.
- **Absent is generated, not observed**: every employee on the shift gets Absent for any
  non-holiday day without a punch. With 11 of 16 mapped people never punching, expect a lot
  of Absent rows; that is the configuration, not a bug.
- `working_hours` will be 0 until staff also check out, because only one punch exists per day.
- `late_entry` = 1 when the first punch is after 08:15. This is reliable today.

## 4. What "today" should be computed from

Attendance for today does not exist until after 22:00. A live monitoring screen must derive
today's state from Employee Checkin:

| Situation | Derive as |
|---|---|
| Employee has a punch today with time >= 06:00 | Present; `in_time` = earliest punch; late if earliest > 08:15 |
| No punch and today is a Sunday (holiday list) | Holiday |
| No punch and now < 08:15 | Not yet in |
| No punch and now >= 08:15 | Not in yet / absent so far |
| Employee has no `attendance_device_id` | Not tracked (exclude or grey out) |

For past days, read Attendance and trust its `status`, `late_entry`, `in_time`, `out_time`.
For the current day, always fall back to checkins. Frappe's own "Monthly Attendance Sheet"
report is available too (see below) and matches what HR sees on the web.

Freshness: terminal to BioTime is immediate while online; agent runs every 15 minutes;
so a punch is visible in Employee Checkin within about 15 minutes.

## 5. Calls, in this app's terms

The app already logs in with a session cookie (`ApiProvider.loginWithFrappe`) and wraps the
REST API; use the same wrappers. `getDocumentList` takes a `filters` map whose values are
scalars (equality) or `[op, value]` pairs, exactly as shown below; `limit: 0` sends
`limit_page_length=0`, which Frappe treats as no limit. The logged-in user needs the **HR User** role (or HR Manager)
to read Employee Checkin and Attendance for everyone; an `Employee`-role user only sees their
own rows. Gate the screen with `DocTypeGuard` on `Attendance`.

Tracked employees (also the row list for the screen):

```
getDocumentList('Employee',
  fields: ['name','employee_name','attendance_device_id','default_shift','status','department','image'],
  filters: {'status': 'Active', 'attendance_device_id': ['is', 'set']},
  orderBy: 'employee_name asc', limit: 0)
```

Today's punches (one call, then group by employee client-side):

```
getDocumentList('Employee Checkin',
  fields: ['name','employee','employee_name','time','log_type','device_id','shift','attendance'],
  filters: {'time': ['>=', '2026-09-09 00:00:00']},
  orderBy: 'time asc', limit: 0)
```

Attendance for a date range (history / calendar view):

```
getDocumentList('Attendance',
  fields: ['name','employee','employee_name','attendance_date','status','working_hours',
           'in_time','out_time','late_entry','early_exit','shift','leave_type'],
  filters: {'docstatus': 1, 'attendance_date': ['between', ['2026-09-01','2026-09-30']]},
  orderBy: 'attendance_date desc, employee_name asc', limit: 0)
```

Holidays (to label Sundays and any added public holidays):

```
getDocument('Holiday List', 'Multimax 2026')   -> data.holidays[] {holiday_date, description, weekly_off}
```

Shift settings (for the 08:15 late threshold instead of hardcoding it):

```
getDocument('Shift Type', 'General')  -> start_time, end_time, late_entry_grace_period,
                                          begin_check_in_before_shift_start_time
```

Monthly summary, same numbers HR sees, via the report runner the app already uses
(`ApiProvider.getReport`, which calls `/api/method/frappe.desk.query_report.run`):

```
getReport('Monthly Attendance Sheet',
  filters: {'month': '09', 'year': '2026', 'company': 'Multimax', 'summarized_view': 1})
```

Realtime option: `FrappeSocket.connect` (`lib/app/data/services/frappe_socket.dart`) is
currently doc-scoped (`doctype` + `docname` -> `doc_update`); it would need a
`doctype_subscribe` / `list_update` variant to watch new Employee Checkin rows. A 60-second
poll is an acceptable first version and needs no socket change.

## 6. Suggested module (mirrors the existing report modules)

```
lib/app/modules/hr/attendance_monitor/
  attendance_monitor_binding.dart
  attendance_monitor_controller.dart   # loads employees + today's checkins, derives status
  attendance_monitor_screen.dart       # list: name, status pill, in time, late flag
  widgets/attendance_status_pill.dart  # Present / Late / Not in / Holiday / Absent / Not tracked
  history/                             # optional: month view from Attendance
```

- Follow `lib/app/modules/manufacturing/reports/job_card_summary/` for filters (date range,
  department) and `ReportFilterSheet` (`lib/app/modules/global_widgets/report_filter_sheet.dart`).
- `DocTypeGuard` lives at `lib/app/modules/global_widgets/doctype_guard.dart`.
- Status colours through the `AppColors` ramp (`lib/app/data/constants/app_theme.dart`) per
  CLAUDE.md (x700 light, x300 dark), never raw material shades.
- List rules from CLAUDE.md apply: `Scrollbar`, bottom-inset padding, end-of-list marker with a
  count summary (present / late / not in), not a sum of anything numeric.

## 7. Known gaps the screen should tolerate

- Terminal offline since 2026-08-28: expect zero punches until it is fixed.
- Five people exist in BioTime but not in ERPNext (Jaffer Potey, Ashal, Hunain, Khalid,
  Ehtisham); their punches are dropped by the agent as "unmatched". Ten ERPNext employees are
  not enrolled on the terminal; they will show Absent every day once Attendance runs.
- Tanveer's mapping (BioTime "Tanveer Mulla" to ERPNext "Tanveer Shaikh") is a first-name match.
- URL-encode spaces in resource paths (`Employee%20Checkin`); Dio does this already, curl does not.
