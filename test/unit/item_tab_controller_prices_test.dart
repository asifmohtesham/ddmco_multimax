import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/item/form/item_tab_controller.dart';

/// Sales-User smoke (2026-09-18): the Prices tab was offered to users who can
/// read neither Item Price nor Pricing Rule, and only ever showed a lock
/// message — on every item they opened, while the drawer hid both entries.
class _Perms extends PermissionService {
  _Perms(this.access);
  final Map<String, bool?> access;
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => access[doctype];
}

ItemTabController _open(PermissionService Function()? perms) {
  Get.put<ApiProvider>(ApiProvider());
  if (perms != null) Get.put<PermissionService>(perms());
  return Get.put(ItemTabController());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  test('no access to either DocType drops the Prices tab', () {
    final c = _open(() => _Perms({'Item Price': false, 'Pricing Rule': false}));
    expect(c.showPrices, isFalse);
    expect(c.tabController.length, 5);
  });

  test('access to either DocType keeps it', () {
    final c = _open(() => _Perms({'Item Price': false, 'Pricing Rule': true}));
    expect(c.showPrices, isTrue);
    expect(c.tabController.length, 6);
  });

  test('unknown permissions keep it (the tab has its own no-access state)',
      () {
    expect(_open(() => _Perms({})).tabController.length, 6);
    Get.reset();
    Get.testMode = true;
    expect(_open(null).tabController.length, 6);
  });
}
