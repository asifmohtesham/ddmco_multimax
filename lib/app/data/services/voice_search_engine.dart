/// The listening lifecycle the [VoiceSearchSheet] reacts to.
enum VoiceEngineState {
  /// Actively capturing audio.
  listening,

  /// The recognizer finished a session (final result delivered or timed out).
  done,

  /// No speech recognizer is available on this device.
  notAvailable,

  /// The user denied (or has not granted) the microphone permission.
  permissionDenied,

  /// A recoverable engine error occurred mid-session.
  error,
}

/// Small, mockable surface over a speech-to-text backend.
///
/// Kept free of any `speech_to_text` types so the sheet and its widget tests
/// depend only on this interface (see [SttVoiceSearchEngine] for the concrete
/// plugin-backed implementation).
abstract class VoiceSearchEngine {
  /// Initializes (idempotent), resolves the locale, and begins listening.
  ///
  /// [onResult] receives the recognized text and whether it is the final
  /// result. [onState] receives lifecycle transitions. Implementations must
  /// never throw — failures are reported through [onState].
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
    required void Function(VoiceEngineState state) onState,
  });

  /// Gracefully finishes the session, allowing a final result to arrive.
  Future<void> stop();

  /// Discards the session without producing a final result.
  Future<void> cancel();
}

/// Picks the recognition locale id from the recognizer's [availableIds].
///
/// Preference order: the device locale (matched case-insensitively and
/// tolerant of `-`/`_` separators), then `en_GB`, then `en_US`, then `null`
/// (let the engine use its own default).
String? resolveLocaleId(List<String> availableIds, String deviceLocaleId) {
  String norm(String s) => s.toLowerCase().replaceAll('-', '_');

  final wanted = norm(deviceLocaleId);
  for (final id in availableIds) {
    if (norm(id) == wanted) return id;
  }
  for (final id in availableIds) {
    if (norm(id) == 'en_gb') return id;
  }
  for (final id in availableIds) {
    if (norm(id) == 'en_us') return id;
  }
  return null;
}
