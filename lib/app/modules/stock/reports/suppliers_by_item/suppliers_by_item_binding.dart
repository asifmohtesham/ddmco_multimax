import 'package:flutter/widgets.dart' show Route;
import 'package:get/get.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_controller.dart';

class SuppliersByItemBinding extends Bindings {
  static final _routeTags = Expando<String>();
  static int _lastTag = 0;

  /// A report opened from an Item can sit above another report in the stack.
  static String? tagForRoute(Route<dynamic>? route) {
    if (route == null || route.settings.name != AppRoutes.SUPPLIERS_BY_ITEM) {
      return null;
    }
    return _routeTags[route] ??= (++_lastTag).toString();
  }

  @override
  void dependencies() {
    final route = Get.routing.route;
    final preset = route?.settings.arguments;
    Get.lazyPut<SuppliersByItemController>(
      () => SuppliersByItemController(
        api: Get.find<ApiProvider>(),
        initialFilters: preset is SuppliersByItemFilters
            ? preset
            : const SuppliersByItemFilters(),
        resolveBarcode: Get.isRegistered<ScanService>()
            ? Get.find<ScanService>().resolveItemBarcode
            : null,
      ),
      tag: tagForRoute(route),
    );
  }
}
