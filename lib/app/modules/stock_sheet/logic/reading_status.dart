import '../model/review_models.dart';

/// The text and progress of the strip above the review list while photos are
/// still being read, zoomed in on or checked for stock.
class ReadingStatus {
  const ReadingStatus({
    required this.label,
    required this.tally,
    required this.progress,
  });

  final String label;
  final String tally;

  /// 0..1: the share of photos read.
  final double progress;

  static const _reading = {
    ReadStage.notRead,
    ReadStage.reading,
    ReadStage.waiting,
    ReadStage.zooming,
  };

  /// Null when every row is settled (the strip is hidden). Counts photos
  /// (distinct paths), not rows; N is the highest [ReviewEntry.number].
  static ReadingStatus? of(List<ReviewEntry> entries) {
    if (entries.every((e) => e.settled)) return null;

    final unread = <String>{};
    final photos = <String>{};
    var total = 0;
    for (final e in entries) {
      photos.add(e.path);
      if (_reading.contains(e.stage)) unread.add(e.path);
      if (e.number > total) total = e.number;
    }
    final read = photos.length - unread.length;

    ReviewEntry? first(ReadStage s) {
      for (final e in entries) {
        if (e.stage == s) return e;
      }
      return null;
    }

    final reading = first(ReadStage.reading);
    final zooming = first(ReadStage.zooming);
    final notRead = first(ReadStage.notRead);
    final String label;
    if (reading != null) {
      label = 'Reading photo ${reading.number} of $total';
    } else if (zooming != null) {
      label = 'Zooming in on photo ${zooming.number} of $total…';
    } else if (notRead != null) {
      label = 'Reading photo ${notRead.number} of $total';
    } else if (first(ReadStage.waiting) != null) {
      label = 'Zooming in…';
    } else {
      label = 'Checking stock…';
    }

    final tally =
        unread.isEmpty ? '$read read' : '$read read · ${unread.length} to go';
    // Round one (photos still being read in order) shows only the count read;
    // round two adds how many are left.
    final roundOne = reading != null || (zooming == null && notRead != null);
    return ReadingStatus(
      label: label,
      tally: roundOne ? '$read read' : tally,
      progress: photos.isEmpty ? 0 : read / photos.length,
    );
  }
}
