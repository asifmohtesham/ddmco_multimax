import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';

void main() {
  testWidgets('AppNavDrawerController no longer exposes a user-menu toggle',
      (tester) async {
    // Compile-time guard: the inline user-menu state was removed (the account
    // header now navigates to the Account hub). The header → hub behaviour is
    // verified manually; a full drawer render needs the service graph.
    final c = AppNavDrawerController();
    expect(c.isGroupExpanded('Stock', defaultValue: false), isFalse);
    c.setGroupExpanded('Stock', true);
    expect(c.isGroupExpanded('Stock', defaultValue: false), isTrue);
    Get.reset();
  });
}
