// Unit Test #1 — MR Type → SE Type Mapping
//
// Requirement:
//   When navigating via "From Material Request", the Stock Entry Type passed
//   as a route argument MUST match the Material Request type. This is enforced
//   by StockEntryController.mapMrTypeToSeType().
//
// Run: flutter test test/unit/stock_entry/mr_type_mapping_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:multimax/app/modules/stock_entry/stock_entry_controller.dart';

// ---------------------------------------------------------------------------
// Minimal stub — mapMrTypeToSeType is pure (no deps, no network). We call it
// directly on an instance obtained without onInit() running, by bypassing
// Get's DI and constructing the class only for its logic under test.
// ---------------------------------------------------------------------------
class _TestableController extends StockEntryController {
  // Prevent onInit() from firing provider calls during the test.
  @override
  void onInit() {}
}

void main() {
  late _TestableController controller;

  setUp(() {
    Get.testMode = true;
    controller = _TestableController();
  });

  tearDown(() => Get.reset());

  // -------------------------------------------------------------------------
  // Happy-path mappings
  // -------------------------------------------------------------------------
  group('mapMrTypeToSeType — known MR types produce correct SE types', () {
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
  });

  // -------------------------------------------------------------------------
  // Boundary / edge cases
  // -------------------------------------------------------------------------
  group('mapMrTypeToSeType — boundary and edge cases', () {
    test('Unknown MR type passes through unchanged (default branch)', () {
      // Any future Frappe MR type not yet handled should not silently map to
      // a wrong SE type — it should pass through so the server validates it.
      const unknownType = 'Some Future MR Type';
      expect(
        controller.mapMrTypeToSeType(unknownType),
        equals(unknownType),
        reason: 'Unknown types must pass through; never silently remap.',
      );
    });

    test('Empty string passes through unchanged', () {
      expect(
        controller.mapMrTypeToSeType(''),
        equals(''),
        reason: 'Empty string must not be remapped to a hardcoded fallback.',
      );
    });

    test('Mapping is case-sensitive — lowercase does not match', () {
      // Frappe always returns properly-cased values; this test confirms the
      // mapping is not accidentally case-insensitive.
      expect(
        controller.mapMrTypeToSeType('material transfer'),
        isNot(equals('Material Transfer')),
        reason: 'Lowercase input must not match the title-case switch branch.',
      );
    });

    test('Manufacture mapping is exact — partial string does not match', () {
      expect(
        controller.mapMrTypeToSeType('Manufactur'),  // truncated
        isNot(equals('Material Transfer for Manufacture')),
        reason: 'Only exact string match should trigger the Manufacture branch.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Contract: SE type returned must never be empty for known MR types
  // -------------------------------------------------------------------------
  group('mapMrTypeToSeType — contract: result is always non-empty for known inputs', () {
    const knownMrTypes = [
      'Material Transfer',
      'Material Issue',
      'Manufacture',
      'Material Receipt',
    ];

    for (final mrType in knownMrTypes) {
      test('Result is non-empty for MR type "$mrType"', () {
        expect(
          controller.mapMrTypeToSeType(mrType),
          isNotEmpty,
          reason: 'SE type must never be blank when a known MR type is provided.',
        );
      });
    }
  });

  // -------------------------------------------------------------------------
  // Contract: mapping must be idempotent
  // -------------------------------------------------------------------------
  group('mapMrTypeToSeType — idempotency', () {
    test('Mapping the result of a mapping produces the same value', () {
      // Applying the map twice should not change the result.
      // e.g. mapMrTypeToSeType('Material Issue') == 'Material Issue'
      //      mapMrTypeToSeType('Material Issue') called again == 'Material Issue'
      const knownTypes = [
        'Material Transfer',
        'Material Issue',
        'Material Receipt',
      ];
      for (final t in knownTypes) {
        final firstPass  = controller.mapMrTypeToSeType(t);
        final secondPass = controller.mapMrTypeToSeType(firstPass);
        expect(
          secondPass,
          equals(firstPass),
          reason: 'mapMrTypeToSeType must be idempotent for "$t".',
        );
      }
    });

    test('Manufacture → Material Transfer for Manufacture is NOT idempotent '
        '(expected — the output is a different type)', () {
      // This documents the intentional asymmetry: MR type "Manufacture" maps
      // to the SE type "Material Transfer for Manufacture", which has no
      // further mapping. Calling map on the output passes through unchanged.
      const result = 'Material Transfer for Manufacture';
      expect(
        controller.mapMrTypeToSeType(result),
        equals(result),
        reason: 'The SE type "Material Transfer for Manufacture" should '
            'pass through the default branch unchanged.',
      );
    });
  });
}
