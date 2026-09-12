/// When the attendance worker wakes (spec 2026-09-12 §4.2) and the heartbeat
/// rule (spec #0 §5). Pure and GetX-free — runs in the background isolate.
library;

import 'package:multimax/app/data/models/attendance_models.dart';

enum ReminderKind { headsUp, missedIn, checkOut }

const Duration kHeadsUpLead = Duration(minutes: 10);
const Duration kCheckOutLag = Duration(minutes: 10);
const Duration kSyncFreshness = Duration(minutes: 20);
const Duration kWatchStep = Duration(minutes: 30);

/// One reminder moment of one shift on one day.
class ShiftMoment {
  final ReminderKind kind;

  /// 0 = the day's first shift, 1 = the second (notification id offset).
  final int shiftIndex;
  final ShiftRules shift;
  final DateTime at;

  const ShiftMoment(
      {required this.kind, required this.shiftIndex, required this.shift, required this.at});

  /// `<shift>|<kind>` — the handled/posted key in the worker state.
  String get key => momentKey(shift.name, kind);
}

/// The worker-state key for one shift's reminder moment: `<shift>|<kind>`.
String momentKey(String shiftName, ReminderKind kind) => '$shiftName|${kind.name}';

/// Heads-up (cut-off − 10), missed check-in (cut-off) and check-out
/// (end + 10) for each of [shifts] on [day], in time order.
List<ShiftMoment> shiftMoments(List<ShiftRules> shifts, DateTime day) {
  final ordered = [...shifts]..sort((a, b) => a.start.compareTo(b.start));
  final out = <ShiftMoment>[];
  for (var i = 0; i < ordered.length; i++) {
    final s = ordered[i];
    final cut = s.cutoffOn(day);
    out
      ..add(ShiftMoment(kind: ReminderKind.headsUp, shiftIndex: i, shift: s, at: cut.subtract(kHeadsUpLead)))
      ..add(ShiftMoment(kind: ReminderKind.missedIn, shiftIndex: i, shift: s, at: cut))
      ..add(ShiftMoment(kind: ReminderKind.checkOut, shiftIndex: i, shift: s, at: s.endOn(day).add(kCheckOutLag)));
  }
  return out..sort((a, b) => a.at.compareTo(b.at));
}

DateTime recapTimeOn(DateTime day) => DateTime(day.year, day.month, day.day, 7, 30);

/// 06:00–22:00 inclusive: when System Managers' terminal watch runs.
bool inWatchHours(DateTime now) {
  final d = dateOnly(now);
  return !now.isBefore(DateTime(d.year, d.month, d.day, 6)) &&
      !now.isAfter(DateTime(d.year, d.month, d.day, 22));
}

/// The 05:55 planning run: today if it is still ahead, else tomorrow.
DateTime planningRunAfter(DateTime now) {
  final today = DateTime(now.year, now.month, now.day, 5, 55);
  return now.isBefore(today) ? today : DateTime(now.year, now.month, now.day + 1, 5, 55);
}

DateTime? _nextWatchSlot(DateTime now) {
  final d = dateOnly(now);
  final end = DateTime(d.year, d.month, d.day, 22);
  for (var t = DateTime(d.year, d.month, d.day, 6); !t.isAfter(end); t = t.add(kWatchStep)) {
    if (t.isAfter(now)) return t;
  }
  return null;
}

/// The next time after [now] the worker must run: the next shift moment,
/// the 07:30 recap ([recap], working days only), the next terminal watch
/// slot ([terminalWatch] alone — [workingDay] does not gate it, since the
/// caller decides which calendar the watch follows) — else the planning run.
DateTime nextAttendanceWake({
  required DateTime now,
  required List<ShiftMoment> moments,
  required bool workingDay,
  required bool recap,
  required bool terminalWatch,
}) {
  final day = dateOnly(now);
  final watch = terminalWatch ? _nextWatchSlot(now) : null;
  final candidates = <DateTime>[
    for (final m in moments)
      if (m.at.isAfter(now)) m.at,
    if (workingDay && recap && recapTimeOn(day).isAfter(now)) recapTimeOn(day),
    if (watch != null) watch,
  ];
  if (candidates.isEmpty) return planningRunAfter(now);
  return candidates.reduce((a, b) => a.isBefore(b) ? a : b);
}

/// Syncing ⇔ agent and terminal both seen within 20 min and the terminal is
/// online. Anything else — including an unreadable document — is unknown.
bool isSyncing(SyncStatus? s, DateTime now) =>
    s != null &&
    s.terminalOnline &&
    s.agentLastRun != null &&
    s.terminalLastSeen != null &&
    now.difference(s.agentLastRun!) <= kSyncFreshness &&
    now.difference(s.terminalLastSeen!) <= kSyncFreshness;

/// Since when the sync looks quiet: the older of the two heartbeat times.
DateTime? quietSince(SyncStatus? s) {
  final times = [
    if (s?.agentLastRun != null) s!.agentLastRun!,
    if (s?.terminalLastSeen != null) s!.terminalLastSeen!,
  ];
  if (times.isEmpty) return null;
  return times.reduce((a, b) => a.isBefore(b) ? a : b);
}
