import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/home/home_controller.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<HomeController>(() => HomeController());
    // You might also put controllers for sub-pages if they are part of the Home "shell"
    // or if the bottom bar needs to interact with them directly.
    // Otherwise, their respective bindings will handle them.
  }
}