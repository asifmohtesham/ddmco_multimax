import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/todo/todo_controller.dart';
import 'package:ddmco_multimax/app/data/providers/todo_provider.dart';

class ToDoBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ToDoProvider>(() => ToDoProvider());
    Get.lazyPut<ToDoController>(() => ToDoController());
  }
}
