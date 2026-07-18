import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/scan_constants.dart';

// Pure coverage for the Dashboard POS-Upload scan classifier. The recognition
// logic (ScanConstants.isPosUploadDocName) is what lets a scanned document
// label like `ML-2026-02011` be routed to the DN/Packing-Slip chooser instead
// of being misread as a rack asset-code by ScanService. The critical property
// is collision-avoidance: it must match real POS Upload names and reject every
// other hyphenated code the scanner produces.

void main() {
  group('isPosUploadDocName — matches real POS Upload document names', () {
    const valid = [
      'ML-2026-02011', // the scanned label in question (Delivery Note family)
      'KA-2025-61960', // Delivery Note family
      'MX-2026-00001', // Stock Entry family
      'KX-2024-99999', // Stock Entry family
      'ML-2026-1234', // 4-digit serial boundary
      'ML-2026-123456', // 6-digit serial boundary
    ];
    for (final code in valid) {
      test('accepts "$code"', () {
        expect(ScanConstants.isPosUploadDocName(code), isTrue);
      });
    }

    test('is case-insensitive', () {
      expect(ScanConstants.isPosUploadDocName('ml-2026-02011'), isTrue);
    });

    test('tolerates surrounding whitespace', () {
      expect(ScanConstants.isPosUploadDocName('  ML-2026-02011  '), isTrue);
    });
  });

  group('isPosUploadDocName — rejects every other hyphenated code', () {
    const invalid = [
      'KA-WH-DXB1-101A', // rack asset-code (non-numeric 2nd segment)
      'KA-WH-DXB3-BLOCK 1', // rack asset-code with spaces
      '84012345-A1B2C3', // batch id ({EAN8}-{suffix})
      'MAT-DN-2026-00042', // ERPNext Delivery Note name (3-letter prefix)
      'MAT-STE-2026-00123', // ERPNext Stock Entry name
      '12345678', // bare EAN-8 item barcode
      'SHIPMENT-24-ABC', // legacy shipment prefix
      'AB-2026-02011', // unknown prefix
      'ML-2026-123', // serial too short (< 4 digits)
      'ML-2026-1234567', // serial too long (> 6 digits)
      'ML-26-02011', // year not 4 digits
      'ML-YEAR-02011', // non-numeric year
      'ML-2026', // missing serial segment
      'KA-1', // simplified/legacy name, not a scannable label
      '', // empty
    ];
    for (final code in invalid) {
      test('rejects "$code"', () {
        expect(ScanConstants.isPosUploadDocName(code), isFalse);
      });
    }
  });

  group('isStockEntryFamilyUpload — MX/KX are Stock Entry, ML/KA are not', () {
    test('MX prefix is Stock Entry family', () {
      expect(ScanConstants.isStockEntryFamilyUpload('MX-2026-00001'), isTrue);
    });
    test('KX prefix is Stock Entry family', () {
      expect(ScanConstants.isStockEntryFamilyUpload('KX-2024-99999'), isTrue);
    });
    test('ML prefix is NOT Stock Entry family (Delivery Note)', () {
      expect(ScanConstants.isStockEntryFamilyUpload('ML-2026-02011'), isFalse);
    });
    test('KA prefix is NOT Stock Entry family (Delivery Note)', () {
      expect(ScanConstants.isStockEntryFamilyUpload('KA-2025-61960'), isFalse);
    });
    test('is case-insensitive and whitespace-tolerant', () {
      expect(ScanConstants.isStockEntryFamilyUpload('  mx-2026-00001 '), isTrue);
    });
  });
}
