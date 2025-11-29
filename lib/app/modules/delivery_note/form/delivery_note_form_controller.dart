import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/delivery_note_model.dart';
import 'package:ddmco_multimax/app/data/providers/delivery_note_provider.dart';

class DeliveryNoteFormController extends GetxController {
  final DeliveryNoteProvider _provider = Get.find<DeliveryNoteProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var deliveryNote = Rx<DeliveryNote?>(null);

  @override
  void onInit() {
    super.onInit();
    fetchDeliveryNote();
  }

  Future<void> fetchDeliveryNote() async {
    isLoading.value = true;
    try {
      final response = await _provider.getDeliveryNote(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        deliveryNote.value = DeliveryNote.fromJson(response.data['data']);
      } else {
        Get.snackbar('Error', 'Failed to fetch delivery note');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      isLoading.value = false;
    }
  }
}
