import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/data/services/scan_constants.dart';

/// Resolves raw barcode strings into typed [ScanResult] values.
///
/// Detection pipeline (in priority order):
///   1. Rack        — hyphenated, non-SHIPMENT codes with ≥3 segments
///   2. Batch       — SHIPMENT-* or plain alphanumeric when [contextItemCode] set
///   3. EAN-8 Item  — strict checksum match → ERPNext Item lookup
///   4. Variant-Of  — ERPNext variant_of filter fallback
///   5. Error       — nothing matched
class ScanService extends GetxService {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // ── Public API ────────────────────────────────────────────────────────────

  Future<ScanResult> processScan(
    String barcode, {
    String? contextItemCode,
  }) async {
    if (barcode.isEmpty) {
      return ScanResult.error(barcode, 'Empty barcode');
    }

    final cleanCode = barcode.trim();

    final rackResult = _detectRack(cleanCode);
    if (rackResult != null) return rackResult;

    final batchResult = _detectBatch(cleanCode, contextItemCode);
    if (batchResult != null) return batchResult;

    final itemResult = await _resolveEan8Item(cleanCode);
    if (itemResult != null) return itemResult;

    return await _resolveVariantOf(cleanCode);
  }

  // ── Step 1: Rack detection ────────────────────────────────────────────────

  ScanResult? _detectRack(String code) {
    final isHyphenated = code.contains('-');
    final hasEnoughSegments = code.split('-').length >= 3;
    final isNotShipment = !code.startsWith(ScanConstants.shipmentPrefix);

    if (isHyphenated && hasEnoughSegments && isNotShipment) {
      return ScanResult.rack(code);
    }
    return null;
  }

  // ── Step 2: Batch context detection ───────────────────────────────────────

  ScanResult? _detectBatch(String code, String? contextItemCode) {
    if (contextItemCode == null) return null;

    final suffix = _extractShipmentSuffix(code);
    if (suffix == null || suffix.isEmpty) return null;

    return ScanResult.batch(
      rawCode: code,
      itemCode: contextItemCode,
      batchNo: '$contextItemCode-$suffix',
    );
  }

  /// Extracts the batch suffix component from a scanned code.
  ///
  /// Handles three patterns:
  ///   - `SHIPMENT-24-<suffix>-…`  → returns `<suffix>`
  ///   - `SHIPMENT-<suffix>-…`     → returns `<suffix>`
  ///   - plain alphanumeric        → returns the code itself
  String? _extractShipmentSuffix(String code) {
    // More-specific prefix checked first to avoid accidental substring match.
    for (final prefix in [
      ScanConstants.shipmentPrefix24,
      ScanConstants.shipmentPrefix,
    ]) {
      if (code.startsWith(prefix)) {
        return code.substring(prefix.length).split('-').first;
      }
    }

    if (!code.contains('-') &&
        ScanConstants.alphanumericSuffix.hasMatch(code)) {
      return code;
    }

    return null;
  }

  // ── Step 3: EAN-8 item resolution ─────────────────────────────────────────

  Future<ScanResult?> _resolveEan8Item(String code) async {
    final ean8 = _parseEan8(code);
    if (ean8 == null) return null;

    try {
      final response = await _apiProvider.getDocument(
        ScanConstants.doctypeItem,
        ean8.itemCode,
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final item = Item.fromJson(response.data['data']);
        return ScanResult.item(
          rawCode: code,
          itemData: item,
          batchNo: ean8.batchNo,
        );
      }
    } on DioException catch (e) {
      // 404 means no item found → fall through to variant_of check.
      if (e.response?.statusCode != 404) {
        return ScanResult.error(code, 'Network Error: ${e.message}');
      }
    } catch (e) {
      return ScanResult.error(code, 'Scan Error: $e');
    }

    return null; // 404 → continue pipeline
  }

  /// Returns a `({itemCode, batchNo?})` record if [code] passes EAN-8
  /// validation, otherwise `null`.
  _Ean8ParseResult? _parseEan8(String code) {
    if (code.contains('-')) {
      // Hyphenated: `{EAN8}-{BatchID}`
      final prefix = code.split('-').first;
      if (_isValidEan8(prefix)) {
        return _Ean8ParseResult(
          itemCode: prefix.substring(0, 7),
          batchNo: code,
        );
      }
    } else {
      if (_isValidEan8(code)) {
        return _Ean8ParseResult(
          itemCode: code.substring(0, 7),
          batchNo: null,
        );
      }
    }
    return null;
  }

  // ── Step 4: Variant-of fallback ───────────────────────────────────────────

  Future<ScanResult> _resolveVariantOf(String code) async {
    try {
      final response = await _apiProvider.getDocumentList(
        ScanConstants.doctypeItem,
        filters: {
          ScanConstants.fieldVariantOf: ['like', '%$code%'],
        },
        limit: 1,
        fields: [ScanConstants.fieldName],
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List data = response.data['data'];
        if (data.isNotEmpty) {
          return ScanResult.variantOf(code);
        }
      }
    } on DioException catch (e) {
      return ScanResult.error(
        code,
        'Network Error resolving variant: ${e.message}',
      );
    } catch (e) {
      return ScanResult.error(code, 'Variant lookup error: $e');
    }

    return ScanResult.error(code, 'Item not found or invalid barcode');
  }

  // ── EAN-8 checksum validation ─────────────────────────────────────────────

  bool _isValidEan8(String code) {
    if (code.length != 8) return false;
    if (!ScanConstants.digitsOnly.hasMatch(code)) return false;

    // EAN-8 weights: 3 1 3 1 3 1 3 (check)
    int sum = 0;
    for (int i = 0; i < 7; i++) {
      final digit = int.parse(code[i]);
      sum += (i.isEven) ? digit * 3 : digit;
    }

    final checksum = (10 - (sum % 10)) % 10;
    return checksum == int.parse(code[7]);
  }
}

// ── Private value type ────────────────────────────────────────────────────────

/// Carries the two values extracted from a validated EAN-8 scan.
class _Ean8ParseResult {
  const _Ean8ParseResult({required this.itemCode, this.batchNo});
  final String itemCode;
  final String? batchNo;
}
