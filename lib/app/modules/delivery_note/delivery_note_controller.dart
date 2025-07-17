import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/home/home_controller.dart'; // To update active screen

class DeliveryNoteController extends GetxController {
  final HomeController _homeController = Get.find<HomeController>();

  @override
  void onInit() {
    super.onInit();
    _homeController.activeScreen.value = ActiveScreen.stockEntry;
    _homeController.selectedDrawerIndex.value = 1; // Assuming Stock Entry is index 1
  }

// Add logic specific to Stock Entry here
// For example, methods to fetch stock items, add new stock, etc.
}