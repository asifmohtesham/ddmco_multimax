import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/packing_slip_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

enum LinkedDocType { deliveryNote, stockEntry, none }

class PackingSlipInfo {
  final String psName;
  final int? fromCaseNo;
  final int? toCaseNo;
  const PackingSlipInfo({
    required this.psName,
    this.fromCaseNo,
    this.toCaseNo,
  });
}

/// Represents a selectable case-range option in the case filter.
class CaseOption {
  final String psName;
  final int? fromCaseNo;
  final int? toCaseNo;
  final double totalQty;

  const CaseOption({
    required this.psName,
    this.fromCaseNo,
    this.toCaseNo,
    this.totalQty = 0,
  });

  String get label {
    if (fromCaseNo != null && toCaseNo != null) return 'Cases $fromCaseNo – $toCaseNo';
    if (fromCaseNo != null) return 'Case $fromCaseNo';
    return psName;
  }

  @override
  bool operator ==(Object other) =>
      other is CaseOption && other.psName == psName;

  @override
  int get hashCode => psName.hashCode;
}

/// Carries a matched Packing Slip item for a single POS Upload item.
/// Unlike [PackingSlipInfo] (which holds only case-range metadata),
/// this class includes the full [PackingSlipItem] row for display in the expanded tile.
class PsItemEntry {
  final String psName;
  final int? fromCaseNo;
  final int? toCaseNo;
  final PackingSlipItem item;
  const PsItemEntry({
    required this.psName,
    this.fromCaseNo,
    this.toCaseNo,
    required this.item,
  });
}

class PosUploadFormController extends GetxController
    with OptimisticLockingMixin {
  final PosUploadProvider _provider = Get.find<PosUploadProvider>();
  final DeliveryNoteProvider _dnProvider = Get.find<DeliveryNoteProvider>();
  final StockEntryProvider _seProvider = Get.find<StockEntryProvider>();
  final PackingSlipProvider _psProvider = Get.find<PackingSlipProvider>();
  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  // ── Core state ─────────────────────────────────────────────────────────────
  var isLoading = true.obs;
  var posUpload = Rx<PosUpload?>(null);

  // ── Search / filter ────────────────────────────────────────────────────────
  var searchQuery = ''.obs;
  var filteredItems = <PosUploadItem>[].obs;

  /// Active case filter; null = no filter applied.
  var activeCaseFilter = Rxn<CaseOption>();

  /// All distinct case options built from packingSlips (ML/KA only).
  final caseOptions = <CaseOption>[].obs;

  // ── Linked document (DN or SE) ─────────────────────────────────────────────
  var linkedDocType = LinkedDocType.none.obs;
  var linkedDocName = ''.obs;
  var isLoadingLinked = false.obs;

  /// idx → custom_invoice_serial_number (null = no match)
  final resolvedSerials = <int, String?>{}.obs;

  // ── Packing Slip layer (ML/KA only) ────────────────────────────────────────
  var isLoadingPackingSlips = false.obs;

  /// idx → PackingSlipInfo (null = not found in any PS)
  final resolvedPackingSlips = <int, PackingSlipInfo?>{}.obs;

  /// All Packing Slips fetched for the linked DN.
  final packingSlips = <PackingSlip>[].obs;

  /// idx → DN item qty (null = item not found in DN)
  final resolvedDnQty = <int, double?>{}.obs;

  /// idx → PS items matching this POS Upload item (empty list = none matched)
  final resolvedPsItems = <int, List<PsItemEntry>>{}.obs;

  // ── Number formatter ───────────────────────────────────────────────────────
  static final _numFmt = NumberFormat('#,##0.00');

  static String fmtAmount(double? v) =>
      v == null ? '0.00' : _numFmt.format(v);

  static String fmtQty(double? v) =>
      v == null ? '0' : v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

  static List<PsItemEntry> matchPsItems({
    required List<PackingSlip> slips,
    required String posUploadName,
    required int itemIdx,
  }) {
    final entries = <PsItemEntry>[];
    for (final ps in slips) {
      if (ps.customPoNo != posUploadName) continue;
      for (final psItem in ps.items) {
        if (psItem.customInvoiceSerialNumber == itemIdx.toString()) {
          entries.add(PsItemEntry(
            psName: ps.name,
            fromCaseNo: ps.fromCaseNo,
            toCaseNo: ps.toCaseNo,
            item: psItem,
          ));
        }
      }
    }
    return entries;
  }

  /// Returns the Excel cell value for the "Case #" column in the packing slip export.
  /// Single case → IntCellValue; range → TextCellValue("N-M"); no case → TextCellValue(ps.name).
  static CellValue psCaseCell(PackingSlip ps) {
    if (ps.fromCaseNo == null) return TextCellValue(ps.name);
    if (ps.toCaseNo != null && ps.toCaseNo != ps.fromCaseNo) {
      return TextCellValue('${ps.fromCaseNo}-${ps.toCaseNo}');
    }
    return IntCellValue(ps.fromCaseNo!);
  }

  @override
  void onInit() {
    super.onInit();
    _loadData();
  }

  // ── Initialisation ─────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    isLoading.value = true;
    await fetchPosUpload();
    isLoading.value = false;
    fetchLinkedDocument();
  }

  // ── POS Upload ─────────────────────────────────────────────────────────────

  Future<void> fetchPosUpload() async {
    try {
      final response = await _provider.getPosUpload(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        posUpload.value = PosUpload.fromJson(response.data['data']);
        _applyFilters();
      } else {
        GlobalSnackbar.error(message: 'Failed to fetch POS upload');
      }
    } catch (e) {
      GlobalSnackbar.error(message: e.toString());
    }
  }

  // ── Linked document ────────────────────────────────────────────────────────

  Future<void> fetchLinkedDocument() async {
    final upload = posUpload.value;
    if (upload == null) return;
    final prefix =
        name.length >= 2 ? name.substring(0, 2).toUpperCase() : '';
    if (prefix == 'ML' || prefix == 'KA') {
      await _fetchDeliveryNote(upload);
    } else if (prefix == 'MX' || prefix == 'KX') {
      await _fetchStockEntry(upload);
    }
  }

  Future<void> _fetchDeliveryNote(PosUpload upload) async {
    isLoadingLinked.value = true;
    linkedDocType.value = LinkedDocType.deliveryNote;
    try {
      final listResp = await _dnProvider.getDeliveryNotes(
          limit: 1, filters: {'po_no': name});
      if (listResp.statusCode == 200 &&
          (listResp.data['data'] as List?)?.isNotEmpty == true) {
        final dnName =
            (listResp.data['data'] as List).first['name'].toString();
        linkedDocName.value = dnName;
        final detailResp = await _dnProvider.getDeliveryNote(dnName);
        if (detailResp.statusCode == 200 &&
            detailResp.data['data'] != null) {
          final dn = DeliveryNote.fromJson(detailResp.data['data']);
          _buildSerialMap(
            posItems: upload.items,
            matchSerial: (idx) => dn.items
                .firstWhereOrNull(
                    (i) => i.customInvoiceSerialNumber == idx.toString())
                ?.customInvoiceSerialNumber,
          );
          _buildDnQtyMap(
            posItems: upload.items,
            matchQty: (idx) {
              final serial = idx.toString();
              final matches = dn.items
                  .where((i) => i.customInvoiceSerialNumber == serial)
                  .toList();
              if (matches.isEmpty) return null;
              return matches.fold<double>(0, (sum, i) => sum + i.qty);
            },
          );
        }
        isLoadingLinked.value = false;
        await _fetchPackingSlips(upload, dnName);
      } else {
        linkedDocName.value = '';
        linkedDocType.value = LinkedDocType.none;
        isLoadingLinked.value = false;
      }
    } catch (_) {
      linkedDocType.value = LinkedDocType.none;
      isLoadingLinked.value = false;
    }
  }

  Future<void> _fetchStockEntry(PosUpload upload) async {
    isLoadingLinked.value = true;
    // resolvedDnQty and resolvedPsItems are not applicable to Stock Entry linked uploads.
    linkedDocType.value = LinkedDocType.stockEntry;
    try {
      final listResp = await _seProvider.getStockEntries(
          limit: 1, filters: {'custom_reference_no': name});
      if (listResp.statusCode == 200 &&
          (listResp.data['data'] as List?)?.isNotEmpty == true) {
        final seName =
            (listResp.data['data'] as List).first['name'].toString();
        linkedDocName.value = seName;
        final detailResp = await _seProvider.getStockEntry(seName);
        if (detailResp.statusCode == 200 &&
            detailResp.data['data'] != null) {
          final se = StockEntry.fromJson(detailResp.data['data']);
          _buildSerialMap(
            posItems: upload.items,
            matchSerial: (idx) => se.items
                .firstWhereOrNull((i) => se.items.indexOf(i) + 1 == idx)
                ?.customInvoiceSerialNumber,
          );
        }
      } else {
        linkedDocName.value = '';
        linkedDocType.value = LinkedDocType.none;
      }
    } catch (_) {
      linkedDocType.value = LinkedDocType.none;
    } finally {
      isLoadingLinked.value = false;
    }
  }

  // ── Packing Slip layer ─────────────────────────────────────────────────────

  Future<void> _fetchPackingSlips(PosUpload upload, String dnName) async {
    isLoadingPackingSlips.value = true;
    try {
      final listResp = await _psProvider.getPackingSlips(
        limit: 0,
        filters: {'delivery_note': dnName},
        orderBy: 'from_case_no asc',
      );
      if (listResp.statusCode != 200) return;
      final psList = listResp.data['data'] as List? ?? [];
      if (psList.isEmpty) return;

      final responses = await Future.wait(
          psList.map((ps) =>
              _psProvider.getPackingSlip(ps['name'].toString())));

      final slips = <PackingSlip>[];
      for (final resp in responses) {
        if (resp.statusCode == 200 && resp.data['data'] != null) {
          slips.add(PackingSlip.fromJson(resp.data['data']));
        }
      }
      slips.removeWhere((ps) => ps.docstatus == 2);   // exclude Cancelled
      packingSlips.assignAll(slips);

      // Build idx → PackingSlipInfo.
      final psMap = <int, PackingSlipInfo?>{};
      for (final item in upload.items) {
        final serial = resolvedSerials[item.idx];
        if (serial == null || serial.isEmpty) {
          psMap[item.idx] = null;
          continue;
        }
        PackingSlipInfo? info;
        outer:
        for (final ps in slips) {
          for (final psItem in ps.items) {
            if (psItem.customInvoiceSerialNumber == serial) {
              info = PackingSlipInfo(
                psName: ps.name,
                fromCaseNo: ps.fromCaseNo,
                toCaseNo: ps.toCaseNo,
              );
              break outer;
            }
          }
        }
        psMap[item.idx] = info;
      }
      resolvedPackingSlips.value = psMap;

      // Build idx → list-of-matching-PS-items using the static matching method.
      final psItemsMap = <int, List<PsItemEntry>>{};
      for (final item in upload.items) {
        psItemsMap[item.idx] = matchPsItems(
          slips: slips,
          posUploadName: upload.name,
          itemIdx: item.idx,
        );
      }
      resolvedPsItems.value = psItemsMap;

      // Build a case option for every non-cancelled PS. totalQty is the sum
      // of the PS's own item quantities so the chip shows how many units are
      // packed in that case.
      caseOptions.assignAll(
        slips
            .map((ps) {
              final psQty = ps.items
                  .fold<double>(0, (s, psItem) => s + psItem.qty);
              return CaseOption(
                psName: ps.name,
                fromCaseNo: ps.fromCaseNo,
                toCaseNo: ps.toCaseNo,
                totalQty: psQty,
              );
            })
            .toList(),
      );

      // Re-apply any active case filter now that PS data is available.
      _applyFilters();
    } catch (_) {
    } finally {
      isLoadingPackingSlips.value = false;
    }
  }

  // ── Serial map helper ──────────────────────────────────────────────────────

  void _buildSerialMap({
    required List<PosUploadItem> posItems,
    required String? Function(int idx) matchSerial,
  }) {
    final map = <int, String?>{};
    for (final item in posItems) {
      map[item.idx] = matchSerial(item.idx);
    }
    resolvedSerials.value = map;
  }

  void _buildDnQtyMap({
    required List<PosUploadItem> posItems,
    required double? Function(int idx) matchQty,
  }) {
    final map = <int, double?>{};
    for (final item in posItems) {
      map[item.idx] = matchQty(item.idx);
    }
    resolvedDnQty.value = map;
  }

  // ── Search + Case filter ───────────────────────────────────────────────────

  void filterByText(String query) {
    searchQuery.value = query;
    _applyFilters();
  }

  // Keep the old name as an alias so existing call-sites don't break.
  void filterItems(String query) => filterByText(query);

  void filterByCase(CaseOption? option) {
    activeCaseFilter.value = option;
    _applyFilters();
  }

  void clearFilters() {
    searchQuery.value = '';
    activeCaseFilter.value = null;
    _applyFilters();
  }

  void _applyFilters() {
    final allItems = posUpload.value?.items ?? [];
    var result = allItems;

    // Text filter
    final q = searchQuery.value.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result
          .where((i) => i.itemName.toLowerCase().contains(q))
          .toList();
    }

    // Case filter — use resolvedPsItems (all PS matches) not resolvedPackingSlips (first-match only).
    final caseFilter = activeCaseFilter.value;
    if (caseFilter != null && resolvedPsItems.isNotEmpty) {
      result = result.where((i) {
        final entries = resolvedPsItems[i.idx] ?? [];
        return entries.any((e) => e.psName == caseFilter.psName);
      }).toList();
    }

    filteredItems.assignAll(result);
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  @override
  Future<void> reloadDocument() async {
    await fetchPosUpload();
    await fetchLinkedDocument();
    GlobalSnackbar.success(message: 'Document reloaded successfully');
  }

  // ── Excel export ───────────────────────────────────────────────────────────

  Future<void> sharePackingSlipExcel({required bool compact}) async {
    final upload = posUpload.value;
    if (upload == null || packingSlips.isEmpty) {
      GlobalSnackbar.error(message: 'No packing slip data available');
      return;
    }

    Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );

    try {
      final itemNameByIdx = <String, String>{
        for (final item in upload.items) item.idx.toString(): item.itemName,
      };

      final excelFile = Excel.createExcel();
      excelFile.rename('Sheet1', upload.name);
      final sheet = excelFile[upload.name];

      final headers = compact
          ? ['Case #', 'Invoice Serial #', 'Item Name', 'Qty', 'Country of Origin']
          : ['Case #', 'Invoice Serial #', 'Variant Of', 'Item Code', 'Item Name', 'Qty', 'Country of Origin'];

      for (int c = 0; c < headers.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
            .value = TextCellValue(headers[c]);
      }

      int row = 1;
      for (final ps in packingSlips.where((p) => p.customPoNo == upload.name)) {
        final caseCell = psCaseCell(ps);
        for (final psItem in ps.items) {
          final posItemName =
              itemNameByIdx[psItem.customInvoiceSerialNumber] ?? psItem.itemName;
          final serial =
              int.tryParse(psItem.customInvoiceSerialNumber ?? '') ?? 0;

          void setCell(int col, CellValue v) => sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
              .value = v;

          if (compact) {
            setCell(0, caseCell);
            setCell(1, IntCellValue(serial));
            setCell(2, TextCellValue(posItemName));
            setCell(3, DoubleCellValue(psItem.qty));
            setCell(4, TextCellValue(psItem.customCountryOfOrigin ?? ''));
          } else {
            setCell(0, caseCell);
            setCell(1, IntCellValue(serial));
            setCell(2, TextCellValue(psItem.customVariantOf ?? ''));
            setCell(3, TextCellValue(psItem.itemCode));
            setCell(4, TextCellValue(posItemName));
            setCell(5, DoubleCellValue(psItem.qty));
            setCell(6, TextCellValue(psItem.customCountryOfOrigin ?? ''));
          }
          row++;
        }
      }

      final fileBytes = excelFile.encode();
      if (fileBytes == null) {
        if (Get.isDialogOpen == true) Get.back();
        GlobalSnackbar.error(message: 'Failed to encode Excel file');
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final safeName = upload.name.replaceAll('/', '_');
      final filePath = '${tempDir.path}/${safeName}_packing_slip.xlsx';
      await File(filePath).writeAsBytes(Uint8List.fromList(fileBytes));

      if (Get.isDialogOpen == true) Get.back();

      await Share.shareXFiles(
        [
          XFile(
            filePath,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        subject: '${upload.name} – Packing Slip',
      );
    } catch (e) {
      if (Get.isDialogOpen == true) Get.back();
      GlobalSnackbar.error(message: 'Share failed: $e');
    }
  }
}
