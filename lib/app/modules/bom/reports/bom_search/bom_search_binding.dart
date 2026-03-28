import 'package:get/get.dart';
import 'package:multimax/app/data/providers/bom_provider.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/modules/bom/reports/bom_search/bom_search_controller.dart';

class BomSearchBinding extends Bindings {
  @override
  void dependencies() {
    // ── App-level singletons ─────────────────────────────────────────
    // DataWedgeService and ScanService are permanent app-wide singletons
    // normally registered at startup. The guards below are a safety net
    // for any navigation path that reaches BOM Search before the standard
    // initialisation has run (e.g. deep-link, hot-reload, test harness).
    if (!Get.isRegistered<DataWedgeService>()) {
      Get.put<DataWedgeService>(DataWedgeService(), permanent: true);
    }
    if (!Get.isRegistered<ScanService>()) {
      Get.put<ScanService>(ScanService(), permanent: true);
    }

    // ── Route-scoped dependencies ─────────────────────────────────
    // lazyPut is a no-op when the dependency is already in the registry,
    // so these are safe to call even if BomProvider was already registered
    // by the BOM list binding.
    Get.lazyPut<BomProvider>(() => BomProvider());
    Get.lazyPut<BomSearchController>(() => BomSearchController());
  }
}
