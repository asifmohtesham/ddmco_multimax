import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock_sheet/logic/reading_status.dart';
import 'package:multimax/app/modules/stock_sheet/model/review_models.dart';

ReviewEntry e(int n, ReadStage s) =>
    ReviewEntry(path: 'p$n', number: n, stage: s);

void main() {
  test('round one names the photo being read', () {
    final s = ReadingStatus.of([
      e(1, ReadStage.checkingStock),
      e(2, ReadStage.reading),
      e(3, ReadStage.notRead)
    ])!;
    expect(s.label, 'Reading photo 2 of 3');
    expect(s.tally, '1 read');
    expect(s.progress, closeTo(1 / 3, 1e-9));
  });

  test('round two names the photo being zoomed in on and what is left', () {
    final s = ReadingStatus.of([
      e(1, ReadStage.settled),
      e(2, ReadStage.zooming),
      e(3, ReadStage.waiting)
    ])!;
    expect(s.label, 'Zooming in on photo 2 of 3…');
    expect(s.tally, '1 read · 2 to go');
  });

  test('between photos in round two the label has no number', () {
    final s =
        ReadingStatus.of([e(1, ReadStage.settled), e(2, ReadStage.waiting)])!;
    expect(s.label, 'Zooming in…');
  });

  test('reading done, stock outstanding', () {
    final s = ReadingStatus.of(
        [e(1, ReadStage.settled), e(2, ReadStage.checkingStock)])!;
    expect(s.label, 'Checking stock…');
    expect(s.tally, '2 read');
    expect(s.progress, 1);
  });

  test('nothing outstanding, or an empty list, gives no strip', () {
    expect(ReadingStatus.of([e(1, ReadStage.settled)]), isNull);
    expect(ReadingStatus.of(const []), isNull);
  });

  test('a photo removed leaves the numbers of the others alone', () {
    final s =
        ReadingStatus.of([e(1, ReadStage.settled), e(3, ReadStage.zooming)])!;
    expect(s.label, 'Zooming in on photo 3 of 3…');
    expect(s.tally, '1 read · 1 to go');
  });
}
