import 'package:get/get.dart';
import 'package:multimax/app/data/providers/todo_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/modules/todo/form/todo_form_controller.dart';

/// GetX dependency binding for the **ToDo form** route.
///
/// [ToDoProvider] is guarded with [Get.isRegistered] before registering —
/// when the user navigates List → Form, [ToDoBinding] has already registered
/// it; re-running [Get.lazyPut] without the guard would create a second
/// instance and leak the first. The guard is a no-op when the form is opened
/// cold (dashboard deep-link, global search) — both paths remain safe.
class ToDoFormBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<ToDoProvider>()) {
      Get.lazyPut<ToDoProvider>(() => ToDoProvider());
    }
    if (!Get.isRegistered<UserProvider>()) {
      Get.lazyPut<UserProvider>(() => UserProvider());
    }
    Get.lazyPut<ToDoFormController>(() => ToDoFormController());
  }
}
