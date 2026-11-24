import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/data/services/scan_constants.dart';
import 'package:multimax/app/shared/barcode/ean8.dart';

/// Resolves raw barcode strings into typed [ScanResult] values.
///
/// Detection pipeline (in priority order):
///   1. Rack        — hyphenated, non-SHIPMENT codes with ≥3 segments
///   2. Batch       — SHIPMENT-* or plain alphanumeric when [contextItemCode] set
///   3. EAN-8 Item  — strict checksum match → ERPNext Item lookup
///   4. Variant-Of  — ERPNext variant_of filter fallback
///   5. Registered barcode or batch — exact lookup through ERPNext
class ScanService extends GetxService {
  ScanService({ApiProvider? apiProvider})
    : _apiProvider = apiProvider ?? Get.find<ApiProvider>();

  final ApiProvider _apiProvider;

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

    try {
      final ean8 = _parseEan8(cleanCode);
      final itemResult = await _resolveEan8Item(cleanCode, ean8);
      if (itemResult != null) return itemResult;

      final variantResult = await _resolveVariantOf(cleanCode);
      if (variantResult.failureOutcome != ScanOutcome.notFound) {
        return variantResult;
      }

      return await _resolveRegisteredBarcode(cleanCode, ean8) ?? variantResult;
    } on DioException catch (error) {
      return ScanResult.error(cleanCode, 'Network Error: ${error.message}');
    } catch (error) {
      return ScanResult.error(cleanCode, 'Scan Error: $error');
    }
  }

  /// Resolves the Item for an image or camera barcode. An unmatched code
  /// returns null. Lookup failures propagate to the caller for retry.
  Future<Item?> resolveItemBarcode(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;

    final ean8 = _parseEan8(code);
    final result =
        await _resolveEan8Item(code, ean8) ??
        await _resolveRegisteredBarcode(code, ean8);
    return result?.itemData;
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

  Future<ScanResult?> _resolveEan8Item(
    String code,
    _Ean8ParseResult? ean8,
  ) async {
    if (ean8 == null) return null;
    final item = await _getItem(ean8.itemCode);
    if (item == null) return null;
    return ScanResult.item(
      rawCode: code,
      itemData: item,
      batchNo: ean8.batchNo,
    );
  }

  Future<Item?> _getItem(String itemCode) async {
    final data = await _getDocumentData(ScanConstants.doctypeItem, itemCode);
    return data == null ? null : Item.fromJson(data);
  }

  Future<Map<String, dynamic>?> _getDocumentData(
    String doctype,
    String name,
  ) async {
    try {
      final response = await _apiProvider.getDocument(
        doctype,
        Uri.encodeComponent(name),
      );
      final data = response.data;
      if (response.statusCode == 200 &&
          data is Map &&
          data['data'] is Map<String, dynamic>) {
        return data['data'] as Map<String, dynamic>;
      }
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
    }
    return null;
  }

  _Ean8ParseResult? _parseEan8(String code) {
    final separator = code.indexOf('-');
    final barcode = separator < 0 ? code : code.substring(0, separator);
    if (!Ean8.isValid(barcode)) return null;
    return _Ean8ParseResult(
      barcode: barcode,
      batchNo: separator < 0 ? null : code,
    );
  }

  Future<ScanResult?> _resolveRegisteredBarcode(
    String code,
    _Ean8ParseResult? ean8,
  ) async {
    var link = await _lookupStockBarcode(code);
    if (link == null && ean8 != null && ean8.batchNo != null) {
      link = await _lookupStockBarcode(ean8.barcode);
    }
    if (link == null) return null;

    final item = await _getItem(link.itemCode);
    if (item == null) return null;
    return ScanResult.item(
      rawCode: code,
      itemData: item,
      batchNo: link.batchNo ?? ean8?.batchNo,
    );
  }

  /// Desk's barcode lookup resolves Item Barcode rows and Batch documents
  /// without requiring direct access to the Item Barcode child table.
  Future<({String itemCode, String? batchNo})?> _lookupStockBarcode(
    String code,
  ) async {
    final Response response;
    try {
      response = await _apiProvider.callMethod(
        'erpnext.stock.utils.scan_barcode',
        params: {'search_value': code},
      );
    } on DioException catch (error) {
      final failure = error.response;
      final data = failure?.data;
      if (failure?.statusCode == 417 &&
          data is Map &&
          data['exc_type'] == 'ValidationError') {
        // Desk requires a serial for stock transactions on serialized Items.
        // Looking up the Item can use the Batch document, like gallery scan.
        final batch = await _getDocumentData('Batch', code);
        final itemCode = batch?['item'];
        if (itemCode is String && itemCode.isNotEmpty) {
          return (itemCode: itemCode, batchNo: code);
        }
      }
      rethrow;
    }
    final data = response.data;
    final message = data is Map ? data['message'] : null;
    if (message is! Map) return null;

    final itemCode = message['item_code'];
    if (itemCode is! String || itemCode.isEmpty) return null;
    return (itemCode: itemCode, batchNo: message['batch_no'] as String?);
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

    return ScanResult.error(
      code,
      'Item not found or invalid barcode',
      outcome: ScanOutcome.notFound,
    );
  }
}

class _Ean8ParseResult {
  const _Ean8ParseResult({required this.barcode, this.batchNo});
  final String barcode;
  final String? batchNo;

  String get itemCode => barcode.substring(0, 7);
}
