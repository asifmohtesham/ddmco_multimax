import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/purchase_receipt_model.dart';
import 'package:ddmco_multimax/app/data/providers/purchase_receipt_provider.dart';

class PurchaseReceiptFormController extends GetxController {
  final PurchaseReceiptProvider _provider = Get.find<PurchaseReceiptProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var purchaseReceipt = Rx<PurchaseReceipt?>(null);

  @override
  void onInit() {
    super.onInit();
    fetchPurchaseReceipt();
  }

  Future<void> fetchPurchaseReceipt() async {
    isLoading.value = true;
    try {
      final response = await _provider.getPurchaseReceipt(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        purchaseReceipt.value = PurchaseReceipt.fromJson(response.data['data']);
      } else {
        Get.snackbar('Error', 'Failed to fetch purchase receipt');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      isLoading.value = false;
    }
  }
}
