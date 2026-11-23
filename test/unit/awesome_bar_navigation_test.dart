import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/common/controllers/awesome_bar_controller.dart';

void main() {
  const itemCode = 'ITEM/001';

  for (final (doctype, name, route) in [
    ('Item', itemCode, AppRoutes.ITEM_FORM),
    ('Delivery Note', 'DN-001', AppRoutes.DELIVERY_NOTE_FORM),
  ]) {
    test('$doctype global-search hit opens its form', () {
      final option = AwesomeBarOption.fromGlobalSearchHit({
        'doctype': doctype,
        'name': name,
      })!;

      expect(option.route, route);
      expect(
        option.routeOptions,
        searchTargetForDoctype(doctype)!.argsFor(name),
      );
    });
  }

  for (final route in ['/app/Item/$itemCode', '']) {
    test('legacy Item recent resolves from route "$route"', () {
      final option = AwesomeBarOption.fromJson({
        'type': 'Item',
        'value': itemCode,
        'route': route,
      }).resolveNavigation()!;

      expect(option.route, AppRoutes.ITEM_FORM);
      expect(
        option.routeOptions,
        searchTargetForDoctype('Item')!.argsFor(itemCode),
      );
    });
  }

  test('List and New options keep their route and arguments', () {
    final list = AwesomeBarOption(
      type: 'List',
      label: 'Item List',
      value: 'Item List',
      route: AppRoutes.ITEM,
    );
    final create = AwesomeBarOption(
      type: 'New',
      label: 'New Item',
      value: 'New Item',
      route: AppRoutes.ITEM_FORM,
      routeOptions: {'mode': 'new'},
    );

    expect(list.resolveNavigation(), same(list));
    expect(create.resolveNavigation(), same(create));
  });

  test('unsupported doctypes have no global hit or legacy destination', () {
    expect(
      AwesomeBarOption.fromGlobalSearchHit({
        'doctype': 'Unknown Doctype',
        'name': 'UNKNOWN-001',
      }),
      isNull,
    );
    expect(
      AwesomeBarOption.fromJson({
        'type': 'Unknown Doctype',
        'value': 'UNKNOWN-001',
        'route': '/app/Unknown Doctype/UNKNOWN-001',
      }).resolveNavigation(),
      isNull,
    );
  });

  test('recent JSON round-trip preserves form arguments', () {
    final option = AwesomeBarOption.fromGlobalSearchHit({
      'doctype': 'Item',
      'name': itemCode,
    })!;

    final restored = AwesomeBarOption.fromJson(
      jsonDecode(jsonEncode(option.toJson())),
    );

    expect(restored.route, option.route);
    expect(restored.routeOptions, option.routeOptions);
  });
}
