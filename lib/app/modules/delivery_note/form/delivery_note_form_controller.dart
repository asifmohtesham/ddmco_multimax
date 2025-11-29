import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/delivery_note_model.dart';
import 'package:ddmco_multimax/app/data/providers/delivery_note_provider.dart';

class DeliveryNoteFormController extends GetxController {
  final DeliveryNoteProvider _provider = Get.find<DeliveryNoteProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];
  final String? posUploadCustomer = Get.arguments['posUploadCustomer'];

  var isLoading = true.obs;
  var deliveryNote = Rx<DeliveryNote?>(null);

  @override
  void onInit() {
    super.onInit();
    if (mode == 'new') {
      _createNewDeliveryNote();
    } else {
      fetchDeliveryNote();
    }
  }

  void _createNewDeliveryNote() {
    // Create a new empty DeliveryNote, optionally pre-filling data
    deliveryNote.value = DeliveryNote(
      name: '',
      customer: posUploadCustomer ?? '',
      grandTotal: 0.0,
      postingDate: DateTime.now().toString().split(' ')[0], // Today's date
      modified: '',
      status: 'Draft',
      currency: 'USD', // Default or fetch from settings
      items: [],
    );
    isLoading.value = false;
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
