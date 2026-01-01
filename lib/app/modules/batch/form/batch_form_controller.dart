import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/batch_model.dart';
import 'package:multimax/app/data/providers/batch_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

class BatchFormController extends GetxController {
  final BatchProvider _provider = Get.find<BatchProvider>();

  // Initialise with defaults, populated in onInit
  String name = '';
  String mode = 'new';

  var isLoading = true.obs;
  var isSaving = false.obs;
  var isExporting = false.obs;
  var isDirty = false.obs;
  String _originalJson = '';
  bool _isFetching = false; // Guard flag to prevent listener noise

  var batch = Rx<Batch?>(null);

  // Form Controllers
  final batchIdController = TextEditingController();
  final itemController = TextEditingController();
  final descriptionController = TextEditingController();
  final mfgDateController = TextEditingController();
  final expDateController = TextEditingController();
  final customPackagingQtyController = TextEditingController();
  final customPurchaseOrderController = TextEditingController();

  // Status State
  var isDisabled = false.obs;

  // New State
  var generatedBatchId = ''.obs;
  var itemBarcode = ''.obs;
  var itemVariantOf = ''.obs;

  // Selection Lists
  var isFetchingItems = false.obs;
  var itemList = <Map<String, dynamic>>[].obs;

  var isFetchingPOs = false.obs;
  var poList = <Map<String, dynamic>>[].obs;

  bool get isEditMode => mode == 'edit';

  // Store the random suffix to persist it across Item Code changes
  String? _currentRandomSuffix;

  // --- Status Logic ---
  // Returns a simple String. Colors are handled by StatusPill.
  String get batchStatus {
    // 1. Not Saved (Dirty)
    if (isDirty.value) {
      return 'Not Saved';
    }

    // 2. Disabled
    if (isDisabled.value) {
      return 'Disabled';
    }

    // 3. Expired
    if (expDateController.text.isNotEmpty) {
      final expiry = DateTime.tryParse(expDateController.text);
      if (expiry != null && expiry.isBefore(DateTime.now())) {
        return 'Expired';
      }
    }

    // 4. Active (Default)
    return 'Active';
  }

  @override
  void onInit() {
    super.onInit();
    _parseArguments();

    // Attach Listeners for Dirty Check
    itemController.addListener(_checkForChanges);
    descriptionController.addListener(_checkForChanges);
    mfgDateController.addListener(_checkForChanges);
    expDateController.addListener(_checkForChanges);
    customPackagingQtyController.addListener(_checkForChanges);
    customPurchaseOrderController.addListener(_checkForChanges);

    isDisabled.listen((_) => _checkForChanges());

    if (isEditMode) {
      fetchBatch();
    } else {
      _initNewBatch();
    }
  }

  void _parseArguments() {
    final args = Get.arguments;
    if (args != null) {
      if (args is Map) {
        name = args['name'] ?? '';
        mode = args['mode'] ?? 'new';
      } else if (args is String) {
        // Handle GlobalSearchDelegate argument (just the ID)
        name = args;
        mode = 'edit';
      }
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

  // --- PopScope Logic ---
  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false; // Reset dirty flag
        Get.back(); // Pop the screen (Navigation)
      },
    );
  }

  void _initNewBatch() {
    batch.value = Batch(
      name: 'New Batch',
      item: '',
      creation: '',
      modified: '',
    );

    mfgDateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    customPackagingQtyController.text = '12';
    isDisabled.value = false;
    itemBarcode.value = '';
    _currentRandomSuffix = null; // Reset suffix for new batch

    isDirty.value = true;
    _originalJson = '';

    isLoading.value = false;
  }

  Future<void> fetchBatch() async {
    isLoading.value = true;
    _isFetching = true; // Block dirty checks while programmatic updates happen
    try {
      final response = await _provider.getBatch(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final b = Batch.fromJson(response.data['data']);
        batch.value = b;

        // Populate Controllers
        batchIdController.text = b.name;
        itemController.text = b.item;
        descriptionController.text = b.description ?? '';
        mfgDateController.text = b.manufacturingDate ?? '';
        expDateController.text = b.expiryDate ?? '';
        customPackagingQtyController.text = b.customPackagingQty.toString();
        customPurchaseOrderController.text = b.customPurchaseOrder ?? '';
        isDisabled.value = b.disabled == 1;

        generatedBatchId.value = b.name;

        // Pre-fill from Batch document first
        itemBarcode.value = b.customItemBarcode ?? '';
        itemVariantOf.value = b.variantOf ?? '';

        if(b.item.isNotEmpty) {
          // Await this to ensure itemBarcode/Variant are synced from Item Master
          // BEFORE we snapshot the form state as "clean"
          await _fetchItemDetails(b.item, generateId: false);
        }

        // Snapshot original state and reset dirty flag
        _originalJson = jsonEncode(_getCurrentFormData());
        isDirty.value = false;
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load batch: $e');
    } finally {
      isLoading.value = false;
      _isFetching = false; // Re-enable dirty checks
    }
  }

  void _checkForChanges() {
    if (_isFetching) return; // Ignore changes during fetch

    if (mode == 'new') {
      isDirty.value = true;
      return;
    }
    final currentJson = jsonEncode(_getCurrentFormData());
    isDirty.value = currentJson != _originalJson;
  }

  Map<String, dynamic> _getCurrentFormData() {
    return {
      'name': batchIdController.text,
      'item': itemController.text,
      'custom_item_barcode': itemBarcode.value,
      'description': descriptionController.text,
      'manufacturing_date': mfgDateController.text.isEmpty ? null : mfgDateController.text,
      'expiry_date': expDateController.text.isEmpty ? null : expDateController.text,
      'custom_packaging_qty': double.tryParse(customPackagingQtyController.text) ?? 0.0,
      'custom_purchase_order': customPurchaseOrderController.text.isEmpty ? null : customPurchaseOrderController.text,
      'disabled': isDisabled.value ? 1 : 0,
    };
  }

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
    Get.back();
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
        String barcode = '';
        if (data['barcodes'] != null && (data['barcodes'] as List).isNotEmpty) {
          barcode = data['barcodes'][0]['barcode'] ?? '';
        } else if (data['barcode'] != null) {
          barcode = data['barcode'];
        } else {
          barcode = itemCode;
        }
        itemBarcode.value = barcode;
        itemVariantOf.value = data['variant_of'] ?? '';
        if (generateId && !isEditMode) {
          _generateBatchId(barcode);
        }
      }
    } catch (e) {
      print('Error fetching item details: $e');
    }
  }

  void _generateBatchId(String ean) {
    // Generate suffix only if it doesn't exist yet
    if (_currentRandomSuffix == null) {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final rnd = Random();
      _currentRandomSuffix = String.fromCharCodes(Iterable.generate(
          6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
    }

    // Format: {ean8}-{6-character alphanumeric}
    // This preserves the suffix while updating the EAN prefix
    generatedBatchId.value = '$ean-$_currentRandomSuffix';
    batchIdController.text = generatedBatchId.value;

    // Update the Batch Model name immediately so UI (AppBar) updates
    if (batch.value != null) {
      batch.value = Batch(
        name: generatedBatchId.value,
        item: batch.value!.item,
        description: batch.value!.description,
        manufacturingDate: batch.value!.manufacturingDate,
        expiryDate: batch.value!.expiryDate,
        customPackagingQty: batch.value!.customPackagingQty,
        customPurchaseOrder: batch.value!.customPurchaseOrder,
        variantOf: batch.value!.variantOf,
        customItemBarcode: itemBarcode.value,
        disabled: batch.value!.disabled,
        creation: batch.value!.creation,
        modified: batch.value!.modified,
      );
    }
  }

  Future<void> saveBatch() async {
    if (!isDirty.value && isEditMode) return;

    if (itemController.text.isEmpty) {
      GlobalSnackbar.warning(message: 'Item Code is required');
      return;
    }

    // Critical check for the mandatory field
    if (itemBarcode.value.isEmpty) {
      // Try to fetch it one last time if missing?
      // Or just fail. Let's assume _fetchItemDetails ran.
      // If it is truly empty, we might use item code as fallback here too.
      itemBarcode.value = itemController.text;
    }

    isSaving.value = true;
    final data = _getCurrentFormData();

    try {
      if (isEditMode) {
        final response = await _provider.updateBatch(name, data);
        if (response.statusCode == 200) {
          GlobalSnackbar.success(message: 'Batch updated successfully');
          // Await fetchBatch to ensure isDirty is reset and data is refreshed
          await fetchBatch();
        } else {
          throw Exception(response.data['exception'] ?? 'Unknown Error');
        }
      } else {
        if (batchIdController.text.isEmpty && itemBarcode.value.isNotEmpty) {
          _generateBatchId(itemBarcode.value);
        }

        data['batch_id'] = batchIdController.text;
        data['name'] = batchIdController.text;

        final response = await _provider.createBatch(data);
        if (response.statusCode == 200) {
          GlobalSnackbar.success(message: 'Batch created: ${data['name']}');

          // Switch to Edit Mode and fetch data to update UI (Status, Title, Actions)
          name = data['name'];
          mode = 'edit';
          await fetchBatch();
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
          eyeStyle: const QrEyeStyle(color: Color(0xFF000000)),
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
        await Share.shareXFiles([XFile(file.path)], text: 'Batch QR Code: ${generatedBatchId.value}');
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
      final pageFormat = PdfPageFormat(51 * PdfPageFormat.mm, 26 * PdfPageFormat.mm);
      final String variant = itemVariantOf.value.isNotEmpty ? itemVariantOf.value : itemController.text;
      final String barcodeData = itemBarcode.value.isNotEmpty ? itemBarcode.value : itemController.text;
      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(2 * PdfPageFormat.mm),
          build: (pw.Context context) {
            return pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(
                  flex: 65,
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        variant,
                        style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, font: pw.Font.courier()),
                        maxLines: 2,
                        overflow: pw.TextOverflow.clip,
                      ),
                      pw.SizedBox(height: 2),
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: barcodeData,
                        height: 32,
                        drawText: true,
                        textStyle: pw.TextStyle(font: pw.Font.courier(), fontSize: 6),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  flex: 35,
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.AspectRatio(
                        aspectRatio: 1,
                        child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: generatedBatchId.value, drawText: false),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        generatedBatchId.value,
                        style: pw.TextStyle(font: pw.Font.courier(), fontSize: 5),
                        maxLines: 2,
                        overflow: pw.TextOverflow.clip,
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${generatedBatchId.value}_label.pdf');
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(file.path)], text: 'Batch Label: ${generatedBatchId.value}');
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to export PDF: $e');
    } finally {
      isExporting.value = false;
    }
  }
}