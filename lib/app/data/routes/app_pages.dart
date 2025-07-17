import 'package:ddmco_multimax/app/modules/home/home_screen.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/auth/login_screen.dart'; // Update path
import 'package:ddmco_multimax/app/modules/auth/login_controller.dart'; // For bindings
import 'package:ddmco_multimax/app/modules/home/home_binding.dart';     // Update path
import 'package:ddmco_multimax/app/modules/home/home_screen.dart';       // Update path
import 'package:ddmco_multimax/app/modules/stock_entry/stock_entry_binding.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/stock_entry_screen.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/delivery_note_binding.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/delivery_note_screen.dart';
import 'package:ddmco_multimax/app/modules/packing_slip/packing_slip_binding.dart';
import 'package:ddmco_multimax/app/modules/packing_slip/packing_slip_screen.dart';

import 'app_routes.dart';

class AppPages {
  static const INITIAL = AppRoutes.LOGIN; // Or check if user is logged in and route to HOME

  static final routes = [
    GetPage(
      name: AppRoutes.LOGIN,
      page: () => const LoginScreen(),
      // It's good practice to use bindings for controllers
      binding: BindingsBuilder(() {
        Get.lazyPut<LoginController>(() => LoginController());
        // ApiProvider should ideally be registered globally in main.dart or an initial binding
      }),
    ),
    GetPage(
      name: AppRoutes.HOME,
      page: () => const HomeScreen(),
      binding: HomeBinding(), // Create HomeBinding
    ),
    GetPage(
      name: AppRoutes.STOCK_ENTRY,
      page: () => const StockEntryScreen(),
      binding: StockEntryBinding(), // Create StockEntryBinding
    ),
    GetPage(
      name: AppRoutes.DELIVERY_NOTE,
      page: () => const DeliveryNoteScreen(),
      binding: DeliveryNoteBinding(), // Create DeliveryNoteBinding
    ),
    GetPage(
      name: AppRoutes.PACKING_SLIP,
      page: () => const PackingSlipScreen(),
      binding: PackingSlipBinding(), // Create PackingSlipBinding
    ),
  ];
}
