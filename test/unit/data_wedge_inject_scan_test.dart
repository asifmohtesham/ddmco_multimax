import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';

void main() {
  // Construct the service directly (no Get lifecycle) so onInit / the native
  // EventChannel listener never runs.
  group('DataWedgeService.injectScan', () {
    test('sets scannedCode synchronously then clears after the hold', () async {
      final dw = DataWedgeService();

      dw.injectScan('6928804014662');
      // _processQueue runs synchronously up to its first await, so the value
      // is visible immediately.
      expect(dw.scannedCode.value, '6928804014662');

      // Drain the 800ms hold + 100ms gap so no timer is left pending.
      await Future.delayed(const Duration(milliseconds: 950));
      expect(dw.scannedCode.value, '');
    });

    test('ignores an empty code', () {
      final dw = DataWedgeService();
      dw.injectScan('');
      expect(dw.scannedCode.value, '');
    });
  });
}
