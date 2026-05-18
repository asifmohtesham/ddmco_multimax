import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/models/batch_model.dart';
import 'package:multimax/app/data/providers/batch_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';

/// GetX controller for the **Batch form** screen.
///
/// Operates in two modes determined by [mode]:
/// - `'new'`  — blank form, generates a Batch ID from the selected item's
///   EAN barcode + a random 6-character alphanumeric suffix.
/// - `'edit'` — fetches the existing [Batch] document from ERPNext and
///   populates all form controllers.
///
/// Uses [OptimisticLockingMixin] to guard against concurrent edits:
/// - [checkStaleAndBlock] is called at the start of [saveBatch].
/// - [handleVersionConflict] is called in the catch block.
/// - [reloadDocument] is implemented to delegate to [fetchBatch].
class BatchFormController extends GetxController with OptimisticLockingMixin {
  final BatchProvider _provider = Get.find<BatchProvider>();

  /// Batch document name (ERPNext `name` field).  Empty string in new mode.
  String name = '';

  /// Form mode: `'new'` or `'edit'`.  Switches to `'edit'` after a
  /// successful [saveBatch] in new mode.
  String mode = 'new';

  /// `true` during any API fetch (initial load or reload).
  var isLoading = true.obs;

  /// `true` while [saveBatch] is in flight.
  var isSaving = false.obs;

  /// `true` while [exportQrAsPng] or [exportQrAsPdf] is in flight.
  var isExporting = false.obs;

  /// `true` when the form has unsaved changes relative to [_originalJson].
  /// Always `true` in new mode.
  var isDirty = false.obs;

  /// JSON snapshot of the form state immediately after a successful fetch.
  /// Used by [_checkForChanges] to detect mutations.
  String _originalJson = '';

  /// Guard flag set to `true` while [fetchBatch] is populating controllers
  /// programmatically.  Prevents the controller change listeners from
  /// incorrectly marking the form as dirty during a fetch.
  bool _isFetching = false;

  /// Reactive reference to the current [Batch] model.
  var batch = Rx<Batch?>(null);

  // ── Form controllers — one per Frappe Batch field ─────────────────────

  /// Maps to Frappe `batch_id` / `name`.
  final batchIdController = TextEditingController();

  /// Maps to Frappe `item` (Item Code).
  final itemController = TextEditingController();

  /// Maps to Frappe `description`.
  final descriptionController = TextEditingController();

  /// Maps to Frappe `manufacturing_date` (ISO date string `yyyy-MM-dd`).
  final mfgDateController = TextEditingController();

  /// Maps to Frappe `expiry_date` (ISO date string `yyyy-MM-dd`).
  final expDateController = TextEditingController();

  /// Maps to Frappe `custom_packaging_qty`.
  final customPackagingQtyController = TextEditingController();

  /// Maps to Frappe `custom_purchase_order`.
  final customPurchaseOrderController = TextEditingController();

  // ── Status state ───────────────────────────────────────────────────────

  /// Whether the batch is disabled in ERPNext (`disabled == 1`).
  var isDisabled = false.obs;

  // ── Derived / supplementary state ─────────────────────────────────────

  /// The batch ID shown in the QR / label preview.  Set by
  /// [_generateBatchId] (new mode) or loaded from [Batch.name] (edit mode).
  var generatedBatchId = ''.obs;

  /// EAN/barcode value for the selected item, sourced from the Item master's
  /// `barcodes` child table, falling back to the item code itself.
  var itemBarcode = ''.obs;

  /// `variant_of` value from the Item master.  Used as the variant label
  /// in the PDF label layout.
  var itemVariantOf = ''.obs;

  // ── Picker list state ─────────────────────────────────────────────────

  /// `true` while [searchItems] is in flight.
  var isFetchingItems = false.obs;

  /// Results from [searchItems], rendered in the item picker sheet.
  var itemList = <Map<String, dynamic>>[].obs;

  /// `true` while [searchPurchaseOrders] is in flight.
  var isFetchingPOs = false.obs;

  /// Results from [searchPurchaseOrders], rendered in the PO picker sheet.
  var poList = <Map<String, dynamic>>[].obs;

  /// `true` when [mode] is `'edit'`.
  bool get isEditMode => mode == 'edit';

  /// Persists the random 6-char suffix across item code changes in new mode.
  /// Ensures the suffix stays stable if the user re-selects an item or
  /// the EAN barcode is refreshed, preserving the batch ID they see.
  String? _currentRandomSuffix;

  // ── Status logic ──────────────────────────────────────────────────────

  /// Computed batch status string.  Priority order:
  ///
  /// 1. **Not Saved** — [isDirty] is `true` (unsaved changes exist).
  /// 2. **Disabled**  — [isDisabled] is `true`.
  /// 3. **Expired**   — [expDateController] holds a date in the past.
  /// 4. **Active**    — none of the above conditions are met.
  ///
  /// Colours for each state are applied by `StatusPill`, not here.
  String get batchStatus {
    if (isDirty.value) return 'Not Saved';
    if (isDisabled.value) return 'Disabled';
    if (expDateController.text.isNotEmpty) {
      final expiry = DateTime.tryParse(expDateController.text);
      if (expiry != null && expiry.isBefore(DateTime.now())) {
        return 'Expired';
      }
    }
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
        // Handle GlobalSearchDelegate argument (just the document ID).
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

  // ── PopScope / discard ──────────────────────────────────────────────────

  /// Shows the standard "Unsaved Changes" dialog ([GlobalDialog.showUnsavedChanges]).
  /// On confirm-discard, resets [isDirty] and pops the route.
  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
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
    _currentRandomSuffix = null;

    isDirty.value = true;
    _originalJson = '';

    isLoading.value = false;
  }

  // ── OptimisticLockingMixin implementation ─────────────────────────────

  /// Required by [OptimisticLockingMixin].  Delegates to [fetchBatch] and
  /// shows a success notification when the reload completes.
  @override
  Future<void> reloadDocument() async {
    await fetchBatch();
    AppNotification.success('Document reloaded successfully');
  }

  // ── Fetch ─────────────────────────────────────────────────────────────

  /// Loads the Batch document identified by [name] from ERPNext.
  ///
  /// Sets [_isFetching] to `true` for the duration of the call to suppress
  /// dirty-check noise from the controller listeners being updated
  /// programmatically.  [_fetchItemDetails] is awaited before snapshotting
  /// [_originalJson] so that [itemBarcode] and [itemVariantOf] are already
  /// populated — preventing a spurious dirty state on first render.
  Future<void> fetchBatch() async {
    isLoading.value = true;
    _isFetching = true;
    try {
      final response = await _provider.getBatch(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final b = Batch.fromJson(response.data['data']);
        batch.value = b;

        batchIdController.text = b.name;
        itemController.text = b.item;
        descriptionController.text = b.description ?? '';
        mfgDateController.text = b.manufacturingDate ?? '';
        expDateController.text = b.expiryDate ?? '';
        customPackagingQtyController.text = b.customPackagingQty.toString();
        customPurchaseOrderController.text = b.customPurchaseOrder ?? '';
        isDisabled.value = b.disabled == 1;

        generatedBatchId.value = b.name;

        itemBarcode.value = b.customItemBarcode ?? '';
        itemVariantOf.value = b.variantOf ?? '';

        if (b.item.isNotEmpty) {
          await _fetchItemDetails(b.item, generateId: false);
        }

        _originalJson = jsonEncode(_getCurrentFormData());
        isDirty.value = false;
      }
    } catch (e) {
      AppNotification.error('Failed to load batch: $e');
    } finally {
      isLoading.value = false;
      _isFetching = false;
    }
  }

  void _checkForChanges() {
    if (_isFetching) return;
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

  // ── Picker search ────────────────────────────────────────────────────────

  /// Queries [BatchProvider.searchItems] and populates [itemList].
  /// Only returns batch-managed items (`has_batch_no == 1`).
  Future<void> searchItems(String query) async {
    isFetchingItems.value = true;
    try {
      final response = await _provider.searchItems(query);
      if (response.statusCode == 200 && response.data['data'] != null) {
        itemList.assignAll(List<Map<String, dynamic>>.from(response.data['data']));
      }
    } catch (e) {
      AppNotification.error('Failed to search items: $e');
    } finally {
      isFetchingItems.value = false;
    }
  }

  /// Queries [BatchProvider.searchPurchaseOrders] and populates [poList].
  Future<void> searchPurchaseOrders(String query) async {
    isFetchingPOs.value = true;
    try {
      final response = await _provider.searchPurchaseOrders(query);
      if (response.statusCode == 200 && response.data['data'] != null) {
        poList.assignAll(List<Map<String, dynamic>>.from(response.data['data']));
      }
    } catch (e) {
      AppNotification.error('Failed to search purchase orders: $e');
    } finally {
      isFetchingPOs.value = false;
    }
  }

  /// Commits [itemData] selection: updates [itemController], dismisses the
  /// picker sheet via [Get.back], and fetches item details to populate
  /// [itemBarcode], [itemVariantOf], and trigger [_generateBatchId].
  void selectItem(Map<String, dynamic> itemData) {
    itemController.text = itemData['item_code'];
    Get.back();
    _fetchItemDetails(itemData['item_code'], generateId: true);
  }

  /// Commits PO selection: updates [customPurchaseOrderController] and
  /// dismisses the picker sheet via [Get.back].
  void selectPurchaseOrder(String poName) {
    customPurchaseOrderController.text = poName;
    Get.back();
  }

  Future<void> _fetchItemDetails(String itemCode, {bool generateId = false}) async {
    try {
      final response = await _provider.getItemDetails(itemCode);
      if (response.statusCode == 200 && response.data['data'] != null) {
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
      AppNotification.error('Failed to fetch item details: $e');
    }
  }

  /// Generates [generatedBatchId] in the format `{ean}-{suffix}` where:
  /// - `ean` is the item's EAN/barcode value.
  /// - `suffix` is a 6-character alphanumeric string drawn from
  ///   `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (ambiguous characters removed).
  ///
  /// The suffix is generated once and cached in [_currentRandomSuffix] so
  /// that changing the selected item refreshes the EAN prefix while keeping
  /// the suffix stable — preventing the batch ID from changing unexpectedly
  /// mid-session.
  void _generateBatchId(String ean) {
    if (_currentRandomSuffix == null) {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final rnd = Random();
      _currentRandomSuffix = String.fromCharCodes(Iterable.generate(
          6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
    }

    generatedBatchId.value = '$ean-$_currentRandomSuffix';
    batchIdController.text = generatedBatchId.value;

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

  // ── Save ─────────────────────────────────────────────────────────────────

  /// Persists the form to ERPNext.
  ///
  /// Guard sequence:
  /// 1. Short-circuits if [isDirty] is `false` in edit mode (no changes).
  /// 2. Calls [checkStaleAndBlock] ([OptimisticLockingMixin]) — returns early
  ///    if the document is stale (modified by another user since last fetch).
  /// 3. Validates that [itemController] is non-empty.
  ///
  /// On conflict the catch block delegates to [handleVersionConflict]
  /// ([OptimisticLockingMixin]) which shows the conflict dialog and returns
  /// `true`, causing [saveBatch] to return without showing a generic error.
  Future<void> saveBatch() async {
    if (!isDirty.value && isEditMode) return;

    if (checkStaleAndBlock()) return;

    if (itemController.text.isEmpty) {
      AppNotification.warning('Item Code is required');
      return;
    }

    if (itemBarcode.value.isEmpty) {
      itemBarcode.value = itemController.text;
    }

    isSaving.value = true;
    final data = _getCurrentFormData();

    if (isEditMode) {
      data['modified'] = batch.value?.modified;
    }

    try {
      if (isEditMode) {
        final response = await _provider.updateBatch(name, data);
        if (response.statusCode == 200) {
          AppNotification.success('Batch updated successfully');
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
          AppNotification.success('Batch created: ${data['name']}');
          name = data['name'];
          mode = 'edit';
          await fetchBatch();
        } else {
          throw Exception(response.data['exception'] ?? 'Unknown Error');
        }
      }
    } catch (e) {
      if (handleVersionConflict(e)) return;
      AppNotification.error('Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  // ── Date picker ──────────────────────────────────────────────────────────

  /// Opens a [showDatePicker] dialog and writes the selected date in
  /// `yyyy-MM-dd` format to [controller].  No-ops if the user cancels.
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

  // ── Export ───────────────────────────────────────────────────────────────

  /// Renders [generatedBatchId] as a 1024×1024 QR code PNG and shares it
  /// via the platform share sheet.  No-ops if [generatedBatchId] is empty.
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
      AppNotification.error('Failed to export PNG: $e');
    } finally {
      isExporting.value = false;
    }
  }

  /// Renders a thermal label as a PDF (51 mm × 26 mm) and shares it via
  /// the platform share sheet.
  ///
  /// Label layout (left-to-right, 65/35 flex split):
  /// - **Left column**: variant name (bold, Code128 barcode of [itemBarcode],
  ///   barcode text in 6 pt Courier).
  /// - **Right column**: QR code of [generatedBatchId], batch ID text below.
  ///
  /// No-ops if [generatedBatchId] is empty.
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
      AppNotification.error('Failed to export PDF: $e');
    } finally {
      isExporting.value = false;
    }
  }
}
