import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart'; // Update path

// Enum to manage current active screen for bottom bar context
enum ActiveScreen { home, stockEntry, deliveryNote, packingSlip }

class HomeController extends GetxController {
  var selectedDrawerIndex = 0.obs; // To highlight active item in NavDrawer
  var activeScreen = ActiveScreen.home.obs; // To control BottomBar context

  // Example: Bottom bar options for Home screen
  List<BottomNavigationBarItem> get homeBottomBarItems => [
    const BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Feed'),
    const BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Discover'),
  ];

  // Example: Bottom bar options for Stock Entry screen
  List<BottomNavigationBarItem> get stockEntryBottomBarItems => [
    const BottomNavigationBarItem(icon: Icon(Icons.add_shopping_cart), label: 'New Item'),
    const BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'View Stock'),
    const BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
  ];

  // You'd have similar lists for Delivery Note and Packing Slip

  List<BottomNavigationBarItem> get currentBottomBarItems {
    switch (activeScreen.value) {
      case ActiveScreen.home:
        return homeBottomBarItems;
      case ActiveScreen.stockEntry:
        return stockEntryBottomBarItems;
    // ... cases for ActiveScreen.deliveryNote, ActiveScreen.packingSlip
      default:
        return homeBottomBarItems; // Default
    }
  }

  void onBottomBarItemTapped(int index) {
    // Handle bottom bar item taps based on the activeScreen.value and index
    print('Bottom bar item $index tapped on ${activeScreen.value}');
    // Example: if activeScreen is home and index 0 is tapped, do something
  }


  void changeDrawerPage(int index, String route) {
    selectedDrawerIndex.value = index;
    Get.back(); // Close the drawer
    Get.toNamed(route); // Navigate to the selected page

    // Update active screen for bottom bar context
    switch (route) {
      case AppRoutes.HOME:
        activeScreen.value = ActiveScreen.home;
        break;
      case AppRoutes.STOCK_ENTRY:
        activeScreen.value = ActiveScreen.stockEntry;
        break;
      case AppRoutes.DELIVERY_NOTE:
        activeScreen.value = ActiveScreen.deliveryNote;
        break;
      case AppRoutes.PACKING_SLIP:
        activeScreen.value = ActiveScreen.packingSlip;
        break;
    }
  }

  // --- Methods for NavDrawer items ---
  void goToHome() => changeDrawerPage(0, AppRoutes.HOME);
  void goToStockEntry() => changeDrawerPage(1, AppRoutes.STOCK_ENTRY);
  void goToDeliveryNote() => changeDrawerPage(2, AppRoutes.DELIVERY_NOTE);
  void goToPackingSlip() => changeDrawerPage(3, AppRoutes.PACKING_SLIP);

  @override
  void onInit() {
    super.onInit();
    // Potentially update activeScreen based on the current route when controller initializes
    // This is useful if the user lands directly on a sub-page or after a hot reload.
    final currentRoute = Get.currentRoute;
    switch (currentRoute) {
      case AppRoutes.HOME:
        activeScreen.value = ActiveScreen.home;
        selectedDrawerIndex.value = 0;
        break;
      case AppRoutes.STOCK_ENTRY:
        activeScreen.value = ActiveScreen.stockEntry;
        selectedDrawerIndex.value = 1;
        break;
      case AppRoutes.DELIVERY_NOTE:
        activeScreen.value = ActiveScreen.deliveryNote;
        selectedDrawerIndex.value = 2;
        break;
      case AppRoutes.PACKING_SLIP:
        activeScreen.value = ActiveScreen.packingSlip;
        selectedDrawerIndex.value = 3;
        break;
    }
  }
}
