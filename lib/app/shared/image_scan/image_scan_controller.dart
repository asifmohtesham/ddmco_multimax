// lib/app/shared/image_scan/image_scan_controller.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart' hide BarcodeType;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/shared/image_scan/barcode_router.dart';
import 'package:multimax/app/shared/image_scan/image_scan_result.dart';

enum ImageScanState {
  idle,
  analyzing,
  noBarcode,
  barcodeFound,
  looking,
  found,
  notFound,
  unresolvable,
  error,
}

class ImageScanController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  final imageNaturalSize = Rx<Size>(Size.zero);
  final barcodes = <Barcode>[].obs;
  final selectedBarcodeIndex = RxnInt();
  final scanState = ImageScanState.idle.obs;
  final errorMessage = ''.obs;

  final foundItemCode = RxnString();
  final foundItemName = RxnString();
  final foundItemGroup = RxnString();
  final foundItemHasImage = false.obs;
  final foundBatchNo = RxnString();
  final isEnriching = false.obs;

  /// Reads [path], decodes its dimensions, then scans for barcodes.
  /// If exactly one barcode is found it is auto-selected and looked up.
  Future<void> analyzeImage(String path, MobileScannerController scanner) async {
    barcodes.clear();
    selectedBarcodeIndex.value = null;
    scanState.value = ImageScanState.analyzing;

    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      imageNaturalSize.value =
          Size(frame.image.width.toDouble(), frame.image.height.toDouble());

      final capture = await scanner.analyzeImage(path);
      if (capture == null || capture.barcodes.isEmpty) {
        scanState.value = ImageScanState.noBarcode;
        return;
      }

      barcodes.value = capture.barcodes;
      scanState.value = ImageScanState.barcodeFound;

      if (barcodes.length == 1) await selectBarcode(0);
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageScanController] analyzeImage: $e');
      errorMessage.value = 'Could not read image';
      scanState.value = ImageScanState.error;
    }
  }

  /// Called when the user taps a barcode in the highlight overlay or the
  /// multi-barcode picker sheet.
  Future<void> selectBarcode(int index) async {
    selectedBarcodeIndex.value = index;
    await _route(barcodes[index].rawValue ?? '');
  }

  /// Called when the user submits the manual item code text field.
  Future<void> lookupManual(String itemCode) async {
    await _lookupItem(itemCode.trim(), batchNo: null);
  }

  /// Re-runs the lookup for the currently selected barcode — used by the retry
  /// button shown on network errors.
  Future<void> retryLookup() async {
    final idx = selectedBarcodeIndex.value;
    if (idx != null && idx < barcodes.length) {
      await _route(barcodes[idx].rawValue ?? '');
    }
  }

  Future<void> _route(String raw) async {
    switch (BarcodeRouter.classify(raw)) {
      case BarcodeType.ean8:
        await _lookupItem(BarcodeRouter.ean8ToItemCode(raw), batchNo: null);
      case BarcodeType.fullBatchNo:
        await _lookupBatch(raw);
      case BarcodeType.batchIdOnly:
        errorMessage.value =
            'This is a Batch ID — scan the full barcode or enter an item code manually.';
        scanState.value = ImageScanState.unresolvable;
      case BarcodeType.unknown:
        errorMessage.value = 'Unrecognised barcode format.';
        scanState.value = ImageScanState.unresolvable;
    }
  }

  Future<void> _lookupItem(String itemCode, {required String? batchNo}) async {
    scanState.value = ImageScanState.looking;
    try {
      final response = await _api.getDocument('Item', itemCode);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'] as Map<String, dynamic>;
        foundItemCode.value = itemCode;
        foundItemName.value = data['item_name'] as String?;
        foundItemGroup.value = data['item_group'] as String?;
        final img = data['image'];
        foundItemHasImage.value = img != null && (img as String).isNotEmpty;
        foundBatchNo.value = batchNo;
        scanState.value = ImageScanState.found;
      } else {
        scanState.value = ImageScanState.notFound;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageScanController] _lookupItem: $e');
      errorMessage.value = e.toString();
      scanState.value = ImageScanState.error;
    }
  }

  Future<void> _lookupBatch(String batchNo) async {
    scanState.value = ImageScanState.looking;
    try {
      final response = await _api.getDocument('Batch', batchNo);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'] as Map<String, dynamic>;
        final itemCode = data['item'] as String?;
        if (itemCode == null || itemCode.isEmpty) {
          scanState.value = ImageScanState.notFound;
          return;
        }
        await _lookupItem(itemCode, batchNo: batchNo);
      } else {
        scanState.value = ImageScanState.notFound;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageScanController] _lookupBatch: $e');
      errorMessage.value = e.toString();
      scanState.value = ImageScanState.error;
    }
  }

  /// Uploads [filePath] as the Item image and PATCHes the `image` field.
  /// Returns [ImageScanResult] on success, or `null` on any failure.
  Future<ImageScanResult?> enrichAndComplete(String filePath) async {
    final itemCode = foundItemCode.value;
    if (itemCode == null) return null;

    isEnriching.value = true;
    try {
      final fileUrl = await _api.uploadFile(
        filePath: filePath,
        doctype: 'Item',
        docname: itemCode,
        fieldname: 'image',
      );
      await _api.updateDocument('Item', itemCode, {'image': fileUrl});
      return ImageScanResult(itemCode: itemCode, batchNo: foundBatchNo.value);
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageScanController] enrichAndComplete: $e');
      return null;
    } finally {
      isEnriching.value = false;
    }
  }

  /// Builds the result without enrichment. Call when the user taps "Open".
  ImageScanResult buildResult() => ImageScanResult(
        itemCode: foundItemCode.value!,
        batchNo: foundBatchNo.value,
      );
}
