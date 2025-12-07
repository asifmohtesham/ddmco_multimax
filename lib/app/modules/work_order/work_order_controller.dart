import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/work_order_model.dart';
import 'package:ddmco_multimax/app/data/providers/work_order_provider.dart';

class WorkOrderController extends GetxController {
  final WorkOrderProvider _provider = Get.find<WorkOrderProvider>();
  var workOrders = <WorkOrder>[].obs;
  var isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    fetchWorkOrders();
  }

  Future<void> fetchWorkOrders() async {
    isLoading.value = true;
    try {
      final response = await _provider.getWorkOrders();
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        workOrders.value = data.map((json) => WorkOrder.fromJson(json)).toList();
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to fetch Work Orders: $e');
    } finally {
      isLoading.value = false;
    }
  }
}