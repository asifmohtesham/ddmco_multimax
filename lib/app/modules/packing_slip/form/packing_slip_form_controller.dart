import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/packing_slip_model.dart';
import 'package:ddmco_multimax/app/data/providers/packing_slip_provider.dart';

class PackingSlipFormController extends GetxController {
  final PackingSlipProvider _provider = Get.find<PackingSlipProvider>();
  
  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode']; // 'view' or 'edit' (likely view only for now)

  var isLoading = true.obs;
  var packingSlip = Rx<PackingSlip?>(null);

  @override
  void onInit() {
    super.onInit();
    fetchPackingSlip();
  }

  Future<void> fetchPackingSlip() async {
    isLoading.value = true;
    try {
      final response = await _provider.getPackingSlip(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        packingSlip.value = PackingSlip.fromJson(response.data['data']);
      } else {
        Get.snackbar('Error', 'Failed to fetch packing slip details');
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to load data: ${e.toString()}');
    } finally {
      isLoading.value = false;
    }
  }
}
