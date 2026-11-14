/// What the attendance worker remembers between runs. Kept in its own
/// GetStorage container ([kAttendanceStateBox]) that ONLY the background
/// worker writes — the main isolate never touches it, so there is no
/// cross-isolate last-writer-wins on the main box (see digest_worker.dart).
library;

const String kAttendanceStateBox = 'attendance_notify';
const String kAttendanceStateKey = 'state';

class AttendanceNotifyState {
  final String user;

  /// yyyy-MM-dd the [handled] / [posted] keys belong to.
  final String day;

  /// `<shift>|<kind>` moments already decided today (posted or not needed).
  final Set<String> handled;

  /// `<shift>|<kind>` moments actually posted today.
  final Set<String> posted;

  /// Last day a recap decision covered (yyyy-MM-dd).
  final String? lastRecapped;

  /// Day the recap was last evaluated (it runs once per day).
  final String? recapRunDay;

  /// Terminal state at the last watch; null before the first watch.
  final bool? terminalQuiet;

  /// Day the "session expired" notice was last posted.
  final String? lastAuthNotice;

  const AttendanceNotifyState({
    required this.user,
    required this.day,
    this.handled = const {},
    this.posted = const {},
    this.lastRecapped,
    this.recapRunDay,
    this.terminalQuiet,
    this.lastAuthNotice,
  });

  /// Reads [raw] for [user] on [today]: another user's state is discarded; a
  /// previous day's handled/posted keys are dropped and the rest kept.
  factory AttendanceNotifyState.fromMap(Object? raw,
      {required String user, required String today}) {
    if (raw is! Map || raw['user'] != user) {
      return AttendanceNotifyState(user: user, day: today);
    }
    Set<String> set(Object? v) => v is List ? v.map((e) => '$e').toSet() : <String>{};
    String? readString(Object? v) => v is String ? v : null;
    bool? readBool(Object? v) => v is bool ? v : null;
    final sameDay = raw['day'] == today;
    return AttendanceNotifyState(
      user: user,
      day: today,
      handled: sameDay ? set(raw['handled']) : const {},
      posted: sameDay ? set(raw['posted']) : const {},
      lastRecapped: readString(raw['lastRecapped']),
      recapRunDay: readString(raw['recapRunDay']),
      terminalQuiet: readBool(raw['terminalQuiet']),
      lastAuthNotice: readString(raw['lastAuthNotice']),
    );
  }

  Map<String, dynamic> toMap() => {
        'user': user,
        'day': day,
        'handled': handled.toList()..sort(),
        'posted': posted.toList()..sort(),
        'lastRecapped': lastRecapped,
        'recapRunDay': recapRunDay,
        'terminalQuiet': terminalQuiet,
        'lastAuthNotice': lastAuthNotice,
      };

  AttendanceNotifyState copyWith({
    Set<String>? handled,
    Set<String>? posted,
    String? lastRecapped,
    String? recapRunDay,
    bool? terminalQuiet,
    String? lastAuthNotice,
  }) =>
      AttendanceNotifyState(
        user: user,
        day: day,
        handled: handled ?? this.handled,
        posted: posted ?? this.posted,
        lastRecapped: lastRecapped ?? this.lastRecapped,
        recapRunDay: recapRunDay ?? this.recapRunDay,
        terminalQuiet: terminalQuiet ?? this.terminalQuiet,
        lastAuthNotice: lastAuthNotice ?? this.lastAuthNotice,
      );
}
