import 'dart:async';

import 'package:dio/dio.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/sales_order_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_strip.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_controller.dart';

class _Request {
  _Request(this.offset, this.filters, this.search);

  final int offset;
  final Map<String, dynamic>? filters;
  final Map<String, dynamic>? search;
  final response = Completer<Response>();

  void succeed(String prefix, {int count = 1}) => response.complete(
    Response(
      requestOptions: RequestOptions(),
      statusCode: 200,
      data: {
        'data': [
          for (var i = 0; i < count; i++) {'name': '$prefix-$i'},
        ],
      },
    ),
  );

  void fail() => response.completeError(StateError('Request failed'));
}

class _SalesOrders extends SalesOrderProvider {
  final requests = <_Request>[];

  @override
  Future<Response> getSalesOrders({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    Map<String, dynamic>? orFilters,
    String orderBy = 'modified desc',
  }) {
    final request = _Request(limitStart, filters, orFilters);
    requests.add(request);
    return request.response.future;
  }
}

void main() {
  late _SalesOrders provider;
  late SalesOrderController controller;

  setUp(() {
    Get.testMode = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => r'C:\temp\test_cookies',
        );
    Get.put(ApiProvider());
    Get.put(AuthenticationController()).currentUser.value = User(
      id: 'me@example.test',
      name: 'Me',
      email: 'me@example.test',
      roles: [],
    );
    provider = Get.put<SalesOrderProvider>(_SalesOrders()) as _SalesOrders;
    Get.put(UserProvider());
  });

  tearDown(Get.reset);

  testWidgets('duplicate quick activation mutates and fetches once', (
    tester,
  ) async {
    controller = Get.put(SalesOrderController());
    provider.requests.single.succeed('initial');
    await tester.pump();
    controller.setScope(ActionableScope.mine);
    controller.setStatusChip('Draft');
    controller.setScope(ActionableScope.everyone);
    final mine = provider.requests.last;
    expect(provider.requests, hasLength(2));
    expect(controller.scope.value, ActionableScope.mine);
    expect(controller.activeFilters, isEmpty);
    expect(mine.filters, {'owner': 'me@example.test'});

    final first = controller.fetch(clear: true);
    final same = controller.fetch(clear: true);
    expect(identical(first, same), isTrue);
    expect(provider.requests, hasLength(2));
    mine.succeed('mine');
    await first;
    controller.setScope(ActionableScope.mine);
    expect(provider.requests, hasLength(2));

    controller.setStatusChip('Draft');
    controller.setStatusChip('Draft');
    expect(controller.activeFilters['status'], 'Draft');
    expect(provider.requests, hasLength(3));
    provider.requests.last.succeed('draft');
    await tester.pump();
    controller.setStatusChip('Draft');
    expect(controller.activeFilters.containsKey('status'), isFalse);
    expect(provider.requests, hasLength(4));
    provider.requests.last.succeed('mine');
    await tester.pump();
  });

  testWidgets(
    'stale clear and page responses cannot change current rows or busy flags',
    (tester) async {
      controller = Get.put(SalesOrderController());
      final initial = provider.requests.single;
      var statuses = ['Draft', 'On Hold'];
      controller.applyFilters({
        'status': ['in', statuses],
        'owner': 'another@example.test',
      });
      final old = provider.requests.last;
      statuses.add('Closed');
      expect(old.filters, {
        'owner': 'another@example.test',
        'status': [
          'in',
          ['Draft', 'On Hold'],
        ],
      });
      controller.onSearchChanged('  Needle  ');
      await tester.pump(const Duration(milliseconds: 510));
      final latest = provider.requests.last;
      expect(latest.offset, 0);
      expect(latest.search, {
        'name': ['like', '%Needle%'],
        'customer_name': ['like', '%Needle%'],
      });

      initial.fail();
      await tester.pump();
      expect(controller.isLoading.value, isTrue);
      expect(controller.orders, isEmpty);
      await controller.fetch(isLoadMore: true);
      expect(provider.requests, hasLength(3));
      latest.succeed('needle', count: 20);
      await tester.pump();
      expect(controller.isLoading.value, isFalse);
      expect(controller.hasMore.value, isTrue);
      expect(controller.orders.first.name, 'needle-0');

      final appendFuture = controller.fetch(isLoadMore: true);
      final append = provider.requests.last;
      expect(append.offset, 20);
      expect(controller.isFetchingMore.value, isTrue);
      controller.setStatusChip('Completed');
      final replacement = provider.requests.last;
      expect(replacement.offset, 0);
      expect(replacement.filters!['owner'], 'another@example.test');
      expect(controller.orders, isEmpty);
      expect(controller.isFetchingMore.value, isFalse);
      append.succeed('obsolete-page');
      await appendFuture;
      expect(controller.isLoading.value, isTrue);
      replacement.succeed('replacement', count: 20);
      await tester.pump();

      final activePageFuture = controller.fetch(isLoadMore: true);
      final activePage = provider.requests.last;
      expect(activePage.offset, 20);
      old.succeed('obsolete-clear');
      await tester.pump();
      expect(controller.isFetchingMore.value, isTrue);
      expect(controller.orders, hasLength(20));
      activePage.succeed('replacement-page');
      await activePageFuture;
      expect(controller.orders.last.name, 'replacement-page-0');
      expect(controller.hasMore.value, isFalse);
    },
  );

  testWidgets(
    'search invalidates an in-flight append before the next dispatch',
    (tester) async {
      controller = Get.put(SalesOrderController());
      provider.requests.single.succeed('initial');
      await tester.pump();
      controller.onSearchChanged('A');
      await tester.pump(const Duration(milliseconds: 510));
      provider.requests.last.succeed('a', count: 20);
      await tester.pump();

      final appendFuture = controller.fetch(isLoadMore: true);
      final append = provider.requests.last;
      expect(append.offset, 20);
      controller.onSearchChanged('B');
      append.succeed('obsolete-a-page');
      await appendFuture;
      await tester.pump(const Duration(milliseconds: 100));

      expect(provider.requests, hasLength(3));
      expect(controller.searchQuery.value, 'B');
      expect(controller.orders, isEmpty);
      expect(controller.isLoading.value, isTrue);
      expect(controller.isFetchingMore.value, isFalse);
      await tester.pump(const Duration(milliseconds: 410));
      final replacement = provider.requests.last;
      expect(replacement.offset, 0);
      expect(replacement.search!['name'], ['like', '%B%']);
      replacement.succeed('b');
      await tester.pump();
      expect(controller.orders.single.name, 'b-0');
    },
  );

  testWidgets(
    'returning to an earlier search query dispatches a fresh first page',
    (tester) async {
      controller = Get.put(SalesOrderController());
      provider.requests.single.succeed('initial');
      await tester.pump();
      controller.onSearchChanged('A');
      await tester.pump(const Duration(milliseconds: 510));
      final firstA = provider.requests.last;

      controller.onSearchChanged('B');
      await tester.pump(const Duration(milliseconds: 100));
      controller.onSearchChanged('  A  ');
      firstA.succeed('obsolete-a');
      await tester.pump(const Duration(milliseconds: 100));
      expect(provider.requests, hasLength(2));
      expect(controller.orders, isEmpty);
      expect(controller.isLoading.value, isTrue);

      await tester.pump(const Duration(milliseconds: 410));
      final latestA = provider.requests.last;
      expect(provider.requests, hasLength(3));
      expect(latestA.offset, 0);
      expect(latestA.search!['name'], ['like', '%A%']);
      controller.onSearchChanged('A');
      latestA.succeed('current-a');
      await tester.pump(const Duration(milliseconds: 510));
      expect(provider.requests, hasLength(3));
      expect(controller.orders.single.name, 'current-a-0');
      expect(controller.isLoading.value, isFalse);
    },
  );

  testWidgets('dismissing a failed refresh leaves the next page available', (
    tester,
  ) async {
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    controller = Get.put(SalesOrderController());
    provider.requests.single.succeed('initial', count: 20);
    await tester.pumpAndSettle();

    final refresh = controller.fetch(clear: true);
    expect(provider.requests.last.offset, 0);
    provider.requests.last.fail();
    await refresh;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(controller.orders, hasLength(20));
    expect(controller.hasMore.value, isTrue);

    final nextPage = controller.fetch(isLoadMore: true);
    expect(provider.requests, hasLength(3));
    expect(provider.requests.last.offset, 20);
    provider.requests.last.succeed('continued');
    await nextPage;
    expect(controller.orders.last.name, 'continued-0');
    expect(controller.hasMore.value, isFalse);
  });

  testWidgets('retry belongs to the active criteria and page', (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    controller = Get.put(SalesOrderController());
    provider.requests.single.succeed('current', count: 20);
    await tester.pumpAndSettle();

    controller.fetch(isLoadMore: true);
    provider.requests.last.fail();
    await tester.pumpAndSettle();
    expect(controller.isFetchingMore.value, isFalse);
    expect(controller.orders, hasLength(20));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(provider.requests.last.offset, 20);
    provider.requests.last.succeed('retry-page');
    await tester.pumpAndSettle();
    expect(controller.orders.last.name, 'retry-page-0');

    controller.fetch(clear: true);
    expect(controller.orders.last.name, 'retry-page-0');
    expect(controller.hasMore.value, isFalse);
    provider.requests.last.fail();
    await tester.pumpAndSettle();
    expect(controller.isLoading.value, isFalse);
    expect(controller.orders.last.name, 'retry-page-0');
    controller.applyFilters({'customer': 'New Customer'});
    provider.requests.last.fail();
    await tester.pumpAndSettle();
    expect(controller.orders, isEmpty);
    expect(controller.isLoading.value, isFalse);
    final count = provider.requests.length;
    await controller.fetch(isLoadMore: true);
    expect(provider.requests, hasLength(count));

    await tester.tap(find.text('Retry').last);
    await tester.pumpAndSettle();
    final retry = provider.requests.last;
    expect(retry.offset, 0);
    expect(retry.filters, {'customer': 'New Customer'});
    retry.succeed('recovered');
    await tester.pumpAndSettle();
    expect(controller.orders.single.name, 'recovered-0');
    final afterRetry = provider.requests.length;
    final obsolete = find.text('Retry');
    if (obsolete.evaluate().isNotEmpty) {
      await tester.tap(obsolete);
      await tester.pumpAndSettle();
    }
    expect(provider.requests, hasLength(afterRetry));
  });
}
