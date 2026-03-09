import 'dart:async';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/manufacturing/work_order_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class WorkOrderController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // Observables
  final RxBool isLoading = false.obs;
  final RxBool isLoadingDetail = false.obs;
  final RxList<WorkOrderModel> workOrderList = <WorkOrderModel>[].obs;
  final Rx<WorkOrderModel?> selectedWorkOrder = Rx<WorkOrderModel?>(null);
  final RxString searchQuery = ''.obs;
  final RxString filterStatus = 'All'.obs; // All, Not Started, In Process, Completed, Stopped

  Timer? _refreshTimer;

  @override
  void onInit() {
    super.onInit();
    fetchWorkOrderList();
    _startAutoRefresh();
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    super.onClose();
  }

  /// Auto-refresh every 30 seconds for active work orders
  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (filterStatus.value == 'In Process' || filterStatus.value == 'All') {
        fetchWorkOrderList(silent: true);
      }
    });
  }

  /// Fetch Work Order list
  Future<void> fetchWorkOrderList({bool silent = false}) async {
    try {
      if (!silent) isLoading.value = true;

      final filters = <String, dynamic>{
        'docstatus': 1, // Submitted only
      };

      if (filterStatus.value != 'All') {
        filters['status'] = filterStatus.value;
      }

      final response = await _apiProvider.get(
        '/api/resource/Work Order',
        queryParameters: {
          'fields': '[
            "name", "status", "production_item", "item_name", "image", 
            "bom_no", "qty", "produced_qty", "material_transferred_for_manufacturing",
            "company", "fg_warehouse", "wip_warehouse", "source_warehouse",
            "planned_start_date", "planned_end_date", "actual_start_date", "actual_end_date",
            "modified", "creation"
          ]',
          'filters': filters,
          'order_by': 'planned_start_date desc',
          'limit_page_length': 100,
        },
      );

      if (response.statusCode == 200) {
        final data = response.body['data'] as List;
        workOrderList.value = data.map((json) => WorkOrderModel.fromJson(json)).toList();
      }
    } catch (e) {
      if (!silent) {
        GlobalSnackbar.error(message: 'Failed to load Work Orders: $e');
      }
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  /// Fetch Work Order detail
  Future<void> fetchWorkOrderDetail(String workOrderName) async {
    try {
      isLoadingDetail.value = true;

      final response = await _apiProvider.get('/api/resource/Work Order/$workOrderName');

      if (response.statusCode == 200) {
        selectedWorkOrder.value = WorkOrderModel.fromJson(response.body['data']);
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load Work Order details: $e');
    } finally {
      isLoadingDetail.value = false;
    }
  }

  /// Start Work Order
  Future<void> startWorkOrder(String workOrderName) async {
    try {
      final response = await _apiProvider.post(
        '/api/method/erpnext.manufacturing.doctype.work_order.work_order.start_work_order',
        data: {'work_order': workOrderName},
      );

      if (response.statusCode == 200) {
        GlobalSnackbar.success(message: 'Work Order started successfully');
        fetchWorkOrderDetail(workOrderName);
        fetchWorkOrderList();
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to start Work Order: $e');
    }
  }

  /// Complete Work Order
  Future<void> completeWorkOrder(String workOrderName) async {
    try {
      final response = await _apiProvider.post(
        '/api/method/erpnext.manufacturing.doctype.work_order.work_order.stop_work_order',
        data: {'work_order': workOrderName, 'status': 'Completed'},
      );

      if (response.statusCode == 200) {
        GlobalSnackbar.success(message: 'Work Order completed successfully');
        fetchWorkOrderDetail(workOrderName);
        fetchWorkOrderList();
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to complete Work Order: $e');
    }
  }

  /// Set filter status
  void setFilterStatus(String status) {
    filterStatus.value = status;
    fetchWorkOrderList();
  }

  /// Search Work Order
  void searchWorkOrder(String query) {
    searchQuery.value = query;
    fetchWorkOrderList();
  }

  /// Navigate to Work Order detail
  void goToWorkOrderDetail(String workOrderName) {
    Get.toNamed('/manufacturing/work-order/$workOrderName');
  }

  /// Navigate to create Job Card
  void goToCreateJobCard(String workOrderName) {
    Get.toNamed('/manufacturing/job-card/new', arguments: {'work_order': workOrderName});
  }
}
