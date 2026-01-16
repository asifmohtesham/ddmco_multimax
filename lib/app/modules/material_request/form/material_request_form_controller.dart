import 'package:get/get.dart';
import 'package:multimax/controllers/frappe_form_controller.dart';
import 'package:intl/intl.dart';

class MaterialRequestFormController extends FrappeFormController {
  MaterialRequestFormController() : super(doctype: 'Material Request');

  @override
  void onInit() {
    super.onInit();

    final args = Get.arguments;

    // Robust initialization logic
    if (args == null ||
        (args is Map && (args['mode'] == 'new' || args['name'] == null))) {
      _initNewRequest();
    } else if (args is Map && args['name'] != null) {
      load(args['name']);
    } else if (args is String) {
      load(args);
    }
  }

  void _initNewRequest() {
    final now = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Initialize default values to trigger UI rendering
    initialise({
      'naming_series': 'MAT-REQ-.YYYY.-',
      'material_request_type': 'Material Transfer',
      'transaction_date': now,
      'schedule_date': now,
      'status': 'Draft',
      'docstatus': 0,
      'items': [],
      '__islocal': 1, // Marks as new for API
    });
  }

  // Getters for UI Status Logic
  String get name => getValue('name') ?? 'New Request';

  String get status => getValue('status') ?? 'Draft';

  int get docstatus => getValue('docstatus') ?? 0;
}
