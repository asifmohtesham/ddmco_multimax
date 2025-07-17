import 'package:ddmco_multimax/app/modules/home/home_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/home/home_controller.dart'; // Or a shared Nav/UI controller

class AppBottomBar extends StatelessWidget {
  const AppBottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    final HomeController homeController = Get.find<HomeController>();
    // If you have many screens with different bottom bars, you might need a more
    // sophisticated way to get the current items, perhaps from the active screen's controller.
    // For this example, HomeController manages the logic.

    return Obx(() => BottomNavigationBar(
      items: homeController.currentBottomBarItems,
      currentIndex: 0, // You'll need to manage the current index of the bottom bar itself
      onTap: homeController.onBottomBarItemTapped,
      type: BottomNavigationBarType.fixed, // Or .shifting
      // Add other styling as needed
    ));
  }
}