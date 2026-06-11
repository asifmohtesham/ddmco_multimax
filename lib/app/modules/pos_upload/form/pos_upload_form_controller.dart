import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/mixins/realtime_sync_mixin.dart';
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

// Stable names for the anonymous row record and column tuple used in
// sharePackingSlipExcel and _rowComparator.
typedef _PSRow = ({
  CellValue caseCell,
  String    caseKey,
  int       serial,
  String    variantOf,
  String    itemCode,
  String    itemName,
  double    qty,
  String    country,
});

typedef _PSCol = (String, CellValue Function(_PSRow));

/// Public record for a single Delivery Note export row.
/// Public (unlike _PSRow) so unit tests can call buildDnRows directly.
typedef DnRow = ({
  int    serial,
  String variantOf,
  String itemCode,
  String itemName,
  double qty,
  String country,
});

// ── compute() plumbing ──────────────────────────────────────────────────────

class _PackingSlipExcelParams {
  final String docName;
  final String docDate;
  final Map<String, String> itemNameByIdx;
  final List<PackingSlip> packingSlips;
  final bool compact;
  final String? sortByColumn;

  const _PackingSlipExcelParams({
    required this.docName,
    required this.docDate,
    required this.itemNameByIdx,
    required this.packingSlips,
    required this.compact,
    this.sortByColumn,
  });
}

// Top-level function — required by compute(). Runs in a background isolate.
// Returns the final xlsx bytes (Consolas font, autofit, Excel Table injected).
List<int> _buildPackingSlipExcel(_PackingSlipExcelParams p) {
  final safeName = p.docName.replaceAll('/', '_');
  final excelFile = Excel.createExcel();
  excelFile.rename('Sheet1', safeName);
  final sheet = excelFile[safeName];

  var columns = p.compact
      ? <_PSCol>[
          ('Case #',            (r) => r.caseCell),
          ('Invoice Serial #',  (r) => IntCellValue(r.serial)),
          ('Item Name',         (r) => TextCellValue(r.itemName)),
          ('Qty',               (r) => DoubleCellValue(r.qty)),
          ('Country of Origin', (r) => TextCellValue(r.country)),
        ]
      : <_PSCol>[
          ('Case #',            (r) => r.caseCell),
          ('Invoice Serial #',  (r) => IntCellValue(r.serial)),
          ('Variant Of',        (r) => TextCellValue(r.variantOf)),
          ('Item Code',         (r) => TextCellValue(r.itemCode)),
          ('Item Name',         (r) => TextCellValue(r.itemName)),
          ('Qty',               (r) => DoubleCellValue(r.qty)),
          ('Country of Origin', (r) => TextCellValue(r.country)),
        ];

  final rowMap = <String, _PSRow>{};
  for (final ps in p.packingSlips) {
    final caseCell = PosUploadFormController.psCaseCell(ps);
    final caseKey  = PosUploadFormController._psCaseKey(ps);
    for (final psItem in ps.items) {
      final posItemName =
          p.itemNameByIdx[psItem.customInvoiceSerialNumber] ?? psItem.itemName;
      final serial    = int.tryParse(psItem.customInvoiceSerialNumber ?? '') ?? 0;
      final variantOf = psItem.customVariantOf ?? '';
      final itemCode  = psItem.itemCode;
      final country   = psItem.customCountryOfOrigin ?? '';

      final key = p.compact
          ? '$caseKey\x00$serial\x00$posItemName\x00$country'
          : '$caseKey\x00$serial\x00$variantOf\x00$itemCode\x00$posItemName\x00$country';

      final existing = rowMap[key];
      rowMap[key] = existing == null
          ? (
              caseCell:  caseCell,
              caseKey:   caseKey,
              serial:    serial,
              variantOf: variantOf,
              itemCode:  itemCode,
              itemName:  posItemName,
              qty:       psItem.qty,
              country:   country,
            )
          : (
              caseCell:  existing.caseCell,
              caseKey:   existing.caseKey,
              serial:    existing.serial,
              variantOf: existing.variantOf,
              itemCode:  existing.itemCode,
              itemName:  existing.itemName,
              qty:       existing.qty + psItem.qty,
              country:   existing.country,
            );
    }
  }

  final sortedRows = rowMap.values.toList();
  if (p.sortByColumn != null) {
    final sortIdx = columns.indexWhere((c) => c.$1 == p.sortByColumn);
    if (sortIdx >= 0) {
      sortedRows.sort(
          (a, b) => PosUploadFormController._rowComparator(p.sortByColumn!, a, b));
      if (sortIdx > 0) {
        final col = columns.removeAt(sortIdx);
        columns.insert(0, col);
      }
    }
  }

  // ── Document header (rows 0–3, row 3 is blank) ───────────────────────
  const tableStartRow = 4;

  CellIndex idx(int c, int r) =>
      CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r);

  sheet.cell(idx(0, 0))
    ..value = TextCellValue('Packing Slip')
    ..cellStyle = CellStyle(fontFamily: 'Consolas', fontSize: 20, bold: true);

  sheet.cell(idx(0, 1))
    ..value = TextCellValue(p.docName)
    ..cellStyle = CellStyle(fontFamily: 'Consolas', fontSize: 13);

  String formattedDate;
  try {
    formattedDate =
        DateFormat('dd MMM yyyy').format(DateTime.parse(p.docDate));
  } catch (_) {
    formattedDate = p.docDate;
  }
  sheet.cell(idx(0, 2))
    ..value = TextCellValue(formattedDate)
    ..cellStyle = CellStyle(fontFamily: 'Consolas', fontSize: 11);

  // ── Table column headers ──────────────────────────────────────────────
  final bodyStyle = CellStyle(fontFamily: 'Consolas', fontSize: 11);

  for (int c = 0; c < columns.length; c++) {
    sheet.cell(idx(c, tableStartRow))
      ..value = TextCellValue(columns[c].$1)
      ..cellStyle = bodyStyle;
  }

  // ── Data rows ─────────────────────────────────────────────────────────
  int row = tableStartRow + 1;
  for (final r in sortedRows) {
    for (int c = 0; c < columns.length; c++) {
      sheet.cell(idx(c, row))
        ..value = columns[c].$2(r)
        ..cellStyle = bodyStyle;
    }
    row++;
  }

  // ── Autofit ───────────────────────────────────────────────────────────
  for (int c = 0; c < columns.length; c++) {
    sheet.setColumnAutoFit(c);
  }

  final rawBytes = excelFile.encode()!;
  return PosUploadFormController._injectExcelTable(
    rawBytes,
    columns.map((col) => col.$1).toList(),
    sortedRows.length,
    tableStartRow: tableStartRow,
  );
}

class PosUploadFormController extends GetxController
    with OptimisticLockingMixin, RealtimeSyncMixin {
  final PosUploadProvider _provider = Get.find<PosUploadProvider>();
  final DeliveryNoteProvider _dnProvider = Get.find<DeliveryNoteProvider>();
  final StockEntryProvider _seProvider = Get.find<StockEntryProvider>();
  final PackingSlipProvider _psProvider = Get.find<PackingSlipProvider>();
  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  // ── RealtimeSyncMixin requirements ─────────────────────────────────────────
  @override String get realtimeDoctype => 'POS Upload';
  @override String get realtimeDocname => name;
  @override var isDirty = false.obs;
  @override var isSaving = false.obs;

  /// POS Upload is a read-only view — no edits are made from this screen.
  @override
  Future<void> saveDocument() async {}

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

  // String key used for row-aggregation grouping (mirrors psCaseCell logic).
  static String _psCaseKey(PackingSlip ps) {
    if (ps.fromCaseNo == null) return ps.name;
    if (ps.toCaseNo != null && ps.toCaseNo != ps.fromCaseNo) {
      return '${ps.fromCaseNo}-${ps.toCaseNo}';
    }
    return '${ps.fromCaseNo}';
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

  static int _rowComparator(String col, _PSRow a, _PSRow b) {
    switch (col) {
      case 'Case #':
        final an = int.tryParse(a.caseKey.split('-').first);
        final bn = int.tryParse(b.caseKey.split('-').first);
        if (an != null && bn != null) return an.compareTo(bn);
        return a.caseKey.compareTo(b.caseKey);
      case 'Invoice Serial #':
        return a.serial.compareTo(b.serial);
      case 'Qty':
        return a.qty.compareTo(b.qty);
      case 'Item Name':
        return a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase());
      case 'Variant Of':
        return a.variantOf.toLowerCase().compareTo(b.variantOf.toLowerCase());
      case 'Item Code':
        return a.itemCode.toLowerCase().compareTo(b.itemCode.toLowerCase());
      case 'Country of Origin':
        return a.country.toLowerCase().compareTo(b.country.toLowerCase());
      default:
        return 0;
    }
  }

  /// Builds the aggregated, optionally sorted row set for the DN Excel export.
  /// Mirrors the PS export semantics: rows whose displayed text columns are
  /// identical aggregate their qty; item names resolve from the POS Upload
  /// items by invoice serial, falling back to the DN item's own name/code.
  static List<DnRow> buildDnRows({
    required List<DeliveryNoteItem> items,
    required Map<String, String> itemNameByIdx,
    required bool compact,
    String? sortByColumn,
  }) {
    final rowMap = <String, DnRow>{};
    for (final dnItem in items) {
      final serialStr = dnItem.customInvoiceSerialNumber ?? '';
      final itemName =
          itemNameByIdx[serialStr] ?? dnItem.itemName ?? dnItem.itemCode;
      final serial    = int.tryParse(serialStr) ?? 0;
      final variantOf = dnItem.customVariantOf ?? '';
      final itemCode  = dnItem.itemCode;
      final country   = dnItem.countryOfOrigin ?? '';

      final key = compact
          ? '$serial\x00$itemName\x00$country'
          : '$serial\x00$variantOf\x00$itemCode\x00$itemName\x00$country';

      final existing = rowMap[key];
      rowMap[key] = existing == null
          ? (
              serial:    serial,
              variantOf: variantOf,
              itemCode:  itemCode,
              itemName:  itemName,
              qty:       dnItem.qty,
              country:   country,
            )
          : (
              serial:    existing.serial,
              variantOf: existing.variantOf,
              itemCode:  existing.itemCode,
              itemName:  existing.itemName,
              qty:       existing.qty + dnItem.qty,
              country:   existing.country,
            );
    }

    final rows = rowMap.values.toList();
    if (sortByColumn != null) {
      rows.sort((a, b) => _dnRowComparator(sortByColumn, a, b));
    }
    return rows;
  }

  static int _dnRowComparator(String col, DnRow a, DnRow b) {
    switch (col) {
      case 'Invoice Serial #':
        return a.serial.compareTo(b.serial);
      case 'Qty':
        return a.qty.compareTo(b.qty);
      case 'Item Name':
        return a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase());
      case 'Variant Of':
        return a.variantOf.toLowerCase().compareTo(b.variantOf.toLowerCase());
      case 'Item Code':
        return a.itemCode.toLowerCase().compareTo(b.itemCode.toLowerCase());
      case 'Country of Origin':
        return a.country.toLowerCase().compareTo(b.country.toLowerCase());
      default:
        return 0;
    }
  }

  @override
  void onInit() {
    super.onInit();
    _loadData();
  }

  @override
  void onClose() {
    disposeRealtimeSync();
    super.onClose();
  }

  // ── Initialisation ─────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    isLoading.value = true;
    await fetchPosUpload().then((_) => initRealtimeSync());
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

  // Builds the xlsx and writes it to the temp directory.
  // Returns the file path on success; throws on failure.
  // The caller is responsible for opening the share sheet and handling errors.
  Future<String> buildPackingSlipExcel({
    required bool compact,
    String? sortByColumn,
  }) async {
    final upload = posUpload.value;
    if (upload == null || packingSlips.isEmpty) {
      throw Exception('No packing slip data available');
    }

    final params = _PackingSlipExcelParams(
      docName: upload.name,
      docDate: upload.date,
      itemNameByIdx: {
        for (final item in upload.items) item.idx.toString(): item.itemName,
      },
      packingSlips:
          packingSlips.where((p) => p.customPoNo == upload.name).toList(),
      compact: compact,
      sortByColumn: sortByColumn,
    );

    // Runs in a background isolate — caller's UI stays responsive.
    final fileBytes = await compute(_buildPackingSlipExcel, params);

    final timestamp = DateFormat('yyyyMMdd HHmmss').format(DateTime.now());
    final safeName  = upload.name.replaceAll('/', '_');
    final fileName  = 'POS Upload - $safeName - $timestamp';
    final tempDir   = await getTemporaryDirectory();
    final filePath  = '${tempDir.path}/$fileName.xlsx';
    await File(filePath).writeAsBytes(Uint8List.fromList(fileBytes));

    return filePath;
  }

  // ── Excel post-processing helpers ───────────────────────────────────────

  // Injects a structured Excel Table into an already-encoded xlsx file.
  // The table covers the header row (row 0) plus [dataRowCount] data rows.
  static List<int> _injectExcelTable(
    List<int> xlsxBytes,
    List<String> columnNames,
    int dataRowCount, {
    int tableStartRow = 0,
  }) {
    final archive = ZipDecoder().decodeBytes(xlsxBytes);
    final colCount = columnNames.length;
    final lastCol = _excelColLetter(colCount - 1);
    // tableStartRow is 0-based; Excel refs are 1-based.
    final firstExcelRow = tableStartRow + 1;
    final ref = 'A$firstExcelRow:$lastCol${firstExcelRow + dataRowCount}';

    final colsBuffer = StringBuffer();
    for (int i = 0; i < colCount; i++) {
      colsBuffer
          .write('<tableColumn id="${i + 1}" name="${_xmlEscape(columnNames[i])}"/>');
    }

    final tableXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
        ' id="1" name="PackingSlipTable" displayName="PackingSlipTable"'
        ' ref="$ref" totalsRowShown="0">'
        '<autoFilter ref="$ref"/>'
        '<tableColumns count="$colCount">$colsBuffer</tableColumns>'
        '<tableStyleInfo name="TableStyleMedium9" showFirstColumn="0"'
        ' showLastColumn="0" showRowStripes="1" showColumnStripes="0"/>'
        '</table>';

    const relsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1"'
        ' Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/table"'
        ' Target="../tables/table1.xml"/>'
        '</Relationships>';

    // Patch worksheet: add <tableParts> before </worksheet>
    final wsFile = archive.findFile('xl/worksheets/sheet1.xml');
    if (wsFile != null) {
      wsFile.decompress();
      var wsXml = utf8.decode(wsFile.content as List<int>);
      wsXml = wsXml.replaceFirst(
        '</worksheet>',
        '<tableParts count="1"><tablePart r:id="rId1"/></tableParts></worksheet>',
      );
      archive.addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', wsXml));
    }

    // Patch [Content_Types].xml
    final ctFile = archive.findFile('[Content_Types].xml');
    if (ctFile != null) {
      ctFile.decompress();
      var ctXml = utf8.decode(ctFile.content as List<int>);
      ctXml = ctXml.replaceFirst(
        '</Types>',
        '<Override PartName="/xl/tables/table1.xml"'
            ' ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.table+xml"/>'
            '</Types>',
      );
      archive.addFile(ArchiveFile.string('[Content_Types].xml', ctXml));
    }

    archive.addFile(ArchiveFile.string('xl/tables/table1.xml', tableXml));
    archive.addFile(ArchiveFile.string(
        'xl/worksheets/_rels/sheet1.xml.rels', relsXml));

    return ZipEncoder().encode(archive) ?? xlsxBytes;
  }

  // Converts a 0-based column index to an Excel column letter (0→A, 25→Z, 26→AA).
  static String _excelColLetter(int index) {
    var result = '';
    var n = index + 1;
    while (n > 0) {
      final remainder = (n - 1) % 26;
      result = String.fromCharCode(65 + remainder) + result;
      n = (n - 1) ~/ 26;
    }
    return result;
  }

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
