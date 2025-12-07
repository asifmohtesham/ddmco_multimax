import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/auth/authentication_controller.dart';
import 'package:ddmco_multimax/app/modules/home/home_controller.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart';

class AppNavDrawer extends StatelessWidget {
  const AppNavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final HomeController homeController = Get.find<HomeController>();
    final AuthenticationController authController = Get.find<AuthenticationController>();

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          Obx(() {
            final user = authController.currentUser.value;
            return UserAccountsDrawerHeader(
              accountName: Text(user?.name ?? 'Guest'),
              accountEmail: Text(user?.email ?? 'Not logged in'),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Text(
                  user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'G',
                  style: const TextStyle(fontSize: 40.0),
                ),
              ),
              onDetailsPressed: () {
                Get.back(); // Close drawer
                Get.toNamed(AppRoutes.PROFILE);
              },
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
              ),
              otherAccountsPictures: [
                if (user?.designation != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Chip(
                      label: Text(
                        user!.designation!,
                        style: const TextStyle(fontSize: 10),
                      ),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.white,
                    ),
                  ),
              ],
            );
          }),
          Obx(() => ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Home'),
            selected: homeController.selectedDrawerIndex.value == 0,
            onTap: homeController.goToHome,
          )),
          Obx(() => ListTile(
            leading: const Icon(Icons.check_box_outlined),
            title: const Text('ToDo'),
            selected: homeController.selectedDrawerIndex.value == 6,
            onTap: homeController.goToToDo,
          )),
          Obx(() => ListTile(
            leading: const Icon(Icons.receipt_outlined),
            title: const Text('Purchase Receipt'),
            selected: homeController.selectedDrawerIndex.value == 4,
            onTap: homeController.goToPurchaseReceipt,
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
          Obx(() => ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('POS Upload'),
            selected: homeController.selectedDrawerIndex.value == 5,
            onTap: homeController.goToPosUpload,
          )),
          const Divider(),
          Obx(() => ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Items'),
            selected: homeController.selectedDrawerIndex.value == 7,
            onTap: homeController.goToItem,
          )),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () {
              Get.back(); // Close the drawer first
              authController.logoutUser();
            },
          ),
        ],
      ),
    );
  }
}