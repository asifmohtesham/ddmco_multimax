import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/app_bottom_bar.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:ddmco_multimax/app/modules/home/home_controller.dart';
import 'package:ddmco_multimax/app/data/routes/app_pages.dart'; // For initial route logic
import 'package:ddmco_multimax/app/data/routes/app_routes.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/stock_entry_screen.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/delivery_note_screen.dart';
import 'package:ddmco_multimax/app/modules/packing_slip/packing_slip_screen.dart';

// Placeholder screens for navigation targets
class ActualHomeScreenContent extends StatelessWidget { // Replace with your actual Home content
  const ActualHomeScreenContent({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text("Main Home Content Area"));
}
// class StockEntryScreen extends StatelessWidget {
//   const StockEntryScreen({super.key});
//   @override
//   Widget build(BuildContext context) => const Center(child: Text("Stock Entry Screen"));
// }
// class DeliveryNoteScreen extends StatelessWidget {
//   const DeliveryNoteScreen({super.key});
//   @override
//   Widget build(BuildContext context) => const Center(child: Text("Delivery Note Screen"));
// }
// class PackingSlipScreen extends StatelessWidget {
//   const PackingSlipScreen({super.key});
//   @override
//   Widget build(BuildContext context) => const Center(child: Text("Packing Slip Screen"));
// }


class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  Widget _buildPage(String route) {
    switch (route) {
      case AppRoutes.HOME:
        return const ActualHomeScreenContent(); // Your actual home page content
      case AppRoutes.STOCK_ENTRY:
        return const StockEntryScreen(); // Your Stock Entry page
      case AppRoutes.DELIVERY_NOTE:
        return const DeliveryNoteScreen(); // Your Delivery Note page
      case AppRoutes.PACKING_SLIP:
        return const PackingSlipScreen(); // Your Packing Slip page
      default:
        return const Center(child: Text("Page not found"));
    }
  }


  @override
  Widget build(BuildContext context) {
    // The HomeController will be managed by its binding (HomeBinding)
    return Obx(() => Scaffold( // Obx rebuilds when activeScreen changes title
      appBar: AppBar(
        title: Text(_getAppBarTitle(controller.activeScreen.value)),
        // Add actions or other app bar items if needed
      ),
      drawer: const AppNavDrawer(),
      body: _buildPage(Get.currentRoute), // Display content based on current route
      // or manage a body widget in HomeController
      bottomNavigationBar: const AppBottomBar(),
    ));
  }

  String _getAppBarTitle(ActiveScreen screen) {
    switch (screen) {
      case ActiveScreen.home:
        return "Home";
      case ActiveScreen.stockEntry:
        return "Stock Entry";
      case ActiveScreen.deliveryNote:
        return "Delivery Note";
      case ActiveScreen.packingSlip:
        return "Packing Slip";
      default:
        return "App";
    }
  }
}
