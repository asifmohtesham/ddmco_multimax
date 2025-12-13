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
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/item/form/item_form_screen.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/modules/home/widgets/session_defaults_bottom_sheet.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';

enum ActiveScreen { home, purchaseReceipt, stockEntry, deliveryNote, packingSlip, posUpload, todo, item, batch }
class HomeController extends GetxController {
  final AuthenticationController _authController = Get.find<AuthenticationController>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final ItemProvider _itemProvider = Get.find<ItemProvider>();
  final WorkOrderProvider _woProvider = Get.find<WorkOrderProvider>();
  final JobCardProvider _jcProvider = Get.find<JobCardProvider>();
  final UserProvider _userProvider = Get.find<UserProvider>();
  final PosUploadProvider _posUploadProvider = Get.find<PosUploadProvider>();
  final StockEntryProvider _stockEntryProvider = Get.find<StockEntryProvider>();
  final DeliveryNoteProvider _deliveryNoteProvider = Get.find<DeliveryNoteProvider>();
  final ScanService _scanService = Get.find<ScanService>();

  var selectedDrawerIndex = 0.obs;
  var activeScreen = ActiveScreen.home.obs;

  var isLoadingStats = true.obs;
  var isLoadingUsers = true.obs;

  // --- Timeline State ---
  var timelineViewMode = 'Daily'.obs;
  var isLoadingTimeline = true.obs;
  var timelineData = <TimelinePoint>[].obs;

  var selectedDailyDate = DateTime.now().obs;
  var selectedWeeklyRange = DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 28)),
      end: DateTime.now()
  ).obs;

  var userList = <User>[].obs;
  Rx<User?> selectedFilterUser = Rx<User?>(null);

  var activeWorkOrdersCount = 0.obs;
  final int targetWorkOrders = 12;

  var activeJobCardsCount = 0.obs;
  final int targetJobCards = 40;

  final TextEditingController barcodeController = TextEditingController();
  var isScanning = false.obs;
  var isRackScanning = false.obs;

  // Fulfillment
  var isFetchingFulfillmentList = false.obs;
  var fulfillmentPosUploads = <PosUpload>[].obs;
  var fulfillmentSearchQuery = ''.obs;
  List<PosUpload> _allFulfillmentUploads = [];

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

  void openSessionDefaults() {
    Get.bottomSheet(const SessionDefaultsBottomSheet(), isScrollControlled: true);
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
    fetchPerformanceData();
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
          final reports = data.map((e) => User(id: e['user_id'] ?? '', name: e['employee_name'] ?? 'Unknown', email: e['user_id'] ?? '', roles: [], employeeId: e['name'])).toList();
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
    Get.back();
    fetchDashboardData();
    fetchPerformanceData();
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

  // --- Timeline Logic ---
  void toggleTimelineView(String mode) {
    if (timelineViewMode.value == mode) return;
    timelineViewMode.value = mode;
    fetchPerformanceData();
  }

  void onDailyDateChanged(DateTime date) {
    selectedDailyDate.value = date;
    if (timelineViewMode.value != 'Weekly') fetchPerformanceData();
  }

  void onWeeklyRangeChanged(DateTimeRange range) {
    selectedWeeklyRange.value = range;
    if (timelineViewMode.value == 'Weekly') fetchPerformanceData();
  }

  Future<void> fetchPerformanceData() async {
    isLoadingTimeline.value = true;
    try {
      final email = selectedFilterUser.value?.email ?? _authController.currentUser.value?.email;
      if (email == null) return;

      DateTime startDate;
      DateTime endDate;
      Map<String, TimelinePoint> buckets = {};

      if (timelineViewMode.value == 'Weekly') {
        startDate = selectedWeeklyRange.value.start;
        endDate = selectedWeeklyRange.value.end;
        DateTime current = startDate;
        while (current.isBefore(endDate) || current.isAtSameMomentAs(endDate)) {
          final key = '${current.year}-${current.month}-W${_getWeekOfMonth(current)}';
          final label = '${DateFormat('MMM').format(current)} W${_getWeekOfMonth(current)}';
          if (!buckets.containsKey(key)) {
            buckets[key] = TimelinePoint(label: label, date: current);
          }
          current = current.add(const Duration(days: 7));
        }
      } else if (timelineViewMode.value == 'Hourly') {
        startDate = selectedDailyDate.value;
        endDate = startDate.add(const Duration(hours: 23, minutes: 59));
        for (int i = 0; i < 24; i++) {
          final key = i.toString();
          final label = '${i.toString().padLeft(2, '0')}:00';
          buckets[key] = TimelinePoint(label: label, date: startDate);
        }
      } else {
        endDate = selectedDailyDate.value;
        startDate = endDate.subtract(const Duration(days: 6));
        for (int i = 0; i < 7; i++) {
          final date = endDate.subtract(Duration(days: (6 - i)));
          final key = DateFormat('yyyy-MM-dd').format(date);
          final label = DateFormat('E').format(date);
          buckets[key] = TimelinePoint(label: label, date: date);
        }
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(startDate);
      final filters = {'owner': email, 'docstatus': ['<', 2]};

      if (timelineViewMode.value == 'Hourly') {
        filters['creation'] = ['between', [
          DateFormat('yyyy-MM-dd 00:00:00').format(startDate),
          DateFormat('yyyy-MM-dd 23:59:59').format(startDate)
        ]];
      } else {
        filters['creation'] = ['>=', dateStr];
      }

      final results = await Future.wait([
        _apiProvider.getDocumentList('Delivery Note', filters: filters, fields: ['creation', 'total_qty', 'customer'], limit: 100),
        _apiProvider.getDocumentList('Stock Entry', filters: filters, fields: ['creation', 'custom_total_qty'], limit: 100),
        _apiProvider.getDocumentList('Purchase Receipt', filters: filters, fields: ['creation', 'total_qty'], limit: 100),
      ]);

      final dnList = _extractList(results[0]);
      final seList = _extractList(results[1]);
      final prList = _extractList(results[2]);

      void fillBucket(List<dynamic> list, String type) {
        for (var item in list) {
          final date = DateTime.parse(item['creation']);
          if (timelineViewMode.value != 'Hourly' && date.isAfter(endDate.add(const Duration(days: 1)))) continue;

          String key;
          if (timelineViewMode.value == 'Weekly') {
            key = '${date.year}-${date.month}-W${_getWeekOfMonth(date)}';
          } else if (timelineViewMode.value == 'Hourly') {
            key = date.hour.toString();
          } else {
            key = DateFormat('yyyy-MM-dd').format(date);
          }

          if (buckets.containsKey(key)) {
            final existing = buckets[key]!;
            double qty = 0.0;
            if (type == 'DN') qty = _safeParseDouble(item['total_qty']);
            else if (type == 'SE') qty = _safeParseDouble(item['custom_total_qty']);
            else if (type == 'PR') qty = _safeParseDouble(item['total_qty']);

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

  // --- Scan & Item Sheet Logic ---
  Future<void> onScan(String code) async {
    // 1. Prevent Double Trigger / Re-entry
    if (isScanning.value) return;

    if (code.isEmpty) return;

    isScanning.value = true;
    try {
      final result = await _scanService.processScan(code);

      if (result.type == ScanType.rack && result.rackId != null) {
        await _handleRackScan(result.rackId!);
      }
      // FIX: Add check for ScanType.batch
      else if (result.isSuccess && (result.type == ScanType.item || result.type == ScanType.batch) && result.itemData != null) {
        _openItemDetailSheet(result.itemData!.itemCode);
      }
      else if (result.type == ScanType.multiple && result.candidates != null) {
        // Open Disambiguation Sheet
        barcodeController.clear();
        Get.bottomSheet(
          MultiItemSelectionSheet(
            items: result.candidates!,
            onItemSelected: (item) => _openItemDetailSheet(item.itemCode),
          ),
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
        );
      } else {
        GlobalSnackbar.error(title: 'Not Found', message: result.message ?? 'Item not found');
      }
    } catch (e) {
      GlobalSnackbar.error(title: 'Scan Error', message: '$e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  void _openItemDetailSheet(String itemCode) async {
    final itemFormController = Get.put(ItemFormController());
    itemFormController.loadItem(itemCode);
    barcodeController.clear();

    await Get.bottomSheet(
      FractionallySizedBox(
        heightFactor: 0.9,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: const ItemFormScreen(),
        ),
      ),
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.white,
    );
    Get.delete<ItemFormController>();
  }

  Future<void> _handleRackScan(String rackCode) async {
    isRackScanning.value = true;
    barcodeController.clear(); // Clear immediately for UX
    try {
      final parts = rackCode.split('-');
      if (parts.length < 3) throw Exception('Invalid Rack Format');
      final String warehouse = '${parts[1]}-${parts[2]} - ${parts[0]}';

      // Call provider which now uses "Stock Balance - Custom"
      final response = await _itemProvider.getWarehouseStock(warehouse);

      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> data = response.data['message']['result'];

        // Filter results for the specific scanned rack
        final rackItems = data.where((row) {
          final rowRack = row['rack']?.toString() ?? '';
          return rowRack == rackCode;
        }).toList();

        if (rackItems.isEmpty) {
          GlobalSnackbar.info(title: 'Empty Rack', message: 'No items found in rack $rackCode');
        } else {
          // Open the updated RackContentsSheet
          Get.bottomSheet(
            RackContentsSheet(rackId: rackCode, items: rackItems),
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
          );
        }
      } else {
        GlobalSnackbar.error(message: 'Failed to fetch stock for warehouse $warehouse');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Invalid Rack QR or Network Error');
    } finally {
      isRackScanning.value = false;
    }
  }

  // --- Fulfillment Logic ---
  Future<void> fetchFulfillmentPosUploads() async {
    isFetchingFulfillmentList.value = true;
    try {
      final response = await _posUploadProvider.getPosUploads(
          limit: 100, filters: {'status': ['in', ['Pending', 'In Progress']]}, orderBy: 'modified desc'
      );
      if(response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'];
        _allFulfillmentUploads = (data as List).map((e)=>PosUpload.fromJson(e)).toList();
        fulfillmentPosUploads.assignAll(_allFulfillmentUploads);
      }
    } catch(e){
      GlobalSnackbar.error(message: 'Error fetching fulfillment list');
    } finally {
      isFetchingFulfillmentList.value = false;
    }
  }

  void filterFulfillmentList(String query) {
    if(query.isEmpty) fulfillmentPosUploads.assignAll(_allFulfillmentUploads);
    else fulfillmentPosUploads.assignAll(_allFulfillmentUploads.where((d) => d.name.toLowerCase().contains(query.toLowerCase()) || d.customer.toLowerCase().contains(query.toLowerCase())).toList());
  }

  Future<void> handleFulfillmentSelection(PosUpload posUpload) async {
    Get.back();
    GlobalSnackbar.info(message: 'Processing ${posUpload.name}...');
    final name = posUpload.name.toUpperCase();
    if (name.startsWith('KX') || name.startsWith('MX')) {
      try {
        final res = await _stockEntryProvider.getStockEntries(limit: 1, filters: {'custom_reference_no': posUpload.name});
        if(res.statusCode == 200 && res.data['data'] != null && (res.data['data'] as List).isNotEmpty) {
          Get.toNamed(AppRoutes.STOCK_ENTRY_FORM, arguments: {'name': res.data['data'][0]['name'], 'mode': 'edit'});
        } else {
          Get.toNamed(AppRoutes.STOCK_ENTRY_FORM, arguments: {'name': '', 'mode': 'new', 'stockEntryType': 'Material Issue', 'customReferenceNo': posUpload.name});
        }
      } catch(e) { GlobalSnackbar.error(message: 'Error processing Stock Entry'); }
    } else {
      try {
        final res = await _deliveryNoteProvider.getDeliveryNotes(limit: 1, filters: {'po_no': posUpload.name});
        if(res.statusCode == 200 && res.data['data'] != null && (res.data['data'] as List).isNotEmpty) {
          Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM, arguments: {'name': res.data['data'][0]['name'], 'mode': 'edit'});
        } else {
          Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM, arguments: {'name': '', 'mode': 'new', 'posUploadCustomer': posUpload.customer, 'posUploadName': posUpload.name});
        }
      } catch(e) { GlobalSnackbar.error(message: 'Error processing Delivery Note'); }
    }
  }

  // Helpers
  int _getWeekOfMonth(DateTime date) {
    int week = ((date.day - 1) / 7).floor() + 1;
    return week > 4 ? 4 : week;
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

  void onBottomBarItemTapped(int index) { if (index == 0) fetchDashboardData(); }
  void updateActiveScreen(String route) { _updateActiveScreenForRoute(route); }

  void _updateActiveScreenForRoute(String route) {
    switch (route) {
      case AppRoutes.HOME: activeScreen.value = ActiveScreen.home; selectedDrawerIndex.value = 0; break;
      case AppRoutes.STOCK_ENTRY: activeScreen.value = ActiveScreen.stockEntry; selectedDrawerIndex.value = 1; break;
      case AppRoutes.DELIVERY_NOTE: activeScreen.value = ActiveScreen.deliveryNote; selectedDrawerIndex.value = 2; break;
      case AppRoutes.PACKING_SLIP: activeScreen.value = ActiveScreen.packingSlip; selectedDrawerIndex.value = 3; break;
      case AppRoutes.PURCHASE_RECEIPT: activeScreen.value = ActiveScreen.purchaseReceipt; selectedDrawerIndex.value = 4; break;
      case AppRoutes.POS_UPLOAD: activeScreen.value = ActiveScreen.posUpload; selectedDrawerIndex.value = 5; break;
      case AppRoutes.TODO: activeScreen.value = ActiveScreen.todo; selectedDrawerIndex.value = 6; break;
      case AppRoutes.ITEM: activeScreen.value = ActiveScreen.item; selectedDrawerIndex.value = 7; break;
      case AppRoutes.WORK_ORDER: activeScreen.value = ActiveScreen.home; selectedDrawerIndex.value = 8; break; // Assuming Work Order uses index 8
      case AppRoutes.JOB_CARD: activeScreen.value = ActiveScreen.home; selectedDrawerIndex.value = 9; break;  // Assuming Job Card uses index 9
      case AppRoutes.BATCH: activeScreen.value = ActiveScreen.batch; selectedDrawerIndex.value = 10; break;
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
  void goToBatch() => changeDrawerPage(10, AppRoutes.BATCH);
}