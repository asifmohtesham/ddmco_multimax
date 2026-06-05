/// Result state of the most recent save attempt.
///
/// Used by [SaveIconButton] (and forwarded through [MainAppBar]) to show
/// animated feedback after a save completes.
///
/// In-flight / saving state is **not** represented here — it is driven by
/// the separate `isSaving` bool that triggers the spinner.
enum SaveResult {
  /// No save has been attempted yet, or the previous result has been cleared.
  idle,

  /// The most recent save completed successfully.
  success,

  /// The most recent save failed.
  error,
}
