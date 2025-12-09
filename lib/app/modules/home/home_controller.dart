import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/modules/home/widgets/scan_bottom_sheets.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart'; // Added
import 'package:multimax/app/data/providers/job_card_provider.dart'; // Added

enum ActiveScreen { home, purchaseReceipt, stockEntry, deliveryNote, packingSlip, posUpload, todo, item }

class HomeController extends GetxController {
  final ItemProvider _itemProvider = Get.find<ItemProvider>();
  final WorkOrderProvider _woProvider = Get.find<WorkOrderProvider>(); // Added
  final JobCardProvider _jcProvider = Get.find<JobCardProvider>(); // Added

  var selectedDrawerIndex = 0.obs;
  var activeScreen = ActiveScreen.home.obs;

  var isLoadingStats = true.obs;

  // --- New KPI Observables ---
  var activeWorkOrdersCount = 0.obs;
  var activeJobCardsCount = 0.obs;

  // --- Static User Targets (Daily/Weekly Goals) ---
  final int targetWorkOrders = 12;
  final int targetJobCards = 40;

  // Controller for Barcode Widget
  final TextEditingController barcodeController = TextEditingController();
  var isScanning = false.obs;

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

  @override
  void onClose() {
    barcodeController.dispose();
    super.onClose();
  }

  Future<void> fetchDashboardData() async {
    isLoadingStats.value = true;
    try {
      // Fetch 'In Process' Work Orders and 'Open' Job Cards
      final results = await Future.wait([
        _woProvider.getWorkOrders(limit: 500, filters: {'status': 'In Process'}),
        _jcProvider.getJobCards(limit: 500, filters: {'status': 'Open'}),
      ]);

      activeWorkOrdersCount.value = _getCountFromResponse(results[0]);
      activeJobCardsCount.value = _getCountFromResponse(results[1]);
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
    if (index == 0) fetchDashboardData();
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

  // Scan Logic
  Future<void> onScan(String code) async {
    if (code.isEmpty) return;

    isScanning.value = true;
    bool isEan = RegExp(r'^\d{8,}$').hasMatch(code);

    try {
      if (isEan) {
        final itemCode = code.length > 7 ? code.substring(0, 7) : code;
        final response = await _itemProvider.getItems(limit: 1, filters: {'item_code': itemCode});

        if (response.statusCode == 200 && response.data['data'] != null && (response.data['data'] as List).isNotEmpty) {
          final item = Item.fromJson(response.data['data'][0]);
          Get.bottomSheet(
            ItemDetailSheet(item: item),
            isScrollControlled: true,
          );
        } else {
          Get.snackbar('Not Found', 'Item with code $itemCode not found.');
        }

      } else {
        final itemCode = code;
        final response = await _itemProvider.getStockLevels(itemCode);

        if (response.statusCode == 200 && response.data['message']?['result'] != null) {
          final List<dynamic> data = response.data['message']['result'];
          final stockList = data.whereType<Map<String, dynamic>>().map((json) => WarehouseStock.fromJson(json)).toList();

          Get.bottomSheet(
            RackBalanceSheet(itemCode: itemCode, stockData: stockList),
            isScrollControlled: true,
          );
        } else {
          Get.snackbar('Error', 'Could not fetch stock report for $itemCode');
        }
      }
    } catch (e) {
      Get.snackbar('Error', 'Scan processing failed: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
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
  void goToWorkOrder() => changeDrawerPage(8, AppRoutes.WORK_ORDER); // Ensure index matches Drawer
  void goToJobCard() => changeDrawerPage(9, AppRoutes.JOB_CARD); // Ensure index matches Drawer
}