// app/modules/batch/form/batch_form_controller.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/batch_model.dart';
import 'package:multimax/app/data/providers/batch_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

class BatchFormController extends GetxController {
  final BatchProvider _provider = Get.find<BatchProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var isSaving = false.obs;
  var isExporting = false.obs;
  var isDirty = false.obs; // Tracks form changes
  String _originalJson = ''; // Stores initial state

  var batch = Rx<Batch?>(null);

  // Form Controllers
  final itemController = TextEditingController();
  final descriptionController = TextEditingController();
  final mfgDateController = TextEditingController();
  final expDateController = TextEditingController();
  final customPackagingQtyController = TextEditingController();
  final customPurchaseOrderController = TextEditingController();

  // New State
  var generatedBatchId = ''.obs;
  var itemBarcode = ''.obs;

  // Selection Lists
  var isFetchingItems = false.obs;
  var itemList = <Map<String, dynamic>>[].obs;

  var isFetchingPOs = false.obs;
  var poList = <Map<String, dynamic>>[].obs;

  bool get isEditMode => mode == 'edit';

  @override
  void onInit() {
    super.onInit();

    // Attach Listeners for Dirty Check
    itemController.addListener(_checkForChanges);
    descriptionController.addListener(_checkForChanges);
    mfgDateController.addListener(_checkForChanges);
    expDateController.addListener(_checkForChanges);
    customPackagingQtyController.addListener(_checkForChanges);
    customPurchaseOrderController.addListener(_checkForChanges);

    if (isEditMode) {
      fetchBatch();
    } else {
      _initNewBatch();
    }
  }

  @override
  void onClose() {
    itemController.dispose();
    descriptionController.dispose();
    mfgDateController.dispose();
    expDateController.dispose();
    customPackagingQtyController.dispose();
    customPurchaseOrderController.dispose();
    super.onClose();
  }

  void _initNewBatch() {
    batch.value = Batch(
      name: 'New Batch',
      item: '',
      creation: '',
      modified: '',
    );

    // Default Values
    mfgDateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    customPackagingQtyController.text = '12';

    // New documents are dirty by default to allow saving immediately
    isDirty.value = true;
    _originalJson = '';

    isLoading.value = false;
  }

  Future<void> fetchBatch() async {
    isLoading.value = true;
    try {
      final response = await _provider.getBatch(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final b = Batch.fromJson(response.data['data']);
        batch.value = b;

        // Populate Fields
        itemController.text = b.item;
        descriptionController.text = b.description ?? '';
        mfgDateController.text = b.manufacturingDate ?? '';
        expDateController.text = b.expiryDate ?? '';
        customPackagingQtyController.text = b.customPackagingQty.toString();
        customPurchaseOrderController.text = b.customPurchaseOrder ?? '';
        generatedBatchId.value = b.name;

        // Fetch item details to show barcode if editing
        if(b.item.isNotEmpty) {
          _fetchItemDetails(b.item, generateId: false);
        }

        // Save original state for dirty check
        _originalJson = jsonEncode(_getCurrentFormData());
        isDirty.value = false;
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load batch: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // --- Change Detection Logic ---

  void _checkForChanges() {
    if (mode == 'new') {
      isDirty.value = true;
      return;
    }
    // Compare current form data with original JSON
    final currentJson = jsonEncode(_getCurrentFormData());
    isDirty.value = currentJson != _originalJson;
  }

  Map<String, dynamic> _getCurrentFormData() {
    return {
      'item': itemController.text,
      'description': descriptionController.text,
      'manufacturing_date': mfgDateController.text.isEmpty ? null : mfgDateController.text,
      'expiry_date': expDateController.text.isEmpty ? null : expDateController.text,
      'custom_packaging_qty': double.tryParse(customPackagingQtyController.text) ?? 0.0,
      'purchase_order': customPurchaseOrderController.text.isEmpty ? null : customPurchaseOrderController.text,
    };
  }

  // --- Search & Selection Logic ---

  Future<void> searchItems(String query) async {
    isFetchingItems.value = true;
    try {
      final response = await _provider.searchItems(query);
      if (response.statusCode == 200 && response.data['data'] != null) {
        itemList.assignAll(List<Map<String, dynamic>>.from(response.data['data']));
      }
    } catch (e) {
      print(e);
    } finally {
      isFetchingItems.value = false;
    }
  }

  Future<void> searchPurchaseOrders(String query) async {
    isFetchingPOs.value = true;
    try {
      final response = await _provider.searchPurchaseOrders(query);
      if (response.statusCode == 200 && response.data['data'] != null) {
        poList.assignAll(List<Map<String, dynamic>>.from(response.data['data']));
      }
    } catch (e) {
      print(e);
    } finally {
      isFetchingPOs.value = false;
    }
  }

  void selectItem(Map<String, dynamic> itemData) {
    itemController.text = itemData['item_code'];
    Get.back(); // Close sheet
    _fetchItemDetails(itemData['item_code'], generateId: true);
  }

  void selectPurchaseOrder(String poName) {
    customPurchaseOrderController.text = poName;
    Get.back();
  }

  Future<void> _fetchItemDetails(String itemCode, {bool generateId = false}) async {
    try {
      final response = await _provider.getItemDetails(itemCode);
      if(response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'];

        // Extract Barcode
        String barcode = '';
        if (data['barcodes'] != null && (data['barcodes'] as List).isNotEmpty) {
          barcode = data['barcodes'][0]['barcode'] ?? '';
        } else if (data['barcode'] != null) {
          barcode = data['barcode'];
        } else {
          barcode = itemCode;
        }

        itemBarcode.value = barcode;

        if (generateId && !isEditMode) {
          _generateBatchId(barcode);
        }
      }
    } catch (e) {
      print('Error fetching item details: $e');
    }
  }

  void _generateBatchId(String ean) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    final randomId = String.fromCharCodes(Iterable.generate(
        6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));

    generatedBatchId.value = '$ean-$randomId';
  }

  // --- Save Logic ---

  Future<void> saveBatch() async {
    if (!isDirty.value && isEditMode) return; // Prevent saving if no changes

    if (itemController.text.isEmpty) {
      GlobalSnackbar.warning(message: 'Item Code is required');
      return;
    }

    isSaving.value = true;
    final data = _getCurrentFormData();

    try {
      if (isEditMode) {
        final response = await _provider.updateBatch(name, data);
        if (response.statusCode == 200) {
          GlobalSnackbar.success(message: 'Batch updated successfully');
          fetchBatch();
        } else {
          throw Exception(response.data['exception'] ?? 'Unknown Error');
        }
      } else {
        data['batch_id'] = generatedBatchId.value;
        data['name'] = generatedBatchId.value;

        final response = await _provider.createBatch(data);
        if (response.statusCode == 200) {
          GlobalSnackbar.success(message: 'Batch created: ${generatedBatchId.value}');
          Get.back(result: true);
        } else {
          throw Exception(response.data['exception'] ?? 'Unknown Error');
        }
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> pickDate(TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: Get.context!,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  // --- QR Export Logic ---

  Future<void> exportQrAsPng() async {
    if (generatedBatchId.value.isEmpty) return;

    isExporting.value = true;
    try {
      final qrValidationResult = QrValidator.validate(
        data: generatedBatchId.value,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.L,
      );

      if (qrValidationResult.isValid) {
        final qrCode = qrValidationResult.qrCode!;
        final painter = QrPainter.withQr(
          qr: qrCode,
          color: const Color(0xFF000000),
          emptyColor: const Color(0xFFFFFFFF),
          gapless: true,
        );

        final pic = painter.toPicture(1024);
        final img = await pic.toImage(1024, 1024);
        final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
        final buffer = byteData!.buffer.asUint8List();

        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/${generatedBatchId.value}.png');
        await file.writeAsBytes(buffer);

        await Share.shareXFiles(
            [XFile(file.path)],
            text: 'Batch QR Code: ${generatedBatchId.value}'
        );
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to export PNG: $e');
    } finally {
      isExporting.value = false;
    }
  }

  Future<void> exportQrAsPdf() async {
    if (generatedBatchId.value.isEmpty) return;

    isExporting.value = true;
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: generatedBatchId.value,
                    width: 200,
                    height: 200,
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text(
                    generatedBatchId.value,
                    style: pw.TextStyle(
                      font: pw.Font.courier(),
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    itemController.text,
                    style: const pw.TextStyle(fontSize: 16),
                  ),
                ],
              ),
            );
          },
        ),
      );

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${generatedBatchId.value}.pdf');
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Batch Label: ${generatedBatchId.value}'
      );
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to export PDF: $e');
    } finally {
      isExporting.value = false;
    }
  }
}