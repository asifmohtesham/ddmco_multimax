import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/home/home_controller.dart';

void main() {
  group('HomeController.showTasksFirst', () {
    test('manager with open todos leads with tasks', () {
      expect(
        HomeController.showTasksFirst(
          roles: ['Stock User', 'Stock Manager'],
          hasOpenTodos: true,
        ),
        isTrue,
      );
    });

    test('manager with no open todos keeps operator layout', () {
      expect(
        HomeController.showTasksFirst(
          roles: ['Stock Manager'],
          hasOpenTodos: false,
        ),
        isFalse,
      );
    });

    test('operator keeps operator layout even with open todos', () {
      expect(
        HomeController.showTasksFirst(
          roles: ['Stock User', 'Sales User'],
          hasOpenTodos: true,
        ),
        isFalse,
      );
    });

    test('no roles at all is operator layout', () {
      expect(
        HomeController.showTasksFirst(roles: [], hasOpenTodos: true),
        isFalse,
      );
    });

    test('role match is case-insensitive', () {
      expect(
        HomeController.showTasksFirst(
          roles: ['manufacturing manager'],
          hasOpenTodos: true,
        ),
        isTrue,
      );
      expect(
        HomeController.showTasksFirst(
          roles: ['SYSTEM MANAGER'],
          hasOpenTodos: true,
        ),
        isTrue,
      );
    });

    test('custom "* Manager" roles match with no maintained list', () {
      expect(
        HomeController.showTasksFirst(
          roles: ['Delivery Manager'],
          hasOpenTodos: true,
        ),
        isTrue,
      );
    });

    // "management" does not contain the substring "manager" (no trailing
    // 'r') — so trainee/management-adjacent roles correctly do NOT count.
    test('"Management Trainee" is NOT managerish', () {
      expect(
        HomeController.showTasksFirst(
          roles: ['Management Trainee'],
          hasOpenTodos: true,
        ),
        isFalse,
      );
    });
  });
}
