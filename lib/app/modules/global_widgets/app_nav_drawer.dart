import 'package:flutter/material.dart';
import 'package:get/get.dart';
// Import AuthenticationController
import 'package:ddmco_multimax/app/modules/auth/authentication_controller.dart';
import 'package:ddmco_multimax/app/modules/home/home_controller.dart';

class AppNavDrawer extends StatelessWidget {
  const AppNavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final HomeController homeController = Get.find<HomeController>();
    // Get the global AuthenticationController instance
    final AuthenticationController authController = Get.find<AuthenticationController>();

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
            child: const Text(
              'App Menu',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ),
          // ... other list items for navigation (Home, Stock Entry, etc.)
          Obx(() => ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Home'),
            selected: homeController.selectedDrawerIndex.value == 0,
            onTap: homeController.goToHome,
          )),
          Obx(() => ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Stock Entry'),
            selected: homeController.selectedDrawerIndex.value == 1,
            onTap: homeController.goToStockEntry,
          )),
          Obx(() => ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: const Text('Delivery Note'),
            selected: homeController.selectedDrawerIndex.value == 2,
            onTap: homeController.goToDeliveryNote,
          )),
          Obx(() => ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Packing Slip'),
            selected: homeController.selectedDrawerIndex.value == 3,
            onTap: homeController.goToPackingSlip,
          )),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () {
              Get.back(); // Close the drawer first
              authController.logoutUser(); // Call logout from AuthenticationController
            },
          ),
        ],
      ),
    );
  }
}
