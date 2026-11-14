import 'package:get/get.dart';
import 'package:multimax/app/data/providers/attendance_provider.dart';
import 'package:multimax/app/modules/hr/attendance/month/attendance_month_controller.dart';

class AttendanceMonthBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AttendanceProvider>(() => AttendanceProvider());
    Get.lazyPut<AttendanceMonthController>(() => AttendanceMonthController());
  }
}
