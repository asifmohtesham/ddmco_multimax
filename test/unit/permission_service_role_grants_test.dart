import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/permission_service.dart';

void main() {
  group('PermissionService.roleGrants', () {
    test('System Manager is always granted, even with no permitted roles', () {
      expect(PermissionService.roleGrants({'System Manager'}, const {}), isTrue);
      expect(
          PermissionService.roleGrants(
              {'System Manager', 'Employee'}, {'Stock User'}),
          isTrue);
    });

    test('grants when the user holds any permitted role', () {
      expect(
          PermissionService.roleGrants(
              {'Employee', 'Stock User'}, {'Stock Manager', 'Stock User'}),
          isTrue);
    });

    test('denies when the user holds none of the permitted roles', () {
      expect(
          PermissionService.roleGrants(
              {'Employee', 'Sales User'}, {'Stock Manager', 'Purchase User'}),
          isFalse);
    });

    test('denies a non-admin when the permitted set is empty', () {
      expect(PermissionService.roleGrants({'Stock User'}, const {}), isFalse);
    });

    test('denies when the user has no roles at all', () {
      expect(PermissionService.roleGrants(const {}, {'Stock User'}), isFalse);
    });
  });
}
