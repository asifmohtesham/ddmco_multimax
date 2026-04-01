import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/packing_slip_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
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

class PosUploadFormController extends GetxController
    with OptimisticLockingMixin {
  final PosUploadProvider _provider = Get.find<PosUploadProvider>();
  final DeliveryNoteProvider _dnProvider = Get.find<DeliveryNoteProvider>();
  final StockEntryProvider _seProvider = Get.find<StockEntryProvider>();
  final PackingSlipProvider _psProvider = Get.find<PackingSlipProvider>();
  final AuthenticationController _authController =
      Get.find<AuthenticationController>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  // ── Core state ─────────────────────────────────────────────────────────────
  var isLoading = true.obs;
  var isSaving = false.obs;
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

  // ── Permissions (cached after first load) ──────────────────────────────────
  final Map<String, int> _fieldLevels = {};
  final Map<int, Set<String>> _levelWriteRoles = {};
  var permissionsLoaded = false.obs;

  // Cached per-field edit flags set once permissions are loaded.
  bool _canEditStatus = false;
  bool _canEditAmount = false;
  bool _canEditQty = false;

  // ── Number formatter ───────────────────────────────────────────────────────
  static final _numFmt = NumberFormat('#,##0.00');

  static String fmtAmount(double? v) =>
      v == null ? '0.00' : _numFmt.format(v);

  static String fmtQty(double? v) =>
      v == null ? '0' : v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

  @override
  void onInit() {
    super.onInit();
    _loadData();
  }

  // ── Initialisation ─────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    isLoading.value = true;
    await Future.wait([fetchPosUpload(), fetchDocTypePermissions()]);
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
                .firstWhereOrNull((i) => i.idx == idx)
                ?.customInvoiceSerialNumber,
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
      packingSlips.assignAll(slips);

      // Build case options for the filter.
      caseOptions.assignAll(
        slips
            .map((ps) => CaseOption(
                  psName: ps.name,
                  fromCaseNo: ps.fromCaseNo,
                  toCaseNo: ps.toCaseNo,
                  totalQty: (ps.items ?? [])
                    .fold(0, (s, i) => s + (i.qty ?? 0)),
                ))
            .toList(),
      );

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

    // Case filter (only meaningful after PS data is resolved)
    final caseFilter = activeCaseFilter.value;
    if (caseFilter != null && resolvedPackingSlips.isNotEmpty) {
      result = result.where((i) {
        final psInfo = resolvedPackingSlips[i.idx];
        return psInfo?.psName == caseFilter.psName;
      }).toList();
    }

    filteredItems.assignAll(result);
  }

  // ── Status update ──────────────────────────────────────────────────────────

  Future<void> updateStatus(String newStatus) async {
    await updatePosUpload({'status': newStatus});
  }

  // ── Permissions ────────────────────────────────────────────────────────────

  Future<void> fetchDocTypePermissions() async {
    try {
      final response =
          await _apiProvider.getDocument('DocType', 'POS Upload');
      if (response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'];
        _fieldLevels['status'] = 0;
        if (data['fields'] != null) {
          for (var field in data['fields']) {
            _fieldLevels[field['fieldname'].toString()] =
                field['permlevel'] as int? ?? 0;
          }
        }
        if (data['permissions'] != null) {
          for (var perm in data['permissions']) {
            final role = perm['role'].toString();
            final level = perm['permlevel'] as int? ?? 0;
            if (perm['write'] == 1) {
              _levelWriteRoles.putIfAbsent(level, () => {}).add(role);
            }
          }
        }
        // Cache results once — permissions don't change during the session.
        _canEditStatus = _canEdit('status');
        _canEditAmount = _canEdit('total_amount');
        _canEditQty = _canEdit('total_qty');
        permissionsLoaded.value = true;
      }
    } catch (_) {}
  }

  bool _canEdit(String fieldName) {
    if (_authController.hasRole('System Manager')) return true;
    final level = _fieldLevels[fieldName] ?? 0;
    final allowed = _levelWriteRoles[level] ?? {};
    return _authController.hasAnyRole(allowed.toList());
  }

  // Public getters so the UI reads the cached values.
  bool get canEditStatus => _canEditStatus;
  bool get canEditAmount => _canEditAmount;
  bool get canEditQty => _canEditQty;

  // Keep old method name for any other callers.
  bool canEdit(String fieldName) => _canEdit(fieldName);

  // ── Save ───────────────────────────────────────────────────────────────────

  @override
  Future<void> reloadDocument() async {
    await fetchPosUpload();
    GlobalSnackbar.success(message: 'Document reloaded successfully');
  }

  Future<void> updatePosUpload(Map<String, dynamic> data) async {
    if (isSaving.value) return;
    if (checkStaleAndBlock()) return;
    isSaving.value = true;
    if (posUpload.value?.modified != null) {
      data['modified'] = posUpload.value!.modified;
    }
    try {
      final response = await _provider.updatePosUpload(name, data);
      if (response.statusCode == 200) {
        GlobalSnackbar.success(message: 'POS Upload updated successfully');
        await fetchPosUpload();
      } else {
        GlobalSnackbar.error(message: 'Failed to update POS Upload');
      }
    } catch (e) {
      if (handleVersionConflict(e)) return;
      GlobalSnackbar.error(message: 'Update failed: $e');
    } finally {
      isSaving.value = false;
    }
  }
}
