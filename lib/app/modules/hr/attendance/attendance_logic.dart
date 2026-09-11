import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/attendance_models.dart';

/// Every state the screen can show for one employee on one day.
///
/// Today is derived from raw punches (Attendance rows only exist after the
/// shift's check-out window closes); past days trust the Attendance ledger and
/// fall back to punches when no row exists yet.
enum AttendanceStatus {
  present('Present'),
  late('Late'),
  notInYet('Not in yet'),
  absentSoFar('Absent so far'),
  absent('Absent'),
  noCheckOut('No check-out'),
  holiday('Holiday'),
  onLeave('On Leave'),
  halfDay('Half Day'),
  workFromHome('Work From Home'),
  untracked('Not tracked');

  const AttendanceStatus(this.label);
  final String label;

  /// Sort order: attention first. Absent › No check-out › Late › Not in ›
  /// Present › rest.
  int get severity => switch (this) {
        absentSoFar || absent => 0,
        noCheckOut => 1,
        late => 2,
        notInYet => 3,
        present => 4,
        halfDay => 5,
        workFromHome => 6,
        onLeave => 7,
        holiday => 8,
        untracked => 99,
      };

  bool get isAbsent => this == absent || this == absentSoFar;
}

/// Derived view row for one employee on the selected day.
class EmployeeDayStatus {
  final TrackedEmployee employee;
  final AttendanceStatus status;
  final DateTime? inTime;
  final DateTime? outTime;
  final Duration? lateBy;
  final bool earlyExit;
  final double workingHours;
  final List<EmployeeCheckin> punches;
  final AttendanceRecord? ledger;

  /// One entry per shift on a Morning/Afternoon day, earliest first; empty on
  /// a single-shift day.
  final List<ShiftDayStatus> shifts;

  const EmployeeDayStatus({
    required this.employee,
    required this.status,
    this.inTime,
    this.outTime,
    this.lateBy,
    this.earlyExit = false,
    this.workingHours = 0,
    this.punches = const [],
    this.ledger,
    this.shifts = const [],
  });

  /// Secondary line under the status pill, or null.
  String? get flag {
    if (lateBy != null && lateBy!.inMinutes > 0) {
      return '${lateBy!.inMinutes} min late';
    }
    if (earlyExit) return 'Early exit';
    if (status == AttendanceStatus.holiday && punches.isNotEmpty) {
      return 'Punched on holiday';
    }
    return null;
  }

  /// A flag that needs the orange "attention" ink rather than neutral grey.
  bool get flagIsWarning => lateBy != null || earlyExit;
}

/// One shift of an employee's day: its own status, in/out and flags.
class ShiftDayStatus {
  final ShiftRules shift;
  final AttendanceStatus status;
  final DateTime? inTime;
  final DateTime? outTime;
  final Duration? lateBy;
  final bool earlyExit;
  final double workingHours;

  /// This shift's punches, sorted, with IN (true) / OUT (false) for each.
  final List<EmployeeCheckin> punches;
  final List<bool> directions;
  final AttendanceRecord? ledger;

  const ShiftDayStatus({
    required this.shift,
    required this.status,
    this.inTime,
    this.outTime,
    this.lateBy,
    this.earlyExit = false,
    this.workingHours = 0,
    this.punches = const [],
    this.directions = const [],
    this.ledger,
  });

  /// Counts toward the day once HRMS has a row for it, it has a punch, or its
  /// late cut-off has passed; a shift that has not started yet does not.
  bool startedBy(DateTime day, DateTime now) =>
      ledger != null || punches.isNotEmpty || !now.isBefore(shift.cutoffOn(day));

  /// "12 min late" / "Early exit", or null.
  String? get flag {
    if (lateBy != null && lateBy!.inMinutes > 0) return '${lateBy!.inMinutes} min late';
    if (earlyExit) return 'Early exit';
    return null;
  }
}

AttendanceStatus _ledgerStatus(AttendanceRecord r) => switch (r.status) {
      'Present' => r.lateEntry ? AttendanceStatus.late : AttendanceStatus.present,
      'Absent' => AttendanceStatus.absent,
      'On Leave' => AttendanceStatus.onLeave,
      'Half Day' => AttendanceStatus.halfDay,
      'Work From Home' => AttendanceStatus.workFromHome,
      _ => AttendanceStatus.present,
    };

/// Pure derivation. [punches] must belong to [employee] on [day]; they are
/// sorted here. [now] is injected so the cut-offs are testable.
///
/// A day with more than one of [shifts] (Morning + Afternoon) is derived per
/// shift, with [ledgers] matched by shift name. Otherwise [shift] (or the only
/// one of [shifts]) and [ledger] (or the first of [ledgers]) give the
/// single-shift day, unchanged from before two shifts existed.
EmployeeDayStatus deriveDayStatus({
  required TrackedEmployee employee,
  required DateTime day,
  required DateTime now,
  required ShiftRules shift,
  required bool isHoliday,
  List<EmployeeCheckin> punches = const [],
  AttendanceRecord? ledger,
  List<ShiftRules> shifts = const [],
  List<AttendanceRecord> ledgers = const [],
}) {
  if (shifts.length > 1) {
    return _deriveShiftedDay(
      employee: employee,
      day: day,
      now: now,
      shifts: shifts,
      isHoliday: isHoliday,
      punches: punches,
      ledgers: ledgers,
    );
  }
  if (shifts.length == 1) shift = shifts.single;
  ledger ??= ledgers.isEmpty ? null : ledgers.first;
  final sorted = [...punches]..sort((a, b) => a.time.compareTo(b.time));
  final cutoff = shift.cutoffOn(day);

  if (!employee.isTracked) {
    return EmployeeDayStatus(
        employee: employee, status: AttendanceStatus.untracked, punches: sorted);
  }

  // Past days: the ledger is authoritative once it exists.
  if (ledger != null) {
    final st = _ledgerStatus(ledger);
    final firstIn = ledger.inTime ?? (sorted.isNotEmpty ? sorted.first.time : null);
    return EmployeeDayStatus(
      employee: employee,
      status: st,
      inTime: firstIn,
      outTime: ledger.outTime,
      lateBy: st == AttendanceStatus.late && firstIn != null
          ? firstIn.difference(cutoff)
          : null,
      earlyExit: ledger.earlyExit,
      workingHours: ledger.workingHours,
      punches: sorted,
      ledger: ledger,
    );
  }

  final firstIn = sorted.isNotEmpty ? sorted.first.time : null;
  // Alternating IN/OUT: an even punch count means the last punch is an OUT.
  final lastOut =
      sorted.length >= 2 && sorted.length.isEven ? sorted.last.time : null;

  if (isHoliday) {
    return EmployeeDayStatus(
      employee: employee,
      status: AttendanceStatus.holiday,
      inTime: firstIn,
      outTime: lastOut,
      punches: sorted,
    );
  }

  if (firstIn != null) {
    final late = firstIn.isAfter(cutoff);
    return EmployeeDayStatus(
      employee: employee,
      status: late ? AttendanceStatus.late : AttendanceStatus.present,
      inTime: firstIn,
      outTime: lastOut,
      lateBy: late ? firstIn.difference(cutoff) : null,
      punches: sorted,
    );
  }

  final isPastDay = dateOnly(day).isBefore(dateOnly(now));
  if (isPastDay) {
    return EmployeeDayStatus(employee: employee, status: AttendanceStatus.absent);
  }
  return EmployeeDayStatus(
    employee: employee,
    status: now.isBefore(cutoff)
        ? AttendanceStatus.notInYet
        : AttendanceStatus.absentSoFar,
  );
}

/// IN/OUT for each of [sorted]: the punch's own `log_type` when set, otherwise
/// the opposite of the previous punch (the first is IN).
List<bool> punchDirections(List<EmployeeCheckin> sorted) {
  final out = <bool>[];
  var nextIn = true;
  for (final p in sorted) {
    final lt = p.logType.trim().toUpperCase();
    final isIn = lt == 'IN' || (lt != 'OUT' && nextIn);
    out.add(isIn);
    nextIn = !isIn;
  }
  return out;
}

/// The shift whose check-in/check-out window holds [t]; where two windows meet
/// the later shift wins (13:00 is Afternoon, as in the sync agent). A punch
/// outside every window goes to the nearest shift.
ShiftRules shiftForPunch(DateTime t, List<ShiftRules> shifts, DateTime day) {
  ShiftRules? hit;
  for (final s in shifts) {
    if (!t.isBefore(s.windowStartOn(day)) && !t.isAfter(s.windowEndOn(day))) hit = s;
  }
  if (hit != null) return hit;
  Duration gap(ShiftRules s) => t.isBefore(s.windowStartOn(day))
      ? s.windowStartOn(day).difference(t)
      : t.difference(s.windowEndOn(day));
  return shifts.reduce((a, b) => gap(b) < gap(a) ? b : a);
}

/// One shift of one day. With a [ledger] row HRMS has decided; otherwise the
/// shift's own punches do: first IN, out = the last punch when it is an OUT,
/// late after the cut-off, early exit before end − grace. An IN with no OUT
/// once the check-out window has closed is No check-out when
/// [requireCheckOut] (every shift of a two-shift day).
ShiftDayStatus deriveShiftStatus({
  required ShiftRules shift,
  required DateTime day,
  required DateTime now,
  List<EmployeeCheckin> punches = const [],
  AttendanceRecord? ledger,
  bool requireCheckOut = true,
}) {
  final sorted = [...punches]..sort((a, b) => a.time.compareTo(b.time));
  final dirs = punchDirections(sorted);
  final cutoff = shift.cutoffOn(day);

  if (ledger != null) {
    var st = _ledgerStatus(ledger);
    final firstIn = ledger.inTime ?? (sorted.isNotEmpty ? sorted.first.time : null);
    final attended = st == AttendanceStatus.present || st == AttendanceStatus.late;
    if (requireCheckOut && attended && ledger.outTime == null) {
      st = AttendanceStatus.noCheckOut;
    }
    return ShiftDayStatus(
      shift: shift,
      status: st,
      inTime: firstIn,
      outTime: ledger.outTime,
      lateBy: ledger.lateEntry && firstIn != null && firstIn.isAfter(cutoff)
          ? firstIn.difference(cutoff)
          : null,
      earlyExit: ledger.earlyExit,
      workingHours: ledger.workingHours,
      punches: sorted,
      directions: dirs,
      ledger: ledger,
    );
  }

  if (sorted.isEmpty) {
    final over = dateOnly(day).isBefore(dateOnly(now)) || now.isAfter(shift.windowEndOn(day));
    return ShiftDayStatus(
      shift: shift,
      status: over
          ? AttendanceStatus.absent
          : now.isBefore(cutoff)
              ? AttendanceStatus.notInYet
              : AttendanceStatus.absentSoFar,
    );
  }

  final inIdx = dirs.indexOf(true);
  final firstIn = sorted[inIdx >= 0 ? inIdx : 0].time;
  final lastOut = dirs.last ? null : sorted.last.time;
  final late = firstIn.isAfter(cutoff);
  var st = late ? AttendanceStatus.late : AttendanceStatus.present;
  if (requireCheckOut && lastOut == null && now.isAfter(shift.windowEndOn(day))) {
    st = AttendanceStatus.noCheckOut;
  }
  return ShiftDayStatus(
    shift: shift,
    status: st,
    inTime: firstIn,
    outTime: lastOut,
    lateBy: late ? firstIn.difference(cutoff) : null,
    earlyExit: lastOut != null && lastOut.isBefore(shift.earlyExitBeforeOn(day)),
    workingHours: lastOut == null ? 0 : lastOut.difference(firstIn).inMinutes / 60,
    punches: sorted,
    directions: dirs,
  );
}

/// A Morning/Afternoon day: each shift derived on its own, then the day takes
/// the most attention-worthy status among the shifts that have started.
EmployeeDayStatus _deriveShiftedDay({
  required TrackedEmployee employee,
  required DateTime day,
  required DateTime now,
  required List<ShiftRules> shifts,
  required bool isHoliday,
  required List<EmployeeCheckin> punches,
  required List<AttendanceRecord> ledgers,
}) {
  final ordered = [...shifts]..sort((a, b) => a.start.compareTo(b.start));
  final sorted = [...punches]..sort((a, b) => a.time.compareTo(b.time));

  if (!employee.isTracked) {
    return EmployeeDayStatus(
        employee: employee, status: AttendanceStatus.untracked, punches: sorted);
  }
  if (isHoliday) {
    final dirs = punchDirections(sorted);
    return EmployeeDayStatus(
      employee: employee,
      status: AttendanceStatus.holiday,
      inTime: sorted.isEmpty ? null : sorted.first.time,
      outTime: sorted.length >= 2 && !dirs.last ? sorted.last.time : null,
      punches: sorted,
    );
  }

  // A ledger row whose shift matches none of the day's shifts (e.g. '' from a
  // Leave Application, or a manual row) decides the whole day rather than
  // being silently dropped.
  final stray = ledgers.where((r) => !ordered.any((s) => s.name == r.shift));
  if (stray.isNotEmpty) {
    return deriveDayStatus(
      employee: employee,
      day: day,
      now: now,
      shift: ordered.first,
      isHoliday: false,
      punches: punches,
      ledger: stray.first,
    );
  }

  final byShift = {for (final s in ordered) s.name: <EmployeeCheckin>[]};
  for (final p in sorted) {
    byShift[shiftForPunch(p.time, ordered, day).name]!.add(p);
  }
  AttendanceRecord? ledgerFor(String name) {
    for (final r in ledgers) {
      if (r.shift == name) return r;
    }
    return null;
  }

  final segments = [
    for (final s in ordered)
      deriveShiftStatus(
        shift: s,
        day: day,
        now: now,
        punches: byShift[s.name]!,
        ledger: ledgerFor(s.name),
      ),
  ];
  final started = segments.where((s) => s.startedBy(day, now)).toList();
  final counted = started.isEmpty ? [segments.first] : started;
  final worst = counted.reduce((a, b) => b.status.severity < a.status.severity ? b : a);

  DateTime? inTime;
  Duration? lateBy;
  AttendanceRecord? ledger;
  for (final s in segments) {
    inTime ??= s.inTime;
    ledger ??= s.ledger;
  }
  for (final s in counted) {
    if (s.lateBy != null && s.lateBy!.inMinutes > 0) {
      lateBy = s.lateBy;
      break;
    }
  }
  return EmployeeDayStatus(
    employee: employee,
    status: worst.status,
    inTime: inTime,
    outTime: counted.last.outTime,
    lateBy: lateBy,
    earlyExit: counted.any((s) => s.earlyExit),
    workingHours: segments.fold(0.0, (sum, s) => sum + s.workingHours),
    punches: sorted,
    ledger: ledger,
    shifts: segments,
  );
}

/// The shifts [employee] works on [day], earliest first: their Shift
/// Assignments covering the day, with rules from [catalog]; without any, the
/// day's own Attendance-row shift names in [ledgerNames] (HRMS already wrote
/// them, so they're authoritative even with no assignment loaded yet); without
/// either, their default shift, else [fallback]. Names missing from [catalog]
/// get [ShiftRules.named].
List<ShiftRules> resolveShifts({
  required TrackedEmployee employee,
  required DateTime day,
  required Iterable<ShiftAssignmentRow> assignments,
  required Map<String, ShiftRules> catalog,
  ShiftRules fallback = ShiftRules.fallback,
  Iterable<String> ledgerNames = const [],
}) {
  var names = {
    for (final a in assignments)
      if (a.employee == employee.name && a.covers(day)) a.shiftType,
  };
  if (names.isEmpty) {
    names = {for (final n in ledgerNames) if (n.trim().isNotEmpty) n.trim()};
  }
  if (names.isEmpty) {
    final d = (employee.defaultShift ?? '').trim();
    if (d.isEmpty) return [catalog[fallback.name] ?? fallback];
    return [catalog[d] ?? ShiftRules.named(d)];
  }
  return [for (final n in names) catalog[n] ?? ShiftRules.named(n)]
    ..sort((a, b) => a.start.compareTo(b.start));
}

/// The shift of [row] that matters at [now]: the latest one whose check-in
/// window has opened, else the first. Null on a single-shift day.
ShiftDayStatus? currentSegment(EmployeeDayStatus row, DateTime now) {
  if (row.shifts.isEmpty) return null;
  final day = dateOnly(now);
  var pick = row.shifts.first;
  for (final s in row.shifts) {
    if (!now.isBefore(s.shift.windowStartOn(day))) pick = s;
  }
  return pick;
}

/// Every distinct shift in [lists] (one list per employee), earliest first.
List<ShiftRules> distinctShifts(Iterable<List<ShiftRules>> lists) {
  final byName = <String, ShiftRules>{};
  for (final l in lists) {
    for (final s in l) {
      byName.putIfAbsent(s.name, () => s);
    }
  }
  return byName.values.toList()..sort((a, b) => a.start.compareTo(b.start));
}

/// The shift in focus at [now] on [day] (banners, headline copy): the latest
/// of [shifts] whose check-in window has opened, else the first.
ShiftRules focusShift(List<ShiftRules> shifts, DateTime day, DateTime now) {
  var pick = shifts.first;
  for (final s in shifts) {
    if (!now.isBefore(s.windowStartOn(day))) pick = s;
  }
  return pick;
}

/// Attention-first ordering, then name A–Z.
int compareDayStatus(EmployeeDayStatus a, EmployeeDayStatus b) {
  final s = a.status.severity.compareTo(b.status.severity);
  if (s != 0) return s;
  return a.employee.employeeName
      .toLowerCase()
      .compareTo(b.employee.employeeName.toLowerCase());
}

/// Rows worth a line on the Dashboard card: untracked never, the viewer's
/// own row never (shown instead in the separate "My attendance" card), nobody
/// on a holiday; the rest
/// attention-first ([compareDayStatus]) and capped at [max].
List<EmployeeDayStatus> dashboardAttendanceHighlights(
  Iterable<EmployeeDayStatus> rows, {
  String? selfEmployee,
  int max = 3,
}) {
  final list = rows
      .where((r) =>
          r.status != AttendanceStatus.untracked &&
          r.status != AttendanceStatus.holiday &&
          r.employee.name != selfEmployee)
      .toList()
    ..sort(compareDayStatus);
  return list.length > max ? list.sublist(0, max) : list;
}

/// Counts for the summary strip; untracked rows are never counted.
class AttendanceCounts {
  final int present, late, notIn, absent, noOut, holiday, tracked;
  const AttendanceCounts({
    this.present = 0,
    this.late = 0,
    this.notIn = 0,
    this.absent = 0,
    this.noOut = 0,
    this.holiday = 0,
    this.tracked = 0,
  });

  static AttendanceCounts of(Iterable<EmployeeDayStatus> rows) {
    var p = 0, l = 0, n = 0, a = 0, o = 0, h = 0, t = 0;
    for (final r in rows) {
      switch (r.status) {
        case AttendanceStatus.untracked:
          continue;
        case AttendanceStatus.present:
        case AttendanceStatus.workFromHome:
        case AttendanceStatus.halfDay:
          p++;
        case AttendanceStatus.late:
          l++;
        case AttendanceStatus.notInYet:
          n++;
        case AttendanceStatus.absent:
        case AttendanceStatus.absentSoFar:
          a++;
        case AttendanceStatus.noCheckOut:
          p++; // on site (just missing an OUT) — counts toward Present too
          o++;
        case AttendanceStatus.holiday:
        case AttendanceStatus.onLeave:
          h++;
      }
      t++;
    }
    return AttendanceCounts(
        present: p, late: l, notIn: n, absent: a, noOut: o, holiday: h, tracked: t);
  }
}

/// Status-filter keys used by the summary tiles and the filter sheet. Present
/// also matches No check-out (they're on site, just missing an OUT) — the
/// dedicated 'No check-out' option below still isolates just them.
const kStatusFilterOptions = <String, List<AttendanceStatus>>{
  'Present': [AttendanceStatus.present, AttendanceStatus.noCheckOut],
  'Late': [AttendanceStatus.late],
  'Not in yet': [AttendanceStatus.notInYet],
  'Absent': [AttendanceStatus.absent, AttendanceStatus.absentSoFar],
  'No check-out': [AttendanceStatus.noCheckOut],
  'Holiday': [AttendanceStatus.holiday, AttendanceStatus.onLeave],
  'Not tracked': [AttendanceStatus.untracked],
};

/// Applies the search box and the department / status filters.
List<EmployeeDayStatus> filterRows(
  Iterable<EmployeeDayStatus> rows, {
  String query = '',
  String? department,
  String? statusKey,
}) {
  final q = query.trim().toLowerCase();
  final statuses = statusKey == null ? null : kStatusFilterOptions[statusKey];
  return rows.where((r) {
    if (department != null &&
        department.isNotEmpty &&
        r.employee.department != department) {
      return false;
    }
    if (statuses != null && !statuses.contains(r.status)) return false;
    if (q.isNotEmpty &&
        !r.employee.employeeName.toLowerCase().contains(q) &&
        !r.employee.department.toLowerCase().contains(q) &&
        !r.employee.name.toLowerCase().contains(q)) {
      return false;
    }
    return true;
  }).toList();
}

/// "Updated 5 min ago" / "Updated 09:15" / "Updated 28 Aug".
String freshnessLabel(DateTime? loadedAt, DateTime now) {
  if (loadedAt == null) return 'Updating…';
  final d = now.difference(loadedAt);
  if (d.inMinutes < 1) return 'Updated just now';
  if (d.inMinutes < 60) return 'Updated ${d.inMinutes} min ago';
  if (dateOnly(loadedAt) == dateOnly(now)) return 'Updated ${kHHmm.format(loadedAt)}';
  return 'Updated ${loadedAt.day} ${_kMon[loadedAt.month - 1]}';
}

const _kMon = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

/// Data older than the 15-minute agent sync interval is "stale".
bool isStale(DateTime? loadedAt, DateTime now) =>
    loadedAt == null ? false : now.difference(loadedAt).inMinutes > 15;

/// One employee's month for the Dashboard dot strip: a status (or null) per
/// calendar day plus the counts behind the tally line.
class MonthStrip {
  final DateTime month;

  /// Index 0 is the 1st. Null means nothing to draw: a future day, today
  /// while still pending, or a past working day HRMS has not processed.
  final List<AttendanceStatus?> days;

  /// Index of today within [days]; null when [month] is not the current one.
  final int? todayIndex;
  final int present, late, absent, leave, noOut;

  const MonthStrip({
    required this.month,
    required this.days,
    this.todayIndex,
    this.present = 0,
    this.late = 0,
    this.absent = 0,
    this.leave = 0,
    this.noOut = 0,
  });

  /// "September · 5 present · 2 late · 1 absent" (+ " · 1 no check-out",
  /// " · 1 leave").
  String get tallyLabel =>
      '${DateFormat('MMMM').format(month)} · $present present · $late late · $absent absent'
      '${noOut > 0 ? ' · $noOut no check-out' : ''}'
      '${leave > 0 ? ' · $leave leave' : ''}';
}

/// Builds the [MonthStrip] for [month]. Past days trust [ledger] (the
/// viewer's own rows; `late_entry` → Late; two rows on a Morning/Afternoon
/// day, rules from [catalog]), holidays read Holiday, today comes from [today]
/// (Not in yet / Absent so far stay null — the day is not over), future days
/// are null. Late is counted apart from present.
MonthStrip buildMonthStrip({
  required DateTime month,
  required List<AttendanceRecord> ledger,
  required Set<String> holidays,
  required EmployeeDayStatus? today,
  required DateTime now,
  required ShiftRules shift,
  required TrackedEmployee employee,
  Map<String, ShiftRules> catalog = const {},
}) {
  final first = DateTime(month.year, month.month);
  final dayCount = DateTime(month.year, month.month + 1, 0).day;
  final todayDate = dateOnly(now);
  final byDate = <String, List<AttendanceRecord>>{};
  for (final r in ledger) {
    byDate.putIfAbsent(kFrappeDate.format(r.date), () => []).add(r);
  }
  final days = <AttendanceStatus?>[];
  int? todayIndex;
  // Short names like AttendanceCounts.of — `late` is a Dart contextual keyword.
  var p = 0, l = 0, a = 0, v = 0, o = 0;

  for (var i = 0; i < dayCount; i++) {
    final d = DateTime(first.year, first.month, i + 1);
    final key = kFrappeDate.format(d);
    AttendanceStatus? st;
    if (d == todayDate) {
      todayIndex = i;
      final t = today?.status;
      st = t == AttendanceStatus.notInYet || t == AttendanceStatus.absentSoFar ? null : t;
    } else if (d.isAfter(todayDate)) {
      st = null;
    } else if (byDate[key] != null) {
      final rows = byDate[key]!;
      final names = {for (final r in rows) r.shift};
      st = deriveDayStatus(
        employee: employee,
        day: d,
        now: now,
        shift: shift,
        isHoliday: false,
        shifts: names.length > 1
            ? [for (final n in names) catalog[n] ?? ShiftRules.named(n)]
            : const [],
        ledgers: rows,
      ).status;
    } else if (holidays.contains(key)) {
      st = AttendanceStatus.holiday;
    }
    switch (st) {
      case AttendanceStatus.present:
      case AttendanceStatus.halfDay:
      case AttendanceStatus.workFromHome:
        p++;
      case AttendanceStatus.late:
        l++;
      case AttendanceStatus.absent:
        a++;
      case AttendanceStatus.noCheckOut:
        o++;
      case AttendanceStatus.onLeave:
        v++;
      default:
        break;
    }
    days.add(st);
  }

  return MonthStrip(
    month: first,
    days: days,
    todayIndex: todayIndex,
    present: p,
    late: l,
    absent: a,
    leave: v,
    noOut: o,
  );
}

/// Headline + sub-line for the viewer's own "My attendance" block. Wording
/// never blames the terminal: "No check-in recorded yet" is true whether the
/// person or the device is at fault. On a Morning/Afternoon day it describes
/// the shift in progress ([currentSegment]) and names it in the sub-line.
(String, String) myAttendanceHeadline(
    EmployeeDayStatus row, ShiftRules shift, DateTime now) {
  final seg = currentSegment(row, now);
  if (seg == null ||
      row.status == AttendanceStatus.holiday ||
      row.status == AttendanceStatus.untracked) {
    return _headline(row, shift, now);
  }
  final (h1, h2) = _headline(
    EmployeeDayStatus(
      employee: row.employee,
      status: seg.status,
      inTime: seg.inTime,
      lateBy: seg.lateBy,
      ledger: seg.ledger,
    ),
    seg.shift,
    now,
  );
  return (h1, '${seg.shift.shortName} · $h2');
}

(String, String) _headline(EmployeeDayStatus row, ShiftRules shift, DateTime now) =>
    switch (row.status) {
      AttendanceStatus.noCheckOut =>
        ('No check-out', 'Ended ${shift.endLabel} with no out punch'),
      AttendanceStatus.notInYet =>
        ('Not in yet', 'Punch before ${shift.cutoffLabel} to be on time'),
      AttendanceStatus.absentSoFar =>
        ('No check-in recorded yet', 'Shift started ${shift.startLabel}'),
      AttendanceStatus.present || AttendanceStatus.late => (
          row.inTime == null ? row.status.label : 'In · ${kHHmm.format(row.inTime!)}',
          row.lateBy != null && row.lateBy!.inMinutes > 0
              ? '${row.lateBy!.inMinutes} min late'
              : row.status == AttendanceStatus.late
                  ? 'After the ${shift.cutoffLabel} cut-off'
                  : 'On time',
        ),
      AttendanceStatus.holiday =>
        ('Holiday', '${DateFormat('EEEE').format(now)} · no attendance expected'),
      AttendanceStatus.absent => ('Absent', 'No check-in recorded'),
      AttendanceStatus.untracked =>
        ('Not enrolled', "You're not enrolled on the attendance terminal"),
      _ => (row.status.label, row.ledger?.leaveType ?? ''),
    };

/// System-Manager banner copy on the Attendance screen.
String unenrolledLabel(int n) => n == 1
    ? "1 employee isn't enrolled on the terminal"
    : "$n employees aren't enrolled on the terminal";
