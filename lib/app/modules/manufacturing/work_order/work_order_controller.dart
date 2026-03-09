import 'package:get/get.dart';
import 'package:multimax/app/data/providers/erpnext_provider.dart';
import 'package:multimax/app/modules/manufacturing/models/work_order_model.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class WorkOrderController extends GetxController {
  final ErpnextProvider _provider = Get.find<ErpnextProvider>();

  final RxList<WorkOrderModel> workOrders = <WorkOrderModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxString? statusFilter = RxString('');

  @override
  void onInit() {
    super.onInit();
    fetchWorkOrders();
  }

  Future<void> fetchWorkOrders({bool silent = false}) async {
    try {
      if (!silent) isLoading.value = true;

      final filters = <String, dynamic>{};
      if (statusFilter?.value.isNotEmpty ?? false) {
        filters['status'] = statusFilter!.value;
      }

      final response = await _provider.getListWithFilters(
        doctype: 'Work Order',
        fields: [
          'name', 'production_item', 'item_name', 'bom_no', 'qty',
          'produced_qty', 'material_transferred_for_manufacturing',
          'status', 'company', 'wip_warehouse', 'fg_warehouse', 'source_warehouse',
          'planned_start_date', 'planned_end_date', 'actual_start_date',
          'actual_end_date', 'modified'
        ],
        filters: filters,
        orderBy: 'modified desc',
        limit: 50,
      );

      if (response != null && response['data'] != null) {
        final List<dynamic> data = response['data'];
        
        // Fetch full details including operations and required items
        final List<WorkOrderModel> fullWorkOrders = [];
        for (var woData in data) {
          final fullWo = await _fetchFullWorkOrder(woData['name']);
          if (fullWo != null) {
            fullWorkOrders.add(fullWo);
          }
        }
        
        workOrders.value = fullWorkOrders;
      }
    } catch (e) {
      if (!silent) {
        GlobalSnackbar.error(message: 'Failed to load work orders: $e');
      }
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  Future<WorkOrderModel?> _fetchFullWorkOrder(String name) async {
    try {
      final response = await _provider.getDoc(
        doctype: 'Work Order',
        name: name,
      );

      if (response != null && response['data'] != null) {
        return WorkOrderModel.fromJson(response['data']);
      }
    } catch (e) {
      // Silent failure for individual work orders
    }
    return null;
  }

  Future<void> startWorkOrder(String name) async {
    try {
      isLoading.value = true;

      await _provider.updateDoc(
        doctype: 'Work Order',
        name: name,
        data: {
          'status': 'In Process',
          'actual_start_date': DateTime.now().toIso8601String(),
        },
      );

      // Submit the document if in draft
      final wo = workOrders.firstWhereOrNull((w) => w.name == name);
      if (wo?.status == 'Draft') {
        await _provider.runDocMethod(
          doctype: 'Work Order',
          name: name,
          method: 'submit',
        );
      }

      GlobalSnackbar.success(message: 'Production started');
      await fetchWorkOrders();
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to start work order: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> stopWorkOrder(String name) async {
    try {
      isLoading.value = true;

      await _provider.updateDoc(
        doctype: 'Work Order',
        name: name,
        data: {
          'status': 'Stopped',
        },
      );

      GlobalSnackbar.success(message: 'Production stopped');
      await fetchWorkOrders();
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to stop work order: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> completeWorkOrder(String name) async {
    try {
      isLoading.value = true;

      await _provider.runDocMethod(
        doctype: 'Work Order',
        name: name,
        method: 'complete',
      );

      GlobalSnackbar.success(message: 'Work order completed');
      await fetchWorkOrders();
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to complete work order: $e');
    } finally {
      isLoading.value = false;
    }
  }
}