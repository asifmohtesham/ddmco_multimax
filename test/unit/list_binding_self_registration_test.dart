import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';
import 'package:multimax/app/data/providers/material_request_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'package:multimax/app/modules/job_card/job_card_binding.dart';
import 'package:multimax/app/modules/job_card/job_card_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/job_card_summary/job_card_summary_binding.dart';
import 'package:multimax/app/modules/manufacturing/reports/job_card_summary/job_card_summary_controller.dart';
import 'package:multimax/app/modules/material_request/material_request_binding.dart';
import 'package:multimax/app/modules/material_request/material_request_controller.dart';

void main() {
  setUp(Get.reset);
  tearDown(Get.reset);

  // Regression: each list/report controller resolves these providers via
  // Get.find at construction. They only worked because HomeBinding happens
  // to register them; the route's own binding must supply them so the screen
  // does not depend on Home being on the stack.

  test('JobCardBinding registers UserProvider', () {
    JobCardBinding().dependencies();

    expect(Get.isRegistered<UserProvider>(), isTrue,
        reason: 'list route must supply its own UserProvider');
    expect(Get.isRegistered<JobCardProvider>(), isTrue);
    expect(Get.isRegistered<JobCardController>(), isTrue);
  });

  test('MaterialRequestBinding registers UserProvider', () {
    MaterialRequestBinding().dependencies();

    expect(Get.isRegistered<UserProvider>(), isTrue,
        reason: 'list route must supply its own UserProvider');
    expect(Get.isRegistered<MaterialRequestProvider>(), isTrue);
    expect(Get.isRegistered<MaterialRequestController>(), isTrue);
  });

  test('JobCardSummaryBinding registers WorkOrderProvider', () {
    JobCardSummaryBinding().dependencies();

    expect(Get.isRegistered<WorkOrderProvider>(), isTrue,
        reason: 'report route must supply its own WorkOrderProvider');
    expect(Get.isRegistered<JobCardSummaryController>(), isTrue);
  });
}
