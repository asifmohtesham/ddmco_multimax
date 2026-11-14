import 'package:get/get.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';

class ThemeBinding extends Bindings {
  @override
  void dependencies() {
    // ThemeController is normally registered permanent in main(); ensure it
    // exists if this route is reached in isolation.
    if (!Get.isRegistered<ThemeController>()) {
      Get.put<ThemeController>(ThemeController(), permanent: true);
    }
  }
}
