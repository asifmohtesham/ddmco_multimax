import 'package:get/get.dart';
import 'package:multimax/app/modules/about/about_controller.dart';

class AboutBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AboutController>(() => AboutController());
  }
}