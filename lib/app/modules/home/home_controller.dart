import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart'; // Update path

// Enum to manage current active screen for bottom bar context
enum ActiveScreen { home, purchaseReceipt, stockEntry, deliveryNote, packingSlip, posUpload }

class HomeController extends GetxController {
  var selectedDrawerIndex = 0.obs; // To highlight active item in NavDrawer
  var activeScreen = ActiveScreen.home.obs; // Now primarily for BottomBar/AppBar context

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
    Get.back(); // Close drawer

    // If the target route is the current route, don't navigate again (optional)
    if (Get.currentRoute != route) {
      Get.toNamed(route);
    }

    // Update activeScreen based on the new route for AppBottomBar/AppBar context
    _updateActiveScreenForRoute(route);
  }

  void updateActiveScreen(String route) {
    _updateActiveScreenForRoute(route);
  }

  void _updateActiveScreenForRoute(String route) {
    switch (route) {
      case AppRoutes.HOME:
        activeScreen.value = ActiveScreen.home;
        selectedDrawerIndex.value = 0;
        break;
      case AppRoutes.PURCHASE_RECEIPT:
        activeScreen.value = ActiveScreen.purchaseReceipt;
        selectedDrawerIndex.value = 4;
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
      case AppRoutes.POS_UPLOAD:
        activeScreen.value = ActiveScreen.posUpload;
        selectedDrawerIndex.value = 5;
        break;
    // ... other cases
    }
  }

  // --- Methods for NavDrawer items ---
  void goToHome() => changeDrawerPage(0, AppRoutes.HOME);
  void goToPurchaseReceipt() => changeDrawerPage(4, AppRoutes.PURCHASE_RECEIPT);
  void goToStockEntry() => changeDrawerPage(1, AppRoutes.STOCK_ENTRY);
  void goToDeliveryNote() => changeDrawerPage(2, AppRoutes.DELIVERY_NOTE);
  void goToPackingSlip() => changeDrawerPage(3, AppRoutes.PACKING_SLIP);
  void goToPosUpload() => changeDrawerPage(5, AppRoutes.POS_UPLOAD);

  @override
  void onInit() {
    super.onInit();

    // Update activeScreen based on the initial route
    _updateActiveScreenForRoute(Get.currentRoute);
  }
}
