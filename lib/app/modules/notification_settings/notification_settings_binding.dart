import 'package:get/get.dart';
import 'package:multimax/app/modules/notification_settings/notification_settings_controller.dart';

class NotificationSettingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<NotificationSettingsController>(
        () => NotificationSettingsController());
  }
}
