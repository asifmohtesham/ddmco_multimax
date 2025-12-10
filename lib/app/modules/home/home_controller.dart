import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/home/widgets/scan_bottom_sheets.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';

enum ActiveScreen { home, purchaseReceipt, stockEntry, deliveryNote, packingSlip, posUpload, todo, item }

class HomeController extends GetxController {
  final AuthenticationController _authController = Get.find<AuthenticationController>();
  final ItemProvider _itemProvider = Get.find<ItemProvider>();
  final WorkOrderProvider _woProvider = Get.find<WorkOrderProvider>();
  final JobCardProvider _jcProvider = Get.find<JobCardProvider>();
  final UserProvider _userProvider = Get.find<UserProvider>();

  var selectedDrawerIndex = 0.obs;
  var activeScreen = ActiveScreen.home.obs;

  // --- User Filter & KPI State ---
  var isLoadingStats = true.obs;
  var isLoadingUsers = true.obs;

  var userList = <User>[].obs;
  Rx<User?> selectedFilterUser = Rx<User?>(null);

  var activeWorkOrdersCount = 0.obs;
  final int targetWorkOrders = 12;

  var activeJobCardsCount = 0.obs;
  final int targetJobCards = 40;

  // Barcode
  final TextEditingController barcodeController = TextEditingController();
  var isScanning = false.obs;

  List<BottomNavigationBarItem> get homeBottomBarItems => [
    const BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
    const BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Notifications'),
  ];

  List<BottomNavigationBarItem> get currentBottomBarItems => homeBottomBarItems;

  @override
  void onInit() {
    super.onInit();
    _updateActiveScreenForRoute(Get.currentRoute);
    _initDashboard();
  }

  @override
  void onClose() {
    barcodeController.dispose();
    super.onClose();
  }

  Future<void> _initDashboard() async {
    await fetchUsers();

    // Set default filter to current user if available in list, else first in list
    if (selectedFilterUser.value == null) {
      final myEmail = _authController.currentUser.value?.email;
      if (myEmail != null) {
        selectedFilterUser.value = userList.firstWhereOrNull((u) => u.email == myEmail);
      }
      if (selectedFilterUser.value == null && userList.isNotEmpty) {
        selectedFilterUser.value = userList.first;
      }
    }
    fetchDashboardData();
  }

  Future<void> fetchUsers() async {
    isLoadingUsers.value = true;
    try {
      final currentUser = _authController.currentUser.value;
      final empId = currentUser?.employeeId;

      if (empId != null) {
        // --- HIERARCHY BASED FILTER ---
        // Fetch users who report to this employee
        final response = await _userProvider.getDirectReports(empId);
        if (response.statusCode == 200 && response.data['data'] != null) {
          final data = response.data['data'] as List;

          // Convert Employee list to User list
          // We map 'user_id' (email) to id/email and 'employee_name' to name
          final reports = data.map((e) => User(
            id: e['user_id'] ?? '',
            name: e['employee_name'] ?? 'Unknown',
            email: e['user_id'] ?? '',
            roles: [], // Not needed for filter
            employeeId: e['name'],
          )).toList();

          // Add Self to the list
          if (currentUser != null && !reports.any((u) => u.email == currentUser.email)) {
            reports.insert(0, currentUser);
          }

          userList.assignAll(reports);
        }
      } else {
        // --- FALLBACK (No Employee Link or Top Level) ---
        // Fetch all active users
        final response = await _userProvider.getUsers();
        if (response.statusCode == 200 && response.data['data'] != null) {
          final data = response.data['data'] as List;
          userList.assignAll(data.map((e) => User.fromJson(e)).toList());
        }
      }
    } catch (e) {
      print('Error fetching users: $e');
    } finally {
      isLoadingUsers.value = false;
    }
  }

  void onUserFilterChanged(User user) {
    selectedFilterUser.value = user;
    Get.back(); // Close modal
    fetchDashboardData();
  }

  Future<void> fetchDashboardData() async {
    isLoadingStats.value = true;
    try {
      // Apply Filter: If a user is selected, filter Work Orders/Job Cards by that user (Owner)
      // Note: This depends on API support. Assuming standard 'owner' filter works.
      Map<String, dynamic> woFilters = {'status': 'In Process'};
      Map<String, dynamic> jcFilters = {'status': 'Open'};

      final filterEmail = selectedFilterUser.value?.email;
      if (filterEmail != null) {
        woFilters['owner'] = filterEmail;
        jcFilters['owner'] = filterEmail;
      }

      final results = await Future.wait([
        _woProvider.getWorkOrders(limit: 0, filters: woFilters), // limit 0 for counts if possible, else high limit
        _jcProvider.getJobCards(limit: 0, filters: jcFilters),
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
    if (response is Response && response.statusCode == 200 && response.data != null && response.data['data'] != null) {
      return (response.data['data'] as List).length;
    }
    return 0;
  }

  // --- Scan Logic ---
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
          Get.bottomSheet(ItemDetailSheet(item: item), isScrollControlled: true);
        } else {
          GlobalSnackbar.error(title: 'Not Found', message: 'Item with code $itemCode not found.');
        }
      } else {
        final itemCode = code;
        final response = await _itemProvider.getStockLevels(itemCode);
        if (response.statusCode == 200 && response.data['message']?['result'] != null) {
          final List<dynamic> data = response.data['message']['result'];
          final stockList = data.whereType<Map<String, dynamic>>().map((json) => WarehouseStock.fromJson(json)).toList();
          Get.bottomSheet(RackBalanceSheet(itemCode: itemCode, stockData: stockList), isScrollControlled: true);
        } else {
          GlobalSnackbar.error(message: 'Could not fetch stock report for $itemCode');
        }
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan processing failed: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  // --- Navigation ---
  void onBottomBarItemTapped(int index) { if (index == 0) fetchDashboardData(); }

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

  void changeDrawerPage(int index, String route) {
    selectedDrawerIndex.value = index;
    Get.back();
    if (Get.currentRoute != route) Get.toNamed(route);
    _updateActiveScreenForRoute(route);
  }

  void goToHome() => changeDrawerPage(0, AppRoutes.HOME);
  void goToStockEntry() => changeDrawerPage(1, AppRoutes.STOCK_ENTRY);
  void goToDeliveryNote() => changeDrawerPage(2, AppRoutes.DELIVERY_NOTE);
  void goToPackingSlip() => changeDrawerPage(3, AppRoutes.PACKING_SLIP);
  void goToPurchaseReceipt() => changeDrawerPage(4, AppRoutes.PURCHASE_RECEIPT);
  void goToPosUpload() => changeDrawerPage(5, AppRoutes.POS_UPLOAD);
  void goToToDo() => changeDrawerPage(6, AppRoutes.TODO);
  void goToItem() => changeDrawerPage(7, AppRoutes.ITEM);
  void goToWorkOrder() => changeDrawerPage(8, AppRoutes.WORK_ORDER);
  void goToJobCard() => changeDrawerPage(9, AppRoutes.JOB_CARD);
}