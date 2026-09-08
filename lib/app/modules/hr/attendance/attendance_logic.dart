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
  holiday('Holiday'),
  onLeave('On Leave'),
  halfDay('Half Day'),
  workFromHome('Work From Home'),
  untracked('Not tracked');

  const AttendanceStatus(this.label);
  final String label;

  /// Sort order: attention first. Absent › Late › Not in › Present › rest.
  int get severity => switch (this) {
        absentSoFar || absent => 0,
        late => 1,
        notInYet => 2,
        present => 3,
        halfDay => 4,
        workFromHome => 5,
        onLeave => 6,
        holiday => 7,
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

AttendanceStatus _ledgerStatus(AttendanceRecord r) => switch (r.status) {
      'Present' => r.lateEntry ? AttendanceStatus.late : AttendanceStatus.present,
      'Absent' => AttendanceStatus.absent,
      'On Leave' => AttendanceStatus.onLeave,
      'Half Day' => AttendanceStatus.halfDay,
      'Work From Home' => AttendanceStatus.workFromHome,
      _ => AttendanceStatus.present,
    };

/// Pure derivation. [punches] must belong to [employee] on [day]; they are
/// sorted here. [now] is injected so the 08:15 cut-off is testable.
EmployeeDayStatus deriveDayStatus({
  required TrackedEmployee employee,
  required DateTime day,
  required DateTime now,
  required ShiftRules shift,
  required bool isHoliday,
  List<EmployeeCheckin> punches = const [],
  AttendanceRecord? ledger,
}) {
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

/// Attention-first ordering, then name A–Z.
int compareDayStatus(EmployeeDayStatus a, EmployeeDayStatus b) {
  final s = a.status.severity.compareTo(b.status.severity);
  if (s != 0) return s;
  return a.employee.employeeName
      .toLowerCase()
      .compareTo(b.employee.employeeName.toLowerCase());
}

/// Counts for the summary strip; untracked rows are never counted.
class AttendanceCounts {
  final int present, late, notIn, absent, holiday, tracked;
  const AttendanceCounts({
    this.present = 0,
    this.late = 0,
    this.notIn = 0,
    this.absent = 0,
    this.holiday = 0,
    this.tracked = 0,
  });

  static AttendanceCounts of(Iterable<EmployeeDayStatus> rows) {
    var p = 0, l = 0, n = 0, a = 0, h = 0, t = 0;
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
        case AttendanceStatus.holiday:
        case AttendanceStatus.onLeave:
          h++;
      }
      t++;
    }
    return AttendanceCounts(
        present: p, late: l, notIn: n, absent: a, holiday: h, tracked: t);
  }
}

/// Status-filter keys used by the summary tiles and the filter sheet.
const kStatusFilterOptions = <String, List<AttendanceStatus>>{
  'Present': [AttendanceStatus.present],
  'Late': [AttendanceStatus.late],
  'Not in yet': [AttendanceStatus.notInYet],
  'Absent': [AttendanceStatus.absent, AttendanceStatus.absentSoFar],
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
