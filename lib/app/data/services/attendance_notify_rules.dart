/// Pure decisions for attendance notifications (spec 2026-09-12 §5): which
/// reminder, recap or terminal alert to post, and its exact wording.
/// GetX-free — runs in the background isolate.
library;

import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/services/attendance_timeline.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';

const int kShiftReminderIdBase = 3000;
const int kRecapNotificationId = 3010;
const int kTerminalNotificationId = 3020;
const int kSessionNotificationId = 3030;
const List<int> kAttendanceNotificationIds = [
  kShiftReminderIdBase,
  kShiftReminderIdBase + 1,
  kRecapNotificationId,
  kTerminalNotificationId,
  kSessionNotificationId,
];

class NotifyMessage {
  final int id;
  final String title;
  final String body;

  /// Posted on the System Manager terminal channel instead of reminders.
  final bool terminal;

  const NotifyMessage({required this.id, required this.title, required this.body, this.terminal = false});
}

const NotifyMessage kSessionExpiredMessage = NotifyMessage(
  id: kSessionNotificationId,
  title: 'Attendance reminders paused',
  body: 'Open Multimax to keep attendance reminders working.',
);

String _short(String shiftName) => shiftName.replaceFirst(RegExp(r'\s*\(.*\)$'), '');

/// The shifts that may produce reminders for [employee] on [day]: their own
/// Shift Assignments covering the day, else the shifts their own Attendance
/// rows name. Never the General / fallback shift; a name missing from
/// [catalog] is left out (no reminder at unknown times).
List<ShiftRules> reminderShifts({
  required String employee,
  required DateTime day,
  required List<ShiftAssignmentRow> assignments,
  required List<AttendanceRecord> ledger,
  required Map<String, ShiftRules> catalog,
}) {
  final names = <String>{
    for (final a in assignments)
      if (a.employee == employee && a.covers(day)) a.shiftType,
  };
  if (names.isEmpty) {
    // A ledger row naming the General/fallback shift only means "no real
    // shift was assigned yet" (pre-go-live data) — never a schedule to remind
    // against. An explicit Shift Assignment for it, above, is a real schedule.
    names.addAll(ledger
        .map((r) => r.shift)
        .where((n) => n.trim().isNotEmpty && n != ShiftRules.fallback.name));
  }
  return [
    for (final n in names)
      if (catalog[n] != null) catalog[n]!,
  ]..sort((a, b) => a.start.compareTo(b.start));
}

/// Everything [decideReminders] needs about the employee's day.
class EmployeeDayFacts {
  final List<ShiftRules> shifts;
  final List<EmployeeCheckin> punches;
  final List<AttendanceRecord> ledger;
  final bool holiday;
  final bool onLeave;
  final bool syncing;

  /// The heartbeat's `agent_last_run`: punches up to this instant have been
  /// polled. Null when the heartbeat couldn't be read.
  final DateTime? syncedUpTo;

  const EmployeeDayFacts({
    required this.shifts,
    this.punches = const [],
    this.ledger = const [],
    this.holiday = false,
    this.onLeave = false,
    this.syncing = true,
    this.syncedUpTo,
  });
}

class ReminderOutcome {
  final List<NotifyMessage> post;
  final List<int> cancel;
  final Set<String> handled;
  final Set<String> posted;

  const ReminderOutcome(
      {required this.post, required this.cancel, required this.handled, required this.posted});
}

/// [msg] is the reminder to post, if any. [heldForSync] means a `missedIn`
/// would otherwise fire but the sync hasn't caught up past the shift's
/// cut-off yet — the caller must leave that moment open, not mark it done.
({NotifyMessage? msg, bool heldForSync}) _reminder(
    ShiftMoment m, ShiftDayStatus st, DateTime now, DateTime? syncedUpTo) {
  final s = m.shift;
  final day = dateOnly(now);
  final id = kShiftReminderIdBase + m.shiftIndex;
  final hasIn = st.inTime != null;
  switch (m.kind) {
    case ReminderKind.headsUp:
      if (hasIn || !now.isBefore(s.cutoffOn(day))) return (msg: null, heldForSync: false);
      return (
        msg: NotifyMessage(
            id: id,
            title: 'Check in for the ${s.shortName} shift',
            body: 'Punch before ${s.cutoffLabel} to be on time.'),
        heldForSync: false,
      );
    case ReminderKind.missedIn:
      if (hasIn || !now.isBefore(s.endOn(day))) return (msg: null, heldForSync: false);
      if (syncedUpTo == null || syncedUpTo.isBefore(s.cutoffOn(day))) {
        return (msg: null, heldForSync: true);
      }
      return (
        msg: NotifyMessage(
            id: id,
            title: 'No check-in for the ${s.shortName} shift',
            body: 'Nothing recorded since ${s.startLabel}. Punch now; this shift will show late.'),
        heldForSync: false,
      );
    case ReminderKind.checkOut:
      if (!hasIn || st.outTime != null || !now.isBefore(s.windowEndOn(day))) {
        return (msg: null, heldForSync: false);
      }
      return (
        msg: NotifyMessage(
            id: id,
            title: 'Check out of the ${s.shortName} shift',
            body: 'In at ${kHHmm.format(st.inTime!)}, no check-out yet. '
                'Punch before ${kHHmm.format(s.windowEndOn(day))}.'),
        heldForSync: false,
      );
  }
}

/// Decides today's due moments (time ≤ [now], not yet [handled]) for every
/// shift. A moment that is no longer needed (punched, too late, holiday,
/// leave) is marked handled; one held back because the terminal isn't
/// syncing stays open so a later run can still post it. A posted
/// check-in reminder is cancelled once the person has punched in, and a
/// check-out reminder once they have punched out.
ReminderOutcome decideReminders({
  required DateTime now,
  required EmployeeDayFacts facts,
  Set<String> handled = const {},
  Set<String> posted = const {},
}) {
  final day = dateOnly(now);
  final ordered = [...facts.shifts]..sort((a, b) => a.start.compareTo(b.start));
  final doneKeys = {...handled};
  final postedKeys = {...posted};
  final post = <NotifyMessage>[];
  final cancel = <int>[];
  if (ordered.isEmpty) {
    return ReminderOutcome(post: post, cancel: cancel, handled: doneKeys, posted: postedKeys);
  }

  final silenced =
      facts.holiday || facts.onLeave || facts.ledger.any((r) => r.status == 'On Leave');
  final sorted = [...facts.punches]..sort((a, b) => a.time.compareTo(b.time));
  final byShift = {for (final s in ordered) s.name: <EmployeeCheckin>[]};
  for (final p in sorted) {
    byShift[shiftForPunch(p.time, ordered, day).name]!.add(p);
  }
  AttendanceRecord? ledgerFor(String name) {
    for (final r in facts.ledger) {
      if (r.shift == name) return r;
    }
    return null;
  }

  final moments = shiftMoments(ordered, day);
  for (var i = 0; i < ordered.length; i++) {
    final s = ordered[i];
    final st = deriveShiftStatus(
        shift: s, day: day, now: now, punches: byShift[s.name]!, ledger: ledgerFor(s.name));
    final id = kShiftReminderIdBase + i;
    final postedIn = postedKeys.contains(momentKey(s.name, ReminderKind.headsUp)) ||
        postedKeys.contains(momentKey(s.name, ReminderKind.missedIn));
    final postedOut = postedKeys.contains(momentKey(s.name, ReminderKind.checkOut));
    if ((st.inTime != null && postedIn && !postedOut) || (st.outTime != null && postedOut)) {
      cancel.add(id);
    }

    for (final m in moments) {
      if (m.shiftIndex != i || m.at.isAfter(now) || doneKeys.contains(m.key)) continue;
      if (silenced) {
        doneKeys.add(m.key);
        continue;
      }
      final (:msg, :heldForSync) = _reminder(m, st, now, facts.syncedUpTo);
      if (heldForSync) continue; // sync hasn't caught up past the cut-off yet
      if (msg == null) {
        doneKeys.add(m.key);
        continue;
      }
      if (!facts.syncing) continue; // held back: never blame a person for the terminal
      post.add(msg);
      doneKeys.add(m.key);
      postedKeys.add(m.key);
      cancel.remove(id);
    }
  }
  return ReminderOutcome(post: post, cancel: cancel, handled: doneKeys, posted: postedKeys);
}

class RecapOutcome {
  /// The day this decision covered (yyyy-MM-dd), or null when none was found.
  final String? recapped;
  final NotifyMessage? message;

  const RecapOutcome({this.recapped, this.message});
}

String? _problem(AttendanceRecord r, Map<String, ShiftRules> catalog) {
  final label =
      r.shift.trim().isEmpty ? 'Day' : catalog[r.shift]?.shortName ?? _short(r.shift);
  if (r.status == 'Absent') return '$label: absent';
  if (r.status != 'Present') return null; // On Leave, Half Day, Work From Home
  final issues = <String>[];
  if (r.lateEntry) {
    final s = catalog[r.shift];
    final mins = s != null && r.inTime != null ? r.inTime!.difference(s.cutoffOn(r.date)).inMinutes : 0;
    issues.add(mins > 0 ? 'late $mins min' : 'late');
  }
  if (r.earlyExit) issues.add('early exit');
  if (r.outTime == null) issues.add('no check-out');
  return issues.isEmpty ? null : '$label: ${issues.join(', ')}';
}

/// The most recent of the last 3 days after [lastRecapped] that has rows. A
/// day with an Absent, Late, Early exit or No check-out row gets a message;
/// either way that day is recapped.
RecapOutcome decideRecap({
  required DateTime now,
  required List<AttendanceRecord> rows,
  required Map<String, ShiftRules> catalog,
  String? lastRecapped,
}) {
  final today = dateOnly(now);
  for (var back = 1; back <= 3; back++) {
    final d = DateTime(today.year, today.month, today.day - back);
    final key = kFrappeDate.format(d);
    if (lastRecapped != null && key.compareTo(lastRecapped) <= 0) break;
    final dayRows = rows.where((r) => kFrappeDate.format(r.date) == key).toList();
    if (dayRows.isEmpty) continue;
    Duration startOf(AttendanceRecord r) => catalog[r.shift]?.start ?? const Duration(hours: 24);
    dayRows.sort((a, b) => startOf(a).compareTo(startOf(b)));
    final parts = <String>[
      for (final r in dayRows)
        if (_problem(r, catalog) != null) _problem(r, catalog)!,
    ];
    if (parts.isEmpty) return RecapOutcome(recapped: key);
    final title =
        back == 1 ? "Yesterday's attendance" : 'Attendance on ${DateFormat('EEE d MMM').format(d)}';
    return RecapOutcome(
      recapped: key,
      message: NotifyMessage(id: kRecapNotificationId, title: title, body: '${parts.join(' · ')}.'),
    );
  }
  return const RecapOutcome();
}

class TerminalOutcome {
  final bool quiet;
  final NotifyMessage? message;

  const TerminalOutcome({required this.quiet, this.message});
}

/// Alerts System Managers only when the sync state changes. The first watch
/// of a session ([wasQuiet] null) alerts only if the sync is quiet.
TerminalOutcome decideTerminal({required DateTime now, required SyncStatus? status, bool? wasQuiet}) {
  final quiet = !isSyncing(status, now);
  if (quiet == wasQuiet) return TerminalOutcome(quiet: quiet);
  if (!quiet) {
    return TerminalOutcome(
      quiet: false,
      message: wasQuiet == null
          ? null
          : NotifyMessage(
              id: kTerminalNotificationId,
              title: 'Attendance terminal back',
              body: 'Syncing again since ${kHHmm.format(now)}.',
              terminal: true),
    );
  }
  final since = quietSince(status);
  return TerminalOutcome(
    quiet: true,
    message: NotifyMessage(
      id: kTerminalNotificationId,
      title: 'Attendance terminal quiet',
      body: since == null
          ? "The sync status can't be read. Check-ins may not be arriving; staff reminders are paused."
          : 'No sync since ${kHHmm.format(since)}. Check-ins may not be arriving; staff reminders are paused.',
      terminal: true,
    ),
  );
}
