import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/home/home_controller.dart';

class AppBottomBar extends StatelessWidget {
  const AppBottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    final HomeController homeController = Get.find<HomeController>();
    
    // Removed Obx because currentBottomBarItems is not currently reactive.
    // If navigation logic becomes dynamic based on observables, wrap this back in Obx.
    return BottomNavigationBar(
      items: homeController.currentBottomBarItems,
      currentIndex: 0, 
      onTap: homeController.onBottomBarItemTapped,
      type: BottomNavigationBarType.fixed,
    );
  }
}
