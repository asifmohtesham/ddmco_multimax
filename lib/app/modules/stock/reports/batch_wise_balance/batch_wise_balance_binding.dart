import 'package:flutter/widgets.dart' show Route;
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/stock/reports/batch_wise_balance/batch_wise_balance_controller.dart';

class BatchWiseBalanceBinding extends Bindings {
  static final _routeTags = Expando<String>();
  static int _lastTag = 0;

  static String? tagForRoute(Route<dynamic>? route) {
    if (route == null || route.settings.name != AppRoutes.BATCH_WISE_BALANCE) {
      return null;
    }
    return _routeTags[route] ??= (++_lastTag).toString();
  }

  @override
  void dependencies() {
    Get.lazyPut<BatchWiseBalanceController>(
      BatchWiseBalanceController.new,
      tag: tagForRoute(Get.routing.route),
    );
  }
}
