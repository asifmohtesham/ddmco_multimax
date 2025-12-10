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
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/home/widgets/performance_timeline_card.dart';

enum ActiveScreen { home, purchaseReceipt, stockEntry, deliveryNote, packingSlip, posUpload, todo, item }

class HomeController extends GetxController {
  final AuthenticationController _authController = Get.find<AuthenticationController>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final ItemProvider _itemProvider = Get.find<ItemProvider>();
  final WorkOrderProvider _woProvider = Get.find<WorkOrderProvider>();
  final JobCardProvider _jcProvider = Get.find<JobCardProvider>();
  final UserProvider _userProvider = Get.find<UserProvider>();

  var selectedDrawerIndex = 0.obs;
  var activeScreen = ActiveScreen.home.obs;

  // --- User Filter & KPI State ---
  var isLoadingStats = true.obs;
  var isLoadingUsers = true.obs;

  // Timeline State
  var isWeeklyView = false.obs;
  var isLoadingTimeline = true.obs;
  var timelineData = <TimelinePoint>[].obs;

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
    fetchPerformanceData(); // Trigger Timeline Fetch
  }

  Future<void> fetchUsers() async {
    isLoadingUsers.value = true;
    try {
      final currentUser = _authController.currentUser.value;
      final empId = currentUser?.employeeId;

      if (empId != null) {
        final response = await _userProvider.getDirectReports(empId);
        if (response.statusCode == 200 && response.data['data'] != null) {
          final data = response.data['data'] as List;
          final reports = data.map((e) => User(
            id: e['user_id'] ?? '',
            name: e['employee_name'] ?? 'Unknown',
            email: e['user_id'] ?? '',
            roles: [],
            employeeId: e['name'],
          )).toList();

          if (currentUser != null && !reports.any((u) => u.email == currentUser.email)) {
            reports.insert(0, currentUser);
          }
          userList.assignAll(reports);
        }
      } else {
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
    fetchPerformanceData(); // Refresh timeline for selected user
  }

  Future<void> fetchDashboardData() async {
    isLoadingStats.value = true;
    try {
      Map<String, dynamic> woFilters = {'status': 'In Process'};
      Map<String, dynamic> jcFilters = {'status': 'Open'};

      final filterEmail = selectedFilterUser.value?.email;
      if (filterEmail != null) {
        woFilters['owner'] = filterEmail;
        jcFilters['owner'] = filterEmail;
      }

      final results = await Future.wait([
        _woProvider.getWorkOrders(limit: 0, filters: woFilters),
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

  // --- Performance Data Logic ---

  void toggleTimelineView(bool weekly) {
    if (isWeeklyView.value == weekly) return;
    isWeeklyView.value = weekly;
    fetchPerformanceData();
  }

  Future<void> fetchPerformanceData() async {
    isLoadingTimeline.value = true;
    try {
      final email = selectedFilterUser.value?.email ?? _authController.currentUser.value?.email;
      if (email == null) return;

      final now = DateTime.now();
      // Daily: Last 7 days. Weekly: Last 28 days.
      final daysBack = isWeeklyView.value ? 28 : 7;
      final startDate = now.subtract(Duration(days: daysBack));
      final dateStr = DateFormat('yyyy-MM-dd').format(startDate);

      // Include Draft (0) and Submitted (1) docs.
      final filters = {
        'owner': email,
        'docstatus': ['<', 2], // 0 and 1, exclude cancelled
        'creation': ['>=', dateStr]
      };

      // Parallel Fetch
      final results = await Future.wait([
        _apiProvider.getDocumentList('Delivery Note', filters: filters, fields: ['creation', 'total_qty', 'customer'], limit: 100),
        _apiProvider.getDocumentList('Stock Entry', filters: filters, fields: ['creation', 'custom_total_qty'], limit: 100),
        _apiProvider.getDocumentList('Purchase Receipt', filters: filters, fields: ['creation', 'total_qty'], limit: 100),
      ]);

      final dnList = _extractList(results[0]);
      final seList = _extractList(results[1]);
      final prList = _extractList(results[2]);

      // Process Data into Buckets
      Map<String, TimelinePoint> buckets = {};

      // Initialize Buckets (ensure X-axis is continuous)
      for (int i = 0; i < (isWeeklyView.value ? 4 : 7); i++) {
        DateTime date;
        String key;
        String label;

        if (isWeeklyView.value) {
          // Weekly buckets: Last 4 weeks
          date = now.subtract(Duration(days: (3 - i) * 7));
          // Key: Year-Month-WeekOfMonth
          key = '${date.year}-${date.month}-W${_getWeekOfMonth(date)}';
          // Label: "MMM W#" e.g. "Oct W4"
          label = '${DateFormat('MMM').format(date)} W${_getWeekOfMonth(date)}';
        } else {
          // Daily buckets: Last 7 days
          date = now.subtract(Duration(days: (6 - i)));
          key = DateFormat('yyyy-MM-dd').format(date);
          label = DateFormat('E').format(date); // Mon, Tue
        }

        buckets[key] = TimelinePoint(label: label, date: date);
      }

      // Helper to fill buckets
      void fillBucket(List<dynamic> list, String type) {
        for (var item in list) {
          final date = DateTime.parse(item['creation']);
          String key;

          if (isWeeklyView.value) {
            // Match initialization logic
            key = '${date.year}-${date.month}-W${_getWeekOfMonth(date)}';
          } else {
            key = DateFormat('yyyy-MM-dd').format(date);
          }

          if (buckets.containsKey(key)) {
            final existing = buckets[key]!;
            double qty = 0.0;
            if (type == 'DN') {
              qty = _safeParseDouble(item['total_qty']);
            } else if (type == 'SE') {
              qty = _safeParseDouble(item['custom_total_qty']);
              if (qty == 0) qty = _safeParseDouble(item['total_qty']);
            } else if (type == 'PR') {
              qty = _safeParseDouble(item['total_qty']);
            }

            int custCount = (type == 'DN' && item['customer'] != null) ? 1 : 0;

            buckets[key] = TimelinePoint(
              label: existing.label,
              date: existing.date,
              deliveryQty: existing.deliveryQty + (type == 'DN' ? qty : 0),
              stockQty: existing.stockQty + (type == 'SE' ? qty : 0),
              receiptQty: existing.receiptQty + (type == 'PR' ? qty : 0),
              customerCount: existing.customerCount + custCount,
            );
          }
        }
      }

      fillBucket(dnList, 'DN');
      fillBucket(seList, 'SE');
      fillBucket(prList, 'PR');

      timelineData.assignAll(buckets.values.toList());

    } catch (e) {
      print('Error fetching timeline: $e');
    } finally {
      isLoadingTimeline.value = false;
    }
  }

  // --- Helpers ---

  // Calculates Week Number within the Month (1-5)
  int _getWeekOfMonth(DateTime date) {
    return ((date.day - 1) / 7).floor() + 1;
  }

  double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  List<dynamic> _extractList(Response response) {
    if (response.statusCode == 200 && response.data['data'] != null) {
      return response.data['data'] as List;
    }
    return [];
  }

  int _getCountFromResponse(dynamic response) {
    if (response is Response && response.statusCode == 200 && response.data != null && response.data['data'] != null) {
      return (response.data['data'] as List).length;
    }
    return 0;
  }

  // ... (Scan Logic and Navigation remain same) ...
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