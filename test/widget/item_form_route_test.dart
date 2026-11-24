import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/item/form/item_form_binding.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/item/form/item_form_screen.dart';
import 'package:multimax/app/modules/item/form/item_tab_controller.dart';

import '../helpers/auth_fakes.dart';

class _ItemApi extends FakeApiProvider {
  final itemRequests = <String>[];

  @override
  Future<Response> getDocument(String doctype, String name) async {
    expect(doctype, 'Item');
    itemRequests.add(name);
    final itemCode = Uri.decodeComponent(name);
    return jsonResponse({
      'data': {'name': itemCode, 'item_code': itemCode, 'item_name': itemCode},
    });
  }
}

void main() {
  testWidgets('stacked Item forms and the modal keep separate state', (
    tester,
  ) async {
    Get.testMode = true;
    addTearDown(Get.reset);
    final api = _ItemApi();
    Get.put<ApiProvider>(api);
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: '/',
        getPages: [
          GetPage(name: '/', page: () => const SizedBox.shrink()),
          GetPage(
            name: AppRoutes.ITEM_FORM,
            page: () => const ItemFormScreen(),
            binding: ItemFormBinding(),
            transition: Transition.noTransition,
          ),
        ],
      ),
    );

    final form = find.byType(ItemFormScreen);
    String? formTag() =>
        ItemFormBinding.tagForRoute(ModalRoute.of(tester.element(form)));
    String title() =>
        tester.widget<DocTypeFormHeader>(find.byType(DocTypeFormHeader)).title;

    Get.put(ItemProvider());
    final modalTabs = Get.put(ItemTabController());
    final modal = Get.put(ItemFormController())..loadItem('MODAL');
    unawaited(Get.bottomSheet<void>(const ItemFormScreen()));
    await tester.pumpAndSettle();
    expect(formTag(), isNull);
    expect(title(), 'MODAL');

    unawaited(Get.toNamed<void>(AppRoutes.ITEM_FORM, arguments: 'ITEM-1'));
    await tester.pumpAndSettle();
    final firstTag = formTag();
    final first = Get.find<ItemFormController>(tag: firstTag);
    final firstTabs = Get.find<ItemTabController>(tag: firstTag);
    expect(title(), 'ITEM-1');
    await tester.tap(find.text('Attributes'));
    await tester.pumpAndSettle();
    expect(firstTabs.tabController.index, 2);

    unawaited(
      Get.toNamed<void>(
        AppRoutes.ITEM_FORM,
        arguments: {'itemCode': 'ITEM/2#', 'batchNo': 'BATCH-2'},
        preventDuplicates: false,
      ),
    );
    await tester.pumpAndSettle();
    final secondTag = formTag();
    final second = Get.find<ItemFormController>(tag: secondTag);
    final secondTabs = Get.find<ItemTabController>(tag: secondTag);
    expect(title(), 'ITEM/2#');
    expect(second.itemCode, 'ITEM/2#');
    expect(second.highlightedBatchNo.value, 'BATCH-2');
    expect(secondTabs.tabController.index, 0);
    expect(firstTabs.tabController.index, 2);
    expect(api.itemRequests, ['MODAL', 'ITEM-1', 'ITEM%2F2%23']);

    Get.back<void>();
    await tester.pumpAndSettle();
    expect(title(), 'ITEM-1');
    expect(first.isClosed, isFalse);
    expect(second.isClosed, isTrue);
    expect(secondTabs.isClosed, isTrue);

    Get.back<void>();
    await tester.pumpAndSettle();
    expect(title(), 'MODAL');
    expect(first.isClosed, isTrue);
    expect(modal.isClosed, isFalse);
    expect(modalTabs.isClosed, isFalse);

    Get.back<void>();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
