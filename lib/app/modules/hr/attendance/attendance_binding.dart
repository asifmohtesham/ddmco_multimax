import 'package:get/get.dart';
import 'package:multimax/app/data/providers/attendance_provider.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_controller.dart';

class AttendanceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AttendanceProvider>(() => AttendanceProvider());
    Get.lazyPut<AttendanceController>(() => AttendanceController());
  }
}
