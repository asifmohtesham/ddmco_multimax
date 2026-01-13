import 'package:get/get.dart';
import 'package:multimax/controllers/frappe_form_controller.dart';

class BatchFormController extends FrappeFormController {
  BatchFormController() : super(doctype: 'Batch');

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args != null) {
      if (args is Map) {
        if (args['name'] != null && args['name'].toString().isNotEmpty) {
          load(args['name']);
        } else if (args['itemCode'] != null) {
          // Pre-fill item if creating new from Item screen
          setValue('item', args['itemCode']);
        }
      } else if (args is String) {
        load(args);
      }
    }
  }

  // Getters for UI logic
  String get batchId => getValue('name') ?? 'New Batch';
  String get itemCode => getValue('item') ?? '';

  bool get isExpired {
    final expiry = getValue<String>('expiry_date');
    if (expiry == null) return false;
    return DateTime.parse(expiry).isBefore(DateTime.now());
  }
}