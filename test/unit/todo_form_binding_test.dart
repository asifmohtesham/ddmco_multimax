import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/todo_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/modules/todo/form/todo_form_binding.dart';
import 'package:multimax/app/modules/todo/form/todo_form_controller.dart';

void main() {
  setUp(Get.reset);
  tearDown(Get.reset);

  // Regression class: the TODO_FORM route previously shipped with no
  // binding at all, so opening it from a dashboard deep-link (or any
  // entry point other than the ToDo list) crashed with "ToDoProvider not
  // found". The form controller resolves its providers via Get.find at
  // construction, so the route's own binding must register them.
  test(
      'ToDoFormBinding self-registers the providers the form controller '
      'needs', () {
    ToDoFormBinding().dependencies();

    expect(Get.isRegistered<ToDoProvider>(), isTrue,
        reason: 'form route must supply its own ToDoProvider');
    expect(Get.isRegistered<UserProvider>(), isTrue,
        reason: 'form route must supply its own UserProvider');
    expect(Get.isRegistered<ToDoFormController>(), isTrue);
  });
}
