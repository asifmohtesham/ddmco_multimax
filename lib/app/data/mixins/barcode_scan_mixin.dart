import 'package:get/get.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

/// Mixin that gives any GetxController automatic DataWedge scan wiring
/// and a single override point [onScanResult] to implement per-screen logic.
///
/// SOLID alignment:
///  - SRP : this mixin owns only the "receive scan → classify → dispatch" flow.
///  - OCP : screens extend behaviour by overriding [onScanResult]; the mixin
///           itself never needs to change when a new screen is added.
///  - LSP : every controller that uses this mixin can substitute for a
///           "barcode-aware controller" without breaking callers.
///  - ISP : controllers that don't need scanning simply don't use the mixin.
///  - DIP : depends on [ScanService] abstraction, not on screen-specific logic.
mixin BarcodeScanMixin on GetxController {
  final ScanService       _scanSvc  = Get.find<ScanService>();
  final DataWedgeService  _dwSvc    = Get.find<DataWedgeService>();

  var isScanning = false.obs;
  Worker? _scanWorker;

  // ── Hook: implement in each controller ───────────────────────────────────────

  /// Called with a fully-resolved [ScanResult] after deduplication and
  /// guard checks.  Each controller handles only its own reaction here.
  Future<void> onScanResult(ScanResult result);

  /// Return true to block scanning (e.g. sheet is open, doc is stale).
  /// Default: always allow.
  bool shouldBlockScan() => false;

  // ── Internal wiring ──────────────────────────────────────────────────────────

  void initScanWiring() {
    _scanWorker = ever(_dwSvc.scannedCode, (String code) {
      if (code.isNotEmpty) _dispatchScan(code);
    });
  }

  void disposeScanWiring() {
    _scanWorker?.dispose();
  }

  Future<void> _dispatchScan(String barcode) async {
    if (isClosed)           return;
    if (barcode.isEmpty)    return;
    if (isScanning.value)   return;
    if (shouldBlockScan())  return;

    isScanning.value = true;
    try {
      final result = await _scanSvc.processScan(barcode);
      await onScanResult(result);
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan processing error: $e');
    } finally {
      isScanning.value = false;
    }
  }

  /// Public entry point for manual / text-field initiated scans.
  Future<void> scanBarcode(String barcode) => _dispatchScan(barcode);
}
