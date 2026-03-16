import 'package:get/get.dart';
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

/// Linked document type resolved from the POS Upload name prefix.
enum LinkedDocType { deliveryNote, stockEntry, none }

/// Packing Slip info associated with a single POS Upload item (by idx).
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

  // ── Linked document (DN or SE) ─────────────────────────────────────────────
  var linkedDocType = LinkedDocType.none.obs;
  var linkedDocName = ''.obs;
  var isLoadingLinked = false.obs;

  /// idx → custom_invoice_serial_number from DN/SE item (null = no match found)
  final resolvedSerials = <int, String?>{}.obs;

  // ── Packing Slip layer (ML/KA only) ────────────────────────────────────────
  var isLoadingPackingSlips = false.obs;

  /// idx → PackingSlipInfo from the PS whose item has matching
  /// custom_invoice_serial_number.  Null value = serial not found in any PS.
  final resolvedPackingSlips = <int, PackingSlipInfo?>{}.obs;

  /// All Packing Slips fetched for the linked DN (used for the summary count).
  final packingSlips = <PackingSlip>[].obs;

  // ── Permissions ────────────────────────────────────────────────────────────
  final Map<String, int> _fieldLevels = {};
  final Map<int, Set<String>> _levelWriteRoles = {};
  var permissionsLoaded = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadData();
  }

  // ── Initialisation ─────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    isLoading.value = true;
    await Future.wait([
      fetchPosUpload(),
      fetchDocTypePermissions(),
    ]);
    isLoading.value = false;
    // Kick off linked-document fetch without blocking the screen render.
    fetchLinkedDocument();
  }

  // ── POS Upload ─────────────────────────────────────────────────────────────

  Future<void> fetchPosUpload() async {
    try {
      final response = await _provider.getPosUpload(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        posUpload.value = PosUpload.fromJson(response.data['data']);
        filteredItems.assignAll(posUpload.value!.items);
      } else {
        GlobalSnackbar.error(message: 'Failed to fetch POS upload');
      }
    } catch (e) {
      GlobalSnackbar.error(message: e.toString());
    }
  }

  // ── Linked document (DN or SE) ─────────────────────────────────────────────

  Future<void> fetchLinkedDocument() async {
    final upload = posUpload.value;
    if (upload == null) return;

    final prefix =
        name.length >= 2 ? name.substring(0, 2).toUpperCase() : '';

    if (prefix == 'ML' || prefix == 'KA') {
      await _fetchDeliveryNote(upload);
    } else if (prefix == 'MX' || prefix == 'KX') {
      await _fetchStockEntry(upload);
      // Packing Slip step is irrelevant for MX/KX — stop here.
    }
  }

  Future<void> _fetchDeliveryNote(PosUpload upload) async {
    isLoadingLinked.value = true;
    linkedDocType.value = LinkedDocType.deliveryNote;
    try {
      final listResp = await _dnProvider.getDeliveryNotes(
        limit: 1,
        filters: {'po_no': name},
      );
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
        // Now fetch Packing Slips for this DN.
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
        limit: 1,
        filters: {'custom_reference_no': name},
      );
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

  /// Fetches all Packing Slips for [dnName], then for every POS Upload item
  /// looks up the PS whose items contain a matching
  /// `custom_invoice_serial_number` == the resolved serial for that idx.
  Future<void> _fetchPackingSlips(
      PosUpload upload, String dnName) async {
    isLoadingPackingSlips.value = true;
    try {
      // Fetch all PS headers + items for this DN in parallel pages.
      // Limit 0 = fetch all.
      final listResp = await _psProvider.getPackingSlips(
        limit: 0,
        filters: {'delivery_note': dnName},
        orderBy: 'from_case_no asc',
      );

      if (listResp.statusCode != 200) return;
      final psList = listResp.data['data'] as List? ?? [];
      if (psList.isEmpty) return;

      // Fetch each PS detail (with items) in parallel.
      final futures = psList
          .map((ps) => _psProvider.getPackingSlip(ps['name'].toString()))
          .toList();
      final responses = await Future.wait(futures);

      final slips = <PackingSlip>[];
      for (final resp in responses) {
        if (resp.statusCode == 200 && resp.data['data'] != null) {
          slips.add(PackingSlip.fromJson(resp.data['data']));
        }
      }
      packingSlips.assignAll(slips);

      // Build idx → PackingSlipInfo by matching the resolved serial for each
      // POS Upload item against each PS item's custom_invoice_serial_number.
      final psMap = <int, PackingSlipInfo?>{};
      for (final item in upload.items) {
        final serial = resolvedSerials[item.idx];
        // Only attempt a PS match when the DN serial is known.
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
    } catch (_) {
      // Non-fatal; PS data is supplementary.
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

  // ── Search ─────────────────────────────────────────────────────────────────

  void filterItems(String query) {
    searchQuery.value = query;
    if (query.isEmpty) {
      filteredItems.assignAll(posUpload.value?.items ?? []);
    } else {
      filteredItems.value = posUpload.value?.items
              .where((item) => item.itemName
                  .toLowerCase()
                  .contains(query.toLowerCase()))
              .toList() ??
          [];
    }
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
        permissionsLoaded.value = true;
      }
    } catch (_) {}
  }

  bool canEdit(String fieldName) {
    if (_authController.hasRole('System Manager')) return true;
    final level = _fieldLevels[fieldName] ?? 0;
    final allowed = _levelWriteRoles[level] ?? {};
    return _authController.hasAnyRole(allowed.toList());
  }

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
        fetchPosUpload();
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
