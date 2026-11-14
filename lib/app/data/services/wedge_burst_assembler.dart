/// Pure-Dart timing state machine that assembles HID keyboard-wedge bursts
/// into a single barcode string.
///
/// Feed printable characters via [addChar] and the terminator (Enter) via
/// [terminate]. The machine owns ALL timing state — callers never recompute
/// gaps themselves; they use the bool returned by [addChar] for their
/// consume decision so the consume rule and the buffer-reset rule cannot
/// diverge.
///
/// A burst is "in cadence" while consecutive keystrokes arrive within
/// [maxGapMs] of each other. A gap >= [maxGapMs] starts a fresh burst.
class WedgeBurstAssembler {
  WedgeBurstAssembler({this.maxGapMs = 50});

  /// Maximum inter-key gap (ms) for two keystrokes to count as one burst.
  final int maxGapMs;

  final StringBuffer _buffer = StringBuffer();
  int? _lastTs;

  /// Appends [char] to the current burst.
  ///
  /// Returns `true` when [char] is in cadence (a continuation of the current
  /// burst). Returns `false` when the gap since the last key is `>= maxGapMs`
  /// or this is the first key — in that case a fresh burst is started holding
  /// only [char].
  bool addChar(String char, int timestampMs) {
    final last = _lastTs;
    _lastTs = timestampMs;

    if (last == null || (timestampMs - last) >= maxGapMs) {
      _buffer
        ..clear()
        ..write(char);
      return false;
    }

    _buffer.write(char);
    return true;
  }

  /// Finalises the current burst.
  ///
  /// Returns the assembled code when the buffer is non-empty AND the gap from
  /// the last char to this terminator is `< maxGapMs`; otherwise `null`.
  /// Always clears state.
  String? terminate(int timestampMs) {
    final last = _lastTs;
    final inCadence =
        _buffer.isNotEmpty && last != null && (timestampMs - last) < maxGapMs;
    final code = inCadence ? _buffer.toString() : null;
    reset();
    return code;
  }

  /// Clears the buffer and last-timestamp.
  void reset() {
    _buffer.clear();
    _lastTs = null;
  }
}
