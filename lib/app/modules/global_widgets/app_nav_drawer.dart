import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/auth/authentication_controller.dart';
import 'package:ddmco_multimax/app/modules/home/home_controller.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/role_guard.dart';

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
                Get.back();
                Get.toNamed(AppRoutes.PROFILE);
              },
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
              otherAccountsPictures: [
                if (user?.designation != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Chip(
                      label: Text(user!.designation!, style: const TextStyle(fontSize: 10)),
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

          RoleGuard(
            roles: const ['Stock Manager', 'Purchase User'],
            child: ExpansionTile(
              leading: const Icon(Icons.shopping_bag_outlined),
              title: const Text('Buying'),
              children: [
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Purchase Order'),
                  onTap: () {
                    Get.back();
                    Get.toNamed(AppRoutes.PURCHASE_ORDER);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_outlined),
                  title: const Text('Purchase Receipt'),
                  onTap: () {
                    Get.back();
                    Get.toNamed(AppRoutes.PURCHASE_RECEIPT);
                  },
                ),
              ],
            ),
          ),

          RoleGuard(
            roles: const ['Stock Manager', 'Stock User'],
            child: Obx(() => ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Stock Entry'),
              selected: homeController.selectedDrawerIndex.value == 1,
              onTap: homeController.goToStockEntry,
            )),
          ),

          RoleGuard(
            roles: const ['Stock Manager', 'Stock User', 'Sales User'],
            child: Obx(() => ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: const Text('Delivery Note'),
              selected: homeController.selectedDrawerIndex.value == 2,
              onTap: homeController.goToDeliveryNote,
            )),
          ),

          RoleGuard(
            roles: const ['Stock Manager', 'Stock User'],
            child: Obx(() => ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Packing Slip'),
              selected: homeController.selectedDrawerIndex.value == 3,
              onTap: homeController.goToPackingSlip,
            )),
          ),

          RoleGuard(
            roles: const ['Sales User', 'Accounts User', 'Stock Manager'],
            child: Obx(() => ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('POS Upload'),
              selected: homeController.selectedDrawerIndex.value == 5,
              onTap: homeController.goToPosUpload,
            )),
          ),

          const Divider(),

          RoleGuard(
            roles: const ['Stock Manager', 'Item Manager'],
            child: Obx(() => ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Items'),
              selected: homeController.selectedDrawerIndex.value == 7,
              onTap: homeController.goToItem,
            )),
          ),

          // Add this block inside the ListView children, before Logout
          RoleGuard(
            roles: const ['Manufacturing Manager', 'Production Manager', 'System Manager'],
            child: ExpansionTile(
              leading: const Icon(Icons.precision_manufacturing_outlined),
              title: const Text('Manufacturing'),
              children: [
                ListTile(
                  leading: const Icon(Icons.account_tree_outlined),
                  title: const Text('Bill of Materials'),
                  onTap: () {
                    Get.back();
                    Get.toNamed(AppRoutes.BOM);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.assignment_outlined),
                  title: const Text('Work Order'),
                  onTap: () {
                    Get.back();
                    Get.toNamed(AppRoutes.WORK_ORDER);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.assignment_ind_outlined),
                  title: const Text('Job Card'),
                  onTap: () {
                    Get.back();
                    Get.toNamed(AppRoutes.JOB_CARD);
                  },
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () {
              Get.back();
              authController.logoutUser();
            },
          ),
        ],
      ),
    );
  }
}