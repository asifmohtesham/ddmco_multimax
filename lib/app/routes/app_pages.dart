// ADD TO EXISTING app_pages.dart

import 'package:get/get.dart';
import 'package:multimax/app/modules/manufacturing/bom/bom_binding.dart';
import 'package:multimax/app/modules/manufacturing/bom/bom_screen.dart';
import 'package:multimax/app/modules/manufacturing/work_order/work_order_binding.dart';
import 'package:multimax/app/modules/manufacturing/work_order/work_order_screen.dart';
import 'package:multimax/app/modules/manufacturing/job_card/job_card_binding.dart';
import 'package:multimax/app/modules/manufacturing/job_card/job_card_screen.dart';

// ADD TO ROUTES CLASS:
class Routes {
  // ... existing routes ...
  
  // Manufacturing Routes
  static const MANUFACTURING_BOM = '/manufacturing/bom';
  static const MANUFACTURING_WORK_ORDERS = '/manufacturing/work-orders';
  static const MANUFACTURING_JOB_CARDS = '/manufacturing/job-cards';
}

// ADD TO PAGES LIST:
class AppPages {
  static final routes = [
    // ... existing routes ...
    
    // Manufacturing Module
    GetPage(
      name: Routes.MANUFACTURING_BOM,
      page: () => const BomScreen(),
      binding: BomBinding(),
      transition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 200),
    ),
    GetPage(
      name: Routes.MANUFACTURING_WORK_ORDERS,
      page: () => const WorkOrderScreen(),
      binding: WorkOrderBinding(),
      transition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 200),
    ),
    GetPage(
      name: Routes.MANUFACTURING_JOB_CARDS,
      page: () => const JobCardScreen(),
      binding: JobCardBinding(),
      transition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 200),
    ),
  ];
}