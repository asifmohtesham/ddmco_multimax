import 'package:get/get.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

/// Which linked document type was resolved for this POS Upload.
enum LinkedDocType { deliveryNote, stockEntry, none }

class PosUploadFormController extends GetxController
    with OptimisticLockingMixin {
  final PosUploadProvider _provider = Get.find<PosUploadProvider>();
  final DeliveryNoteProvider _dnProvider = Get.find<DeliveryNoteProvider>();
  final StockEntryProvider _seProvider = Get.find<StockEntryProvider>();
  final AuthenticationController _authController =
      Get.find<AuthenticationController>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  // ── Core state ────────────────────────────────────────────────────────────
  var isLoading = true.obs;
  var isSaving = false.obs;
  var posUpload = Rx<PosUpload?>(null);

  // ── Search / filter ───────────────────────────────────────────────────────
  var searchQuery = ''.obs;
  var filteredItems = <PosUploadItem>[].obs;

  // ── Linked document progress ──────────────────────────────────────────────
  /// Type of linked document resolved (or none).
  var linkedDocType = LinkedDocType.none.obs;

  /// Name of the linked Delivery Note or Stock Entry.
  var linkedDocName = ''.obs;

  /// Loading state while fetching the linked document.
  var isLoadingLinked = false.obs;

  /// Map of PosUploadItem.idx  →  custom_invoice_serial_number from the
  /// matched DN/SE item.  Empty string means the row was found but has no
  /// serial.  Null key means no match.
  final resolvedSerials = <int, String?>{}.obs;

  // ── Permissions ───────────────────────────────────────────────────────────
  final Map<String, int> _fieldLevels = {};
  final Map<int, Set<String>> _levelWriteRoles = {};
  var permissionsLoaded = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadData();
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    isLoading.value = true;
    await Future.wait([
      fetchPosUpload(),
      fetchDocTypePermissions(),
    ]);
    isLoading.value = false;
    // After core data is loaded, kick off linked-document fetch in background.
    fetchLinkedDocument();
  }

  // ── POS Upload ────────────────────────────────────────────────────────────

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

  // ── Linked document (DN or SE) ────────────────────────────────────────────

  /// Determines the linked doctype from the POS Upload name prefix and fetches
  /// the referenced document, then builds the [resolvedSerials] map.
  Future<void> fetchLinkedDocument() async {
    final upload = posUpload.value;
    if (upload == null) return;

    final prefix = name.length >= 2 ? name.substring(0, 2).toUpperCase() : '';

    if (prefix == 'ML' || prefix == 'KA') {
      await _fetchDeliveryNote(upload);
    } else if (prefix == 'MX' || prefix == 'KX') {
      await _fetchStockEntry(upload);
    }
    // Any other prefix → linkedDocType stays .none, no progress shown.
  }

  Future<void> _fetchDeliveryNote(PosUpload upload) async {
    isLoadingLinked.value = true;
    linkedDocType.value = LinkedDocType.deliveryNote;
    try {
      // Find a DN whose po_no matches this POS Upload's name.
      final listResp = await _dnProvider.getDeliveryNotes(
        limit: 1,
        filters: {'po_no': name},
      );
      if (listResp.statusCode == 200 &&
          (listResp.data['data'] as List?)?.isNotEmpty == true) {
        final dnName =
            (listResp.data['data'] as List).first['name'].toString();
        linkedDocName.value = dnName;

        // Fetch full document with items.
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

  Future<void> _fetchStockEntry(PosUpload upload) async {
    isLoadingLinked.value = true;
    linkedDocType.value = LinkedDocType.stockEntry;
    try {
      // Find a SE whose custom_reference_no matches this POS Upload's name.
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
                .firstWhereOrNull((i) =>
                    // StockEntryItem.idx is not modelled; match by list position
                    se.items.indexOf(i) + 1 == idx)
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

  /// Populates [resolvedSerials] by mapping each [PosUploadItem.idx] to the
  /// `custom_invoice_serial_number` returned by [matchSerial].  A null return
  /// from [matchSerial] means no matching row was found in the linked doc.
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

  // ── Search ────────────────────────────────────────────────────────────────

  void filterItems(String query) {
    searchQuery.value = query;
    if (query.isEmpty) {
      filteredItems.assignAll(posUpload.value?.items ?? []);
    } else {
      filteredItems.value = posUpload.value?.items
              .where((item) =>
                  item.itemName.toLowerCase().contains(query.toLowerCase()))
              .toList() ??
          [];
    }
  }

  // ── Permissions ───────────────────────────────────────────────────────────

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

  // ── Save ──────────────────────────────────────────────────────────────────

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
