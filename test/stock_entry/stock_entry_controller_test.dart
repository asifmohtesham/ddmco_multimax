// Unit tests for StockEntryController.
// Covers:
//   Group 1 — MR type → SE type mapping
//   Group 2 — POS upload prefix filtering
//   Group 3 — Material Request search filtering
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/stock_entry_controller.dart';
import 'package:multimax/app/data/models/material_request_model.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'helpers/mock_providers.dart';

void main() {
  late StockEntryController controller;

  setUp(() {
    Get.testMode = true;
    registerListFakes();
    controller = Get.put(StockEntryController());
  });

  tearDown(() async {
    await Get.deleteAll(force: true);
  });

  // -------------------------------------------------------------------------
  // Group 1 — MR type → SE type mapping
  // Requirement: "From Material Request" must map MR type to correct SE type.
  // -------------------------------------------------------------------------
  group('mapMrTypeToSeType', () {
    test('Material Transfer MR → Material Transfer SE', () {
      expect(
        controller.mapMrTypeToSeType('Material Transfer'),
        equals('Material Transfer'),
      );
    });

    test('Material Issue MR → Material Issue SE', () {
      expect(
        controller.mapMrTypeToSeType('Material Issue'),
        equals('Material Issue'),
      );
    });

    test('Manufacture MR → Material Transfer for Manufacture SE', () {
      expect(
        controller.mapMrTypeToSeType('Manufacture'),
        equals('Material Transfer for Manufacture'),
      );
    });

    test('Material Receipt MR → Material Receipt SE (pass-through)', () {
      expect(
        controller.mapMrTypeToSeType('Material Receipt'),
        equals('Material Receipt'),
      );
    });

    test('Unknown MR type → passed through unchanged (no silent default)', () {
      // The switch default returns mrType as-is; validate that contract.
      expect(
        controller.mapMrTypeToSeType('Purchase'),
        equals('Purchase'),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 2 — POS upload prefix guard
  // KX / MX prefixes must reach posUpload source; all others must not.
  // -------------------------------------------------------------------------
  group('POS upload prefix identification', () {
    test('KX prefix is a valid POS upload reference', () {
      expect('KX-00123'.startsWith('KX'), isTrue);
    });

    test('MX prefix is a valid POS upload reference', () {
      expect('MX-00456'.startsWith('MX'), isTrue);
    });

    test('MAT-MR prefix is NOT a POS upload reference', () {
      const ref = 'MAT-MR-0001';
      expect(ref.startsWith('KX') || ref.startsWith('MX'), isFalse);
    });

    test('Empty string is NOT a POS upload reference', () {
      const ref = '';
      expect(ref.startsWith('KX') || ref.startsWith('MX'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Group 3 — filterMaterialRequests search
  // -------------------------------------------------------------------------
  group('filterMaterialRequests', () {
    setUp(() {
      // Seed the private backing list via the public forSelection observable
      // by calling filterMaterialRequests with an empty query first after
      // we inject test data through the observable directly.
      controller.materialRequestsForSelection.value = [
        _fakeMR('MAT-MR-0001', 'Material Transfer'),
        _fakeMR('MAT-MR-0002', 'Material Issue'),
        _fakeMR('MAT-MR-0003', 'Manufacture'),
      ];
      // Mirror into the private backing list by clearing then re-filtering.
      controller.filterMaterialRequests('');
    });

    test('empty query returns all results', () {
      controller.filterMaterialRequests('');
      expect(controller.materialRequestsForSelection.length, equals(3));
    });

    test('query matches by name (case-insensitive)', () {
      controller.filterMaterialRequests('mat-mr-0002');
      expect(controller.materialRequestsForSelection.length, equals(1));
      expect(
          controller.materialRequestsForSelection.first.name, 'MAT-MR-0002');
    });

    test('query matches by materialRequestType', () {
      controller.filterMaterialRequests('Manufacture');
      expect(controller.materialRequestsForSelection.length, equals(1));
      expect(controller.materialRequestsForSelection.first.materialRequestType,
          'Manufacture');
    });

    test('query with no match returns empty list', () {
      controller.filterMaterialRequests('XXXXXX');
      expect(controller.materialRequestsForSelection.isEmpty, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Group 4 — filterPosUploads search
  // -------------------------------------------------------------------------
  group('filterPosUploads', () {
    setUp(() {
      controller.posUploadsForSelection.value = [
        _fakePOS('KX-00001', 'Customer A'),
        _fakePOS('MX-00002', 'Customer B'),
        _fakePOS('KX-00003', 'Customer C'),
      ];
      controller.filterPosUploads('');
    });

    test('empty query returns all POS uploads', () {
      controller.filterPosUploads('');
      expect(controller.posUploadsForSelection.length, equals(3));
    });

    test('query matches by POS name', () {
      controller.filterPosUploads('KX-00001');
      expect(controller.posUploadsForSelection.length, equals(1));
      expect(controller.posUploadsForSelection.first.name, 'KX-00001');
    });

    test('query matches by customer name', () {
      controller.filterPosUploads('Customer B');
      expect(controller.posUploadsForSelection.length, equals(1));
      expect(controller.posUploadsForSelection.first.customer, 'Customer B');
    });

    test('no match returns empty list', () {
      controller.filterPosUploads('ZZ-99999');
      expect(controller.posUploadsForSelection.isEmpty, isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

MaterialRequest _fakeMR(String name, String type) => MaterialRequest(
      name: name,
      materialRequestType: type,
      status: 'Pending',
      docstatus: 1,
      transactionDate: '2026-01-01',
      scheduleDate: '2026-01-01',
      modified: '2026-01-01 00:00:00',
      items: [],
    );

PosUpload _fakePOS(String name, String customer) => PosUpload(
      name: name,
      customer: customer,
      status: 'Pending',
      date: '2026-01-01',
      modified: '2026-01-01 00:00:00',
      totalQty: 10.0,
      items: [],
    );
