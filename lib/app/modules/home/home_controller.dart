import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart';
import 'package:ddmco_multimax/app/data/providers/delivery_note_provider.dart';
import 'package:ddmco_multimax/app/data/providers/packing_slip_provider.dart';
import 'package:ddmco_multimax/app/data/providers/pos_upload_provider.dart';
import 'package:ddmco_multimax/app/data/providers/todo_provider.dart';

enum ActiveScreen { home, purchaseReceipt, stockEntry, deliveryNote, packingSlip, posUpload, todo, item }

class HomeController extends GetxController {
  final DeliveryNoteProvider _dnProvider = Get.find<DeliveryNoteProvider>();
  final PackingSlipProvider _psProvider = Get.find<PackingSlipProvider>();
  final PosUploadProvider _posProvider = Get.find<PosUploadProvider>();
  final ToDoProvider _todoProvider = Get.find<ToDoProvider>();

  var selectedDrawerIndex = 0.obs;
  var activeScreen = ActiveScreen.home.obs;

  var isLoadingStats = true.obs;
  var draftDeliveryNotesCount = 0.obs;
  var draftPackingSlipsCount = 0.obs;
  var pendingPosUploadsCount = 0.obs;
  var openTodosCount = 0.obs;

  List<BottomNavigationBarItem> get homeBottomBarItems => [
    const BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
    const BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Notifications'),
  ];

  List<BottomNavigationBarItem> get currentBottomBarItems {
    return homeBottomBarItems;
  }

  @override
  void onInit() {
    super.onInit();
    _updateActiveScreenForRoute(Get.currentRoute);
    fetchDashboardData();
  }

  Future<void> fetchDashboardData() async {
    isLoadingStats.value = true;
    try {
      // Use docstatus: 0 for drafts to get accurate counts from API
      // Increased limit to 500 to ensure we catch most open items
      final results = await Future.wait([
        _dnProvider.getDeliveryNotes(limit: 500, filters: {'docstatus': 0}),
        _psProvider.getPackingSlips(limit: 500, filters: {'docstatus': 0}),
        _posProvider.getPosUploads(limit: 500, filters: {'status': 'Pending'}),
        _todoProvider.getTodos(limit: 500, filters: {'status': 'Open'}),
      ]);

      draftDeliveryNotesCount.value = _getCountFromResponse(results[0]);
      draftPackingSlipsCount.value = _getCountFromResponse(results[1]);
      pendingPosUploadsCount.value = _getCountFromResponse(results[2]);
      openTodosCount.value = _getCountFromResponse(results[3]);
    } catch (e) {
      print('Error fetching dashboard stats: $e');
    } finally {
      isLoadingStats.value = false;
    }
  }

  int _getCountFromResponse(dynamic response) {
    if (response.statusCode == 200 && response.data['data'] != null) {
      return (response.data['data'] as List).length;
    }
    return 0;
  }

  void onBottomBarItemTapped(int index) {
    if (index == 0) fetchDashboardData(); // Refresh on tap
  }

  void changeDrawerPage(int index, String route) {
    selectedDrawerIndex.value = index;
    Get.back();
    if (Get.currentRoute != route) {
      Get.toNamed(route);
    }
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
      case AppRoutes.TODO:
        activeScreen.value = ActiveScreen.todo;
        selectedDrawerIndex.value = 6;
        break;
      case AppRoutes.ITEM:
        activeScreen.value = ActiveScreen.item;
        selectedDrawerIndex.value = 7;
        break;
    }
  }

  // Navigation Shortcuts
  void goToHome() => changeDrawerPage(0, AppRoutes.HOME);
  void goToPurchaseReceipt() => changeDrawerPage(4, AppRoutes.PURCHASE_RECEIPT);
  void goToStockEntry() => changeDrawerPage(1, AppRoutes.STOCK_ENTRY);
  void goToDeliveryNote() => changeDrawerPage(2, AppRoutes.DELIVERY_NOTE);
  void goToPackingSlip() => changeDrawerPage(3, AppRoutes.PACKING_SLIP);
  void goToPosUpload() => changeDrawerPage(5, AppRoutes.POS_UPLOAD);
  void goToToDo() => changeDrawerPage(6, AppRoutes.TODO);
  void goToItem() => changeDrawerPage(7, AppRoutes.ITEM);
}