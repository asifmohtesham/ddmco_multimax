import 'dart:async';

// Keep the app's shared Material APIs until its Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/batch_age_provider.dart';
import 'package:multimax/app/shared/item_sheet/batch_age_checker.dart';
import 'package:multimax/app/shared/item_sheet/batch_age_rule.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/shared/item_sheet/widgets/older_stock_sheet.dart';

const _dxb1 = 'WH-DXB1 - KA';
const _dxb3 = 'WH-DXB3 - KA';
const _group = 'Finished Goods - KA';
const _ecom = 'WH-ECOM - KA';
const _shop = 'POS-DXB1 - KA';

BatchAge _received(int y, int m, int d) =>
    BatchAge(DateTime(y, m, d), fromReceipt: true);

/// In-memory server: records what was asked so the tests can tell which
/// lookups a check really made.
class _FakeSource implements BatchAgeDataSource {
  Map<String, String?> parents = {_dxb1: _group, _dxb3: _group, _ecom: null};
  List<BatchStockLine> stock = [];
  Map<String, BatchAge> ages = {};
  List<BatchDraftLine> drafts = [];
  List<RackStockLine> racks = [];

  /// When set, every call throws it.
  Object? failure;
  Completer<String?>? parentLookup;

  final calls = <String>[];
  String? stockWarehouseAsked;
  String? rackWarehouseAsked;

  void _record(String call) {
    calls.add(call);
    if (failure != null) throw failure!;
  }

  @override
  Future<String?> parentWarehouse(String warehouse) async {
    _record('parent');
    return parentLookup?.future ?? parents[warehouse];
  }

  @override
  Future<List<BatchStockLine>> batchStock({
    required String itemCode,
    required String warehouse,
  }) async {
    _record('stock');
    stockWarehouseAsked = warehouse;
    return stock;
  }

  @override
  Future<Map<String, BatchAge>> batchAges(List<String> batchNos) async {
    _record('ages');
    return {
      for (final b in batchNos)
        if (ages.containsKey(b)) b: ages[b]!,
    };
  }

  @override
  Future<List<BatchDraftLine>> draftLines({required String itemCode}) async {
    _record('drafts');
    return drafts;
  }

  @override
  Future<List<RackStockLine>> rackStock({
    required String itemCode,
    required String warehouse,
  }) async {
    _record('racks');
    rackWarehouseAsked = warehouse;
    return racks;
  }
}

/// The smallest concrete item sheet: just enough to drive the shared gate.
class _Sheet extends ItemSheetControllerBase {
  bool enforce = true;
  String? warehouse = _dxb1;
  String? exempt;
  List<BatchDraftLine> own = const [];
  int sheetValidations = 0;

  @override
  bool get enforcesBatchAge => enforce;
  @override
  String? get batchAgeExemptBatch => exempt;
  @override
  List<BatchDraftLine> get batchAgeOwnLines => own;

  @override
  String? get resolvedWarehouse => warehouse;
  @override
  bool get requiresBatch => true;
  @override
  bool get requiresRack => false;
  @override
  Color get accentColor => Colors.teal;
  @override
  bool get isAddMode => true;
  @override
  String? get qtyInfoText => null;
  @override
  void validateSheet() => sheetValidations++;
  @override
  Future<void> submit() async {}
  @override
  void adjustQty(int delta) {}
  @override
  void deleteCurrentItem() {}
}

void main() {
  // The sheet controller looks for an overlay to show the refusal on; with
  // the binding up and no app running it finds none and stays quiet.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSource source;
  late BatchAgeChecker checker;

  setUp(() {
    source = _FakeSource()
      ..stock = [
        const BatchStockLine(batchNo: 'OLD', warehouse: _dxb1, qty: 12),
        const BatchStockLine(batchNo: 'NEW', warehouse: _dxb1, qty: 500),
      ]
      ..ages = {
        'OLD': _received(2025, 9, 10),
        'NEW': _received(2026, 7, 16),
      };
    checker = BatchAgeChecker(source);
    BatchAgeChecker.create = () => BatchAgeChecker(source);
  });

  tearDown(() => BatchAgeChecker.create = BatchAgeChecker.new);

  group('BatchAgeChecker.check', () {
    test('refuses the newer batch and names the older one', () async {
      final verdict = await checker.check(
          itemCode: 'ITEM', pickWarehouse: _dxb1, batchNo: 'NEW');
      expect(verdict.isRefused, isTrue);
      expect(verdict.older.single.batchNo, 'OLD');
      expect(verdict.scopeWarehouse, _group);
    });

    test('judges stock under the parent of the pick warehouse', () async {
      source.stock = [
        const BatchStockLine(batchNo: 'OLD', warehouse: _dxb3, qty: 2400),
        const BatchStockLine(batchNo: 'NEW', warehouse: _dxb1, qty: 833),
      ];
      final verdict = await checker.check(
          itemCode: 'ITEM', pickWarehouse: _dxb1, batchNo: 'NEW');
      expect(source.stockWarehouseAsked, _group);
      expect(verdict.older.single.qtyByWarehouse, {_dxb3: 2400.0});
    });

    test('a top-level warehouse is its own scope', () async {
      source.stock = [
        const BatchStockLine(batchNo: 'NEW', warehouse: _ecom, qty: 984),
      ];
      final verdict = await checker.check(
          itemCode: 'ITEM', pickWarehouse: _ecom, batchNo: 'NEW');
      expect(source.stockWarehouseAsked, _ecom);
      expect(verdict.isRefused, isFalse);
    });

    test('a pick outside the WH- warehouses asks the server nothing', () async {
      final verdict = await checker.check(
          itemCode: 'ITEM', pickWarehouse: _shop, batchNo: 'NEW');
      expect(verdict.isRefused, isFalse);
      expect(source.calls, isEmpty);

      await checker.check(itemCode: 'ITEM', pickWarehouse: null, batchNo: 'NEW');
      expect(source.calls, isEmpty);
    });

    test('a single batch in stock skips the age and draft lookups', () async {
      source.stock = [
        const BatchStockLine(batchNo: 'NEW', warehouse: _dxb1, qty: 500),
      ];
      final verdict = await checker.check(
          itemCode: 'ITEM', pickWarehouse: _dxb1, batchNo: 'NEW');
      expect(verdict.isRefused, isFalse);
      expect(source.calls, ['parent', 'stock']);
    });

    test('stock held outside the WH- warehouses does not block', () async {
      source.stock = [
        const BatchStockLine(batchNo: 'OLD', warehouse: _shop, qty: 40),
        const BatchStockLine(batchNo: 'NEW', warehouse: _dxb1, qty: 500),
      ];
      final verdict = await checker.check(
          itemCode: 'ITEM', pickWarehouse: _dxb1, batchNo: 'NEW');
      expect(verdict.isRefused, isFalse);
    });

    test('older stock already on another draft no longer blocks', () async {
      source.drafts = [
        const BatchDraftLine(
            batchNo: 'OLD',
            warehouse: _dxb1,
            qty: 12,
            doctype: 'Stock Entry',
            docName: 'MAT-STE-1'),
      ];
      final verdict = await checker.check(
          itemCode: 'ITEM', pickWarehouse: _dxb1, batchNo: 'NEW');
      expect(verdict.isRefused, isFalse);
    });

    test('the open document counts by its rows in memory, not its saved rows',
        () async {
      // Saved on the server: 12 of OLD on this very note. In memory the user
      // has since cut that row to 2, so 10 of OLD are free again.
      source.drafts = [
        const BatchDraftLine(
            batchNo: 'OLD',
            warehouse: _dxb1,
            qty: 12,
            doctype: 'Delivery Note',
            docName: 'MAT-DN-1'),
      ];
      final verdict = await checker.check(
        itemCode: 'ITEM',
        pickWarehouse: _dxb1,
        batchNo: 'NEW',
        ownDoctype: 'Delivery Note',
        ownDocName: 'MAT-DN-1',
        ownLines: const [
          BatchDraftLine(batchNo: 'OLD', warehouse: _dxb1, qty: 2),
        ],
      );
      expect(verdict.older.single.availableQty, 10);
    });

    test('a same-named document of another type is still counted', () async {
      source.drafts = [
        const BatchDraftLine(
            batchNo: 'OLD',
            warehouse: _dxb1,
            qty: 12,
            doctype: 'Stock Entry',
            docName: 'X-1'),
      ];
      final verdict = await checker.check(
        itemCode: 'ITEM',
        pickWarehouse: _dxb1,
        batchNo: 'NEW',
        ownDoctype: 'Delivery Note',
        ownDocName: 'X-1',
      );
      expect(verdict.isRefused, isFalse);
    });

    test('a lookup that fails is passed on, never read as "no older stock"',
        () async {
      source.failure = StateError('offline');
      expect(
        () => checker.check(
            itemCode: 'ITEM', pickWarehouse: _dxb1, batchNo: 'NEW'),
        throwsStateError,
      );
    });

    test('a missing age is an error, not a pass', () async {
      source.ages = {'NEW': _received(2026, 7, 16)};
      expect(
        () => checker.check(
            itemCode: 'ITEM', pickWarehouse: _dxb1, batchNo: 'NEW'),
        throwsA(isA<BatchAgeUnknown>()),
      );
    });
  });

  group('BatchAgeChecker.orderBreakReason', () {
    const before = [
      BatchDraftLine(batchNo: 'OLD', warehouse: _dxb1, qty: 12),
      BatchDraftLine(batchNo: 'NEW', warehouse: _dxb1, qty: 88),
    ];

    test('refuses an edit that frees older stock under a newer row', () async {
      final reason = await checker.orderBreakReason(
        itemCode: 'ITEM',
        pickWarehouse: _dxb1,
        linesBefore: before,
        linesAfter: const [
          BatchDraftLine(batchNo: 'NEW', warehouse: _dxb1, qty: 88),
        ],
      );
      expect(reason, contains('NEW'));
    });

    test('allows removing the newer row', () async {
      final reason = await checker.orderBreakReason(
        itemCode: 'ITEM',
        pickWarehouse: _dxb1,
        linesBefore: before,
        linesAfter: const [
          BatchDraftLine(batchNo: 'OLD', warehouse: _dxb1, qty: 12),
        ],
      );
      expect(reason, isNull);
    });

    test('does not apply outside the WH- warehouses', () async {
      final reason = await checker.orderBreakReason(
        itemCode: 'ITEM',
        pickWarehouse: _shop,
        linesBefore: before,
        linesAfter: const [],
      );
      expect(reason, isNull);
      expect(source.calls, isEmpty);
    });
  });

  group('BatchAgeChecker.racks', () {
    test('asks for the scope warehouse and keeps WH- racks only', () async {
      source.racks = const [
        RackStockLine(warehouse: _dxb1, rack: 'KA-WH-DXB1-9C', qty: 936),
        RackStockLine(warehouse: _shop, rack: 'KA-POS-DXB1-1', qty: 5),
        RackStockLine(warehouse: _dxb3, rack: '', qty: 36),
      ];
      final racks =
          await checker.racks(itemCode: 'ITEM', pickWarehouse: _dxb1);
      expect(source.rackWarehouseAsked, _group);
      expect(racks.map((r) => r.warehouse), [_dxb1, _dxb3]);
    });
  });

  group('item sheet gate (recheckBatchAge)', () {
    _Sheet sheetWith(String batch) => _Sheet()
      ..itemCode.value = 'ITEM'
      ..batchController.text = batch
      ..isBatchValid.value = true;

    test('refusal invalidates the batch and lists the older stock', () async {
      final sheet = sheetWith('NEW');
      await sheet.recheckBatchAge();

      expect(sheet.isBatchValid.value, isFalse);
      expect(sheet.batchError.value, kOlderStockMessage);
      expect(sheet.olderBatches.single.batchNo, 'OLD');
      expect(sheet.isValidatingBatch.value, isFalse);
      expect(sheet.sheetValidations, 1);
    });

    test('the oldest batch stays valid', () async {
      final sheet = sheetWith('OLD');
      await sheet.recheckBatchAge();

      expect(sheet.isBatchValid.value, isTrue);
      expect(sheet.batchError.value, isEmpty);
      expect(sheet.olderBatches, isEmpty);
    });

    test('a failed lookup refuses the batch (fail closed)', () async {
      source.failure = StateError('offline');
      final sheet = sheetWith('NEW');
      await sheet.recheckBatchAge();

      expect(sheet.isBatchValid.value, isFalse);
      expect(sheet.batchError.value, contains('Could not check'));
      expect(sheet.olderBatches, isEmpty);
    });

    test('the batch a row was saved with is never refused', () async {
      final sheet = sheetWith('NEW')..exempt = 'NEW';
      await sheet.recheckBatchAge();

      expect(sheet.isBatchValid.value, isTrue);
      expect(source.calls, isEmpty);
    });

    test('sheets that do not opt in are untouched', () async {
      final sheet = sheetWith('NEW')..enforce = false;
      await sheet.recheckBatchAge();

      expect(sheet.isBatchValid.value, isTrue);
      expect(source.calls, isEmpty);
    });

    test('an unknown pick warehouse passes, then is checked once it resolves',
        () async {
      final sheet = sheetWith('NEW')..warehouse = null;
      await sheet.recheckBatchAge();
      expect(sheet.isBatchValid.value, isTrue);
      expect(source.calls, isEmpty);

      // The rack scan resolves the warehouse.
      sheet.warehouse = _dxb1;
      await sheet.recheckBatchAge();
      expect(sheet.isBatchValid.value, isFalse);
      expect(sheet.olderBatches.single.batchNo, 'OLD');
    });

    test('a delayed refusal cannot invalidate a batch after the pick warehouse changes', () async {
      final pendingParent = Completer<String?>();
      source.parentLookup = pendingParent;
      final sheet = sheetWith('NEW');

      final oldCheck = sheet.recheckBatchAge();
      sheet.warehouse = _shop;
      pendingParent.complete(_group);
      await oldCheck;
      await Future<void>.delayed(Duration.zero);

      expect(sheet.isBatchValid.value, isTrue);
      expect(sheet.isValidatingBatch.value, isFalse);
      expect(sheet.batchError.value, isEmpty);
      expect(sheet.olderBatches, isEmpty);
    });

    test('the same batch and warehouse are not checked twice', () async {
      final sheet = sheetWith('OLD');
      await sheet.recheckBatchAge();
      final callsAfterFirst = source.calls.length;
      await sheet.recheckBatchAge();
      expect(source.calls.length, callsAfterFirst);
    });

    test('quantities already on this document free the newer batch', () async {
      final sheet = sheetWith('NEW')
        ..own = const [
          BatchDraftLine(batchNo: 'OLD', warehouse: _dxb1, qty: 12),
        ];
      await sheet.recheckBatchAge();
      expect(sheet.isBatchValid.value, isTrue);
    });

    test('resetting the batch clears the refusal', () async {
      final sheet = sheetWith('NEW');
      await sheet.recheckBatchAge();
      expect(sheet.olderBatches, isNotEmpty);

      sheet.resetBatch();
      expect(sheet.olderBatches, isEmpty);
      expect(sheet.batchError.value, isEmpty);
    });
  });
}
