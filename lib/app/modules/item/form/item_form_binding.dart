import 'package:flutter/widgets.dart' show Route;
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/providers/warehouse_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/item/form/item_tab_controller.dart';

class ItemFormBinding extends Bindings {
  static final _routeTags = Expando<String>();
  static int _lastTag = 0;

  /// Gives each named Item form its own document and tab state.
  static String? tagForRoute(Route<dynamic>? route) {
    if (route == null || route.settings.name != AppRoutes.ITEM_FORM) {
      return null;
    }
    return _routeTags[route] ??= (++_lastTag).toString();
  }

  @override
  void dependencies() {
    final route = Get.routing.route;
    final tag = tagForRoute(route);
    final arguments = route?.settings.arguments;
    Get.lazyPut<ItemTabController>(
      () => ItemTabController(formTag: tag),
      tag: tag,
      fenix: tag == null,
    );
    Get.lazyPut<ItemFormController>(
      () => ItemFormController(
        readArguments: tag == null ? null : () => arguments,
      ),
      tag: tag,
      fenix: tag == null,
    );
    Get.lazyPut<WarehouseProvider>(() => WarehouseProvider(), fenix: true);
    Get.lazyPut<ItemProvider>(() => ItemProvider(), fenix: true);
  }
}
