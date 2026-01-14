import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/controllers/frappe_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class BatchFormController extends FrappeFormController {
  BatchFormController() : super(doctype: 'Batch');

  // Observables for Custom UI Logic
  final RxString generatedBatchId = ''.obs;
  final RxString itemVariantOf = ''.obs;
  final RxString itemBarcode = ''.obs;
  final RxBool isExporting = false.obs;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args != null) {
      if (args is Map) {
        final name = args['name'];
        if (name != null && name.toString().isNotEmpty) {
          load(name);
        } else if (args['itemCode'] != null) {
          // Pre-fill item if creating new
          initialize({'item': args['itemCode']});
        }
      }
    }

    // Listen to changes to auto-update UI helpers
    ever(data, (_) => _updateHelpers());
  }

  void _updateHelpers() {
    generatedBatchId.value = getValue('name') ?? '';
    // If you had logic to fetch variant/barcode details based on item, call it here
    // e.g. if (item changed) fetchItemDetails();
  }

  // Getters for UI
  String get batchStatus {
    if (getValue<int>('disabled') == 1) return 'Disabled';
    final expiry = getValue<String>('expiry_date');
    if (expiry != null && DateTime.parse(expiry).isBefore(DateTime.now())) {
      return 'Expired';
    }
    return 'Active';
  }

  // --- Export Logic (Updated to use generic values) ---

  Future<void> exportQrAsPng() async {
    // Implementation for PNG export using generatedBatchId.value
    GlobalSnackbar.success(message: "Exporting PNG...");
  }

  Future<void> exportQrAsPdf() async {
    isExporting.value = true;
    try {
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(getValue('item') ?? 'Unknown Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.SizedBox(height: 5),
                  pw.BarcodeWidget(
                    data: generatedBatchId.value,
                    barcode: pw.Barcode.qrCode(),
                    width: 100,
                    height: 100,
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(generatedBatchId.value, style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            );
          },
        ),
      );
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
    } catch (e) {
      GlobalSnackbar.error(message: "Failed to export PDF: $e");
    } finally {
      isExporting.value = false;
    }
  }
}