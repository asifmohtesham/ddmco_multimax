import 'dart:async';

import 'package:dio/dio.dart';
// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/item/widgets/share_item_quick_actions.dart';
import 'package:multimax/app/modules/stock_sheet/logic/photo_decoder.dart';

const _photo = '/shared/label.jpg';

class _Decoder implements PhotoDecoder {
  _Decoder(this.whole, {this.zoomed = const []});

  final List<String>? whole;
  final List<String> zoomed;
  int zoomCalls = 0;
  int disposed = 0;

  @override
  Future<List<String>?> readWhole(String path) async {
    expect(path, _photo);
    return whole;
  }

  @override
  Future<List<String>?> zoomIn(
    String path, {
    required List<String> whole,
    bool Function()? stopped,
  }) async {
    zoomCalls++;
    return zoomed;
  }

  @override
  Future<void> dispose() async => disposed++;
}

Item _item({String? variantOf = 'WALLET', String? image}) {
  return Item(
    name: '1000001',
    itemCode: '1000001',
    itemName: 'Blue Wallet',
    itemGroup: 'Wallets',
    variantOf: variantOf,
    image: image,
  );
}

void main() {
  late List<String> lookups;
  late List<String> permissionChecks;
  late List<ShareItemDestination> destinations;
  late RxBool reportAccess;

  setUp(() {
    lookups = [];
    permissionChecks = [];
    destinations = [];
    reportAccess = true.obs;
  });

  Future<void> mount(
    WidgetTester tester,
    _Decoder decoder, {
    Future<Item?> Function(String)? lookup,
    Future<String?> Function(BuildContext)? scan,
    Future<String?> Function(BuildContext, String)? upload,
    bool canUpload = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShareItemQuickActions(
            photoPath: _photo,
            createDecoder: () => decoder,
            lookup: (barcode) async {
              lookups.add(barcode);
              return lookup == null ? _item() : await lookup(barcode);
            },
            canUpload: (itemCode) async {
              permissionChecks.add(itemCode);
              return canUpload;
            },
            canOpenSuppliers: () => reportAccess.value,
            upload: upload ?? (_, _) async => null,
            imageUrl: (_) => '',
            scan: scan,
            onSelect: destinations.add,
          ),
        ),
      ),
    );
  }

  testWidgets('one distinct barcode loads the Item and header opens its form', (
    tester,
  ) async {
    final decoder = _Decoder([' 12345678 ', '12345678', '']);
    final resolved = Completer<Item?>();
    await mount(tester, decoder, lookup: (_) => resolved.future);
    await tester.pump();
    expect(find.text('Looking up Item…'), findsOneWidget);

    resolved.complete(_item());
    await tester.pumpAndSettle();
    expect(lookups, ['12345678']);
    expect(decoder.zoomCalls, 0);
    expect(decoder.disposed, 1);
    expect(find.textContaining('Variant of WALLET'), findsWidgets);
    expect(find.textContaining('1000001'), findsOneWidget);
    await tester.tap(find.text('Blue Wallet'));
    expect(destinations.single.route, AppRoutes.ITEM_FORM);
    expect(destinations.single.arguments, {'itemCode': '1000001'});
  });

  testWidgets('several barcode values wait for a choice and can be revisited', (
    tester,
  ) async {
    await mount(
      tester,
      _Decoder(['ITEM-A', 'ITEM-B', 'ITEM-A']),
      lookup: (code) async => code == 'ITEM-A' ? null : _item(),
    );
    await tester.pumpAndSettle();
    expect(lookups, isEmpty);
    expect(find.text('ITEM-A'), findsOneWidget);
    expect(find.text('ITEM-B'), findsOneWidget);

    await tester.tap(find.text('ITEM-A'));
    await tester.pumpAndSettle();
    expect(lookups, ['ITEM-A']);
    expect(find.text('No Item matches this barcode.\nITEM-A'), findsOneWidget);
    await tester.tap(find.text('Choose another barcode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ITEM-B'));
    await tester.pumpAndSettle();
    expect(lookups, ['ITEM-A', 'ITEM-B']);
    expect(find.text('Blue Wallet'), findsOneWidget);
  });

  testWidgets('no barcode offers the camera and the original photo workflow', (
    tester,
  ) async {
    final decoder = _Decoder([]);
    await mount(tester, decoder, scan: (_) async => 'FROM-CAMERA');
    await tester.pumpAndSettle();
    expect(decoder.zoomCalls, 1);
    expect(find.text('No barcode found in this photo.'), findsOneWidget);
    await tester.tap(find.text('Items from Photos'));
    expect(destinations.single.route, AppRoutes.ITEMS_FROM_PHOTOS);
    expect(destinations.single.arguments, [_photo]);

    await tester.tap(find.text('Scan with camera'));
    await tester.pumpAndSettle();
    expect(lookups, ['FROM-CAMERA']);
    expect(find.text('Blue Wallet'), findsOneWidget);
  });

  testWidgets('an unreadable photo offers the existing photo workflow', (
    tester,
  ) async {
    await mount(tester, _Decoder(null));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't read this photo."), findsOneWidget);
    expect(find.text('Items from Photos'), findsOneWidget);
    expect(lookups, isEmpty);
  });

  testWidgets('uses a small barcode from the tiled image retry', (
    tester,
  ) async {
    await mount(tester, _Decoder([], zoomed: ['SMALL-CODE']));
    await tester.pumpAndSettle();
    expect(lookups, ['SMALL-CODE']);
    expect(find.text('Blue Wallet'), findsOneWidget);
  });

  testWidgets('sanitizes lookup errors and retries the selected barcode', (
    tester,
  ) async {
    var attempts = 0;
    final request = RequestOptions(path: '/internal-trace');
    await mount(
      tester,
      _Decoder(['BARCODE']),
      lookup: (_) async {
        attempts++;
        if (attempts == 1) {
          throw DioException(
            requestOptions: request,
            message: 'internal trace',
            type: DioExceptionType.badResponse,
            response: Response(requestOptions: request, statusCode: 403),
          );
        }
        if (attempts == 2) {
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.connectionError,
          );
        }
        return _item();
      },
    );
    await tester.pumpAndSettle();
    expect(
      find.text("You don't have permission to look up this Item."),
      findsOneWidget,
    );
    expect(find.textContaining('internal'), findsNothing);

    await tester.tap(find.text('Retry lookup'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not reach the server'), findsOneWidget);
    await tester.tap(find.text('Retry lookup'));
    await tester.pumpAndSettle();
    expect(lookups, ['BARCODE', 'BARCODE', 'BARCODE']);
    expect(find.text('Blue Wallet'), findsOneWidget);
  });

  for (final variantOf in ['WALLET', null]) {
    testWidgets('uses the correct report filter for variant $variantOf', (
      tester,
    ) async {
      await mount(
        tester,
        _Decoder(['BARCODE']),
        lookup: (_) async => _item(variantOf: variantOf),
      );
      await tester.pumpAndSettle();
      final label = variantOf == null
          ? 'Suppliers for this Item'
          : 'Suppliers by Item';
      await tester.tap(find.text(label));
      final destination = destinations.single;
      expect(destination.route, AppRoutes.SUPPLIERS_BY_ITEM);
      final filters = destination.arguments as SuppliersByItemFilters;
      expect(filters.variantOf, [?variantOf]);
      expect(filters.items, variantOf == null ? ['1000001'] : isEmpty);

      reportAccess.value = false;
      await tester.pumpAndSettle();
      expect(find.text(label), findsNothing);
    });
  }

  testWidgets('offers upload for a missing image and hides it after upload', (
    tester,
  ) async {
    await mount(
      tester,
      _Decoder(['BARCODE']),
      upload: (_, code) async {
        expect(code, '1000001');
        return '/files/uploaded.jpg';
      },
    );
    await tester.pumpAndSettle();
    expect(permissionChecks, ['1000001']);
    await tester.tap(find.text('Upload Item Image'));
    await tester.pumpAndSettle();
    expect(find.text('Upload Item Image'), findsNothing);
  });

  testWidgets(
    'does not offer upload for an existing image or a read-only Item',
    (tester) async {
      await mount(
        tester,
        _Decoder(['BARCODE']),
        lookup: (_) async => _item(image: '/files/existing.jpg'),
      );
      await tester.pumpAndSettle();
      expect(permissionChecks, isEmpty);
      expect(find.text('Upload Item Image'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester, _Decoder(['BARCODE']), canUpload: false);
      await tester.pumpAndSettle();
      expect(permissionChecks, ['1000001']);
      expect(find.text('Upload Item Image'), findsNothing);
    },
  );
}
