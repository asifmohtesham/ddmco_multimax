import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/user_model.dart';

User _u(List<String> roles) =>
    User(id: 'a@b.c', name: 'A', email: 'a@b.c', roles: roles);

void main() {
  group('User.isManager', () {
    test('true for any *Manager role (case-insensitive)', () {
      expect(_u(['Stock Manager']).isManager, isTrue);
      expect(_u(['System Manager']).isManager, isTrue);
      expect(_u(['Purchase Manager']).isManager, isTrue);
      expect(_u(['sales manager']).isManager, isTrue);
      expect(_u(['Stock User', 'Manufacturing Manager']).isManager, isTrue);
    });
    test('false when no role contains manager', () {
      expect(_u(['Stock User']).isManager, isFalse);
      expect(_u(['Employee', 'Sales User']).isManager, isFalse);
      expect(_u(const <String>[]).isManager, isFalse);
    });
  });
}
