/// Model for the **Job Card Time Log** child DocType.
///
/// ERPNext path: Manufacturing → Job Card → time_logs (child table)
/// DocType name : `Job Card Time Log`  (istable: 1)
/// Parent       : `Job Card`
///
/// Each row records one work session: who worked, from when to when,
/// how many units were completed, and which sub-operation it applies to.
class JobCardTimeLog {
  // ── Identity ──────────────────────────────────────────────────────────────
  final String name;

  // ── Time window ───────────────────────────────────────────────────────────
  /// Session start datetime string (ISO 8601). Null if timer not yet stopped.
  final String? fromTime;

  /// Session end datetime string (ISO 8601). Null if timer still running.
  final String? toTime;

  /// Duration in minutes (computed server-side from from/to time).
  final double timeInMins;

  // ── Output ────────────────────────────────────────────────────────────────
  /// Finished-good qty completed during this session.
  final double completedQty;

  // ── Employee ──────────────────────────────────────────────────────────────
  /// Link → Employee. Null when no employee is assigned to the session.
  final String? employee;

  /// Employee full name (denormalised for display, not a DocType field).
  /// Populated when fetching with `fields: ['employee', 'employee_name']`.
  final String? employeeName;

  // ── Sub-operation ─────────────────────────────────────────────────────────
  /// Link → Operation (sub-operation within the Job Card). Optional.
  final String? operation;

  const JobCardTimeLog({
    required this.name,
    this.fromTime,
    this.toTime,
    required this.timeInMins,
    required this.completedQty,
    this.employee,
    this.employeeName,
    this.operation,
  });

  // ── Computed ──────────────────────────────────────────────────────────────

  /// Duration formatted as `HH:MM` for display.
  /// Falls back to `timeInMins` when from/to are not available.
  String get formattedDuration {
    final mins = timeInMins.round();
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// Whether this log row represents a currently running timer
  /// (start recorded, end not yet saved).
  bool get isRunning => fromTime != null && toTime == null;

  // ── Deserialization ───────────────────────────────────────────────────────

  factory JobCardTimeLog.fromJson(Map<String, dynamic> json) {
    return JobCardTimeLog(
      name:         json['name']          as String? ?? '',
      fromTime:     json['from_time']     as String?,
      toTime:       json['to_time']       as String?,
      timeInMins:   (json['time_in_mins'] as num?)?.toDouble() ?? 0.0,
      completedQty: (json['completed_qty'] as num?)?.toDouble() ?? 0.0,
      employee:     json['employee']      as String?,
      employeeName: json['employee_name'] as String?,
      operation:    json['operation']     as String?,
    );
  }

  @override
  String toString() =>
      'JobCardTimeLog(name: $name, from: $fromTime, to: $toTime, '
      'completedQty: $completedQty, employee: $employee)';
}
