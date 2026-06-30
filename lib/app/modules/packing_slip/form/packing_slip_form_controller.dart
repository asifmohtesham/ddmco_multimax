import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/data/providers/packing_slip_provider.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/mixins/realtime_sync_mixin.dart';
import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_invoice_serial_number_field.dart';
import 'package:multimax/app/modules/packing_slip/form/dn_scan_item_matcher.dart';
import 'package:multimax/app/modules/packing_slip/form/ps_serial_balance.dart';
import 'package:multimax/app/modules/packing_slip/form/ps_serial_options.dart';
import 'package:multimax/app/modules/packing_slip/form/ps_dn_reference_resolver.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_item_form_controller.dart';
import 'package:multimax/app/modules/packing_slip/form/widgets/packing_slip_item_form_sheet.dart'
    show BatchDisplayTile;
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';

class PackingSlipFormController extends GetxController
    with OptimisticLockingMixin, RealtimeSyncMixin {
  final PackingSlipProvider  _provider              = Get.find<PackingSlipProvider>();
  final DeliveryNoteProvider _deliveryNoteProvider  = Get.find<DeliveryNoteProvider>();
  final PosUploadProvider    _posUploadProvider     = Get.find<PosUploadProvider>();
  final ApiProvider          _apiProvider           = Get.find<ApiProvider>();
  final StorageService       _storageService        = Get.find<StorageService>();
  final DataWedgeService     _dataWedgeService      = Get.find<DataWedgeService>();
  final ScanService          _scanService           = Get.find<ScanService>();

  var itemFormKey = GlobalKey<FormState>();
  String name = Get.arguments['name'];
  String mode = Get.arguments['mode'];

  @override String get realtimeDoctype => 'Packing Slip';
  @override String get realtimeDocname => name;

  var isLoading    = true.obs;
  @override var isSaving     = false.obs;
  var isScanning   = false.obs;
  @override var isDirty      = false.obs;
  var saveResult     = SaveResult.idle.obs;
  Timer? _saveResultTimer;

  void _setSaveResult(SaveResult result) {
    _saveResultTimer?.cancel();
    saveResult.value = result;
    _saveResultTimer = Timer(const Duration(seconds: 2), () {
      saveResult.value = SaveResult.idle;
    });
  }

  var isAddingItem = false.obs;
  String _originalJson = '';

  // ── EAN scan context ──────────────────────────────────────────────────────
  String currentScannedEan = '';

  // bsQtyController and bsMaxQty kept as shims until step-6.
  var bsMaxQty  = 0.0.obs;
  // isSheetValid shim kept until step-6.
  var isSheetValid = false.obs;

  var packingSlip        = Rx<PackingSlip?>(null);
  var linkedDeliveryNote = Rx<DeliveryNote?>(null);
  var posUpload          = Rx<PosUpload?>(null);

  var relatedPackingSlips = <PackingSlip>[].obs;

  final TextEditingController barcodeController = TextEditingController();

  var expandedInvoice = ''.obs;

  var isEditing = false.obs;

  var itemFilter = ''.obs;

  var isItemSheetOpen = false.obs;

  var isLoadingItemEdit  = false.obs;
  var loadingForItemName = RxnString();

  String? currentItemDnDetail;
  String? currentItemCode;
  String? currentItemName;
  String? currentBatchNo;
  String? currentUom;
  String? currentSerial;
  double? currentNetWeight;
  double? currentWeightUom;
  String? currentItemNameKey;

  /// Batch from the scan result that opened the sheet; null for tap-to-add.
  /// Narrows the serial options to rows of the scanned batch.
  String? currentScannedBatch;

  /// Reactive batch for the sheet's BatchDisplayTile — re-seeded when the
  /// sheet is re-targeted to a different serial's DN row.
  final bsBatchNo = RxnString();

  // Metadata shims kept until step-6.
  var bsItemOwner      = RxnString();

  // DataWedge hardware-scan worker.
  Worker? _scanWorker;

  bool get scanWorkerActive => _scanWorker != null;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
    _scanWorker = ever(_dataWedgeService.scannedCode, (String code) {
      if (code.isNotEmpty) {
        scanBarcode(code);
      }
    });

    if (mode == 'new') {
      _initNewPackingSlip();
    } else {
      fetchDocument().then((_) => initRealtimeSync());
    }
  }

  @override
  void onClose() {
    disposeRealtimeSync();
    _scanWorker?.dispose();
    _saveResultTimer?.cancel();
    barcodeController.dispose();
    super.onClose();
  }

  // ── Sheet validation predicates ────────────────────────────────────────────
  // Each function answers exactly one question about validity.
  // Returns true when the sheet should be considered INVALID for that reason.

  /// Returns true when the qty text is unparseable or zero / negative.
  bool _isQtyInvalid(String text) {
    final qty = double.tryParse(text);
    return qty == null || qty <= 0;
  }

  // ---------------------------------------------------------------------------
  // Pop / discard
  // ---------------------------------------------------------------------------

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Document init / fetch
  // ---------------------------------------------------------------------------

  // ── New-document argument extraction ───────────────────────────────────────

  /// Reads and coerces the route arguments required to bootstrap a new
  /// Packing Slip. Single responsibility: argument access and type coercion.
  /// No side effects.
  ({String dnName, String? customPoNo, int nextCaseNo}) _extractNewSlipArgs() => (
  dnName:     Get.arguments['deliveryNote'] as String? ?? '',
  customPoNo: Get.arguments['customPoNo']  as String?,
  nextCaseNo: Get.arguments['nextCaseNo']  as int? ?? 1,
  );

  // ── New-document construction ───────────────────────────────────────────────

  /// Builds the initial [PackingSlip] scaffold for a new document.
  /// Single responsibility: field mapping. Receives all values as
  /// parameters so it is pure and independently testable.
  PackingSlip _buildNewPackingSlip({
    required String  dnName,
    required int     nextCaseNo,
    String?          customPoNo,
  }) =>
      PackingSlip(
        name:         'New Packing Slip',
        deliveryNote: dnName,
        modified:     '',
        creation:     DateTime.now().toString(),
        docstatus:    0,
        status:       'Draft',
        customPoNo:   customPoNo,
        fromCaseNo:   nextCaseNo,
        toCaseNo:     nextCaseNo,
        items:        [],
        customer:     '',
      );

  // ── New-document dirty state reset ─────────────────────────────────────────

  /// Marks the controller as dirty with no saved baseline.
  /// Semantically distinct from [_updateOriginalState] (which records a
  /// fetched/saved document). A new document has no original to compare
  /// against, so the snapshot is explicitly empty.
  void _resetDirtyStateForNewDocument() {
    _originalJson = '';
    isDirty.value = true;
  }

  // ── Linked-document side-effect trigger ────────────────────────────────────

  /// Triggers async fetches for all documents that are linked to [dnName].
  /// Guard (isNotEmpty) is owned here so [_initNewPackingSlip] reads as
  /// pure policy: "if we have a DN, load its dependents."
  void _fetchLinkedDocumentsIfPresent(String dnName) {
    if (dnName.isEmpty) return;
    fetchLinkedDeliveryNote(dnName);
    fetchRelatedPackingSlips(dnName);
  }

  // ── Orchestrator ───────────────────────────────────────────────────────────

  void _initNewPackingSlip() {
    isLoading.value = true;
    final (:dnName, :customPoNo, :nextCaseNo) = _extractNewSlipArgs();
    packingSlip.value = _buildNewPackingSlip(
      dnName:     dnName,
      nextCaseNo: nextCaseNo,
      customPoNo: customPoNo,
    );
    _resetDirtyStateForNewDocument();
    _fetchLinkedDocumentsIfPresent(dnName);
    isLoading.value = false;
  }

  // ── Response validation ────────────────────────────────────────────────────

  /// Returns true when [response] carries a valid, non-null data payload.
  /// Single responsibility: success-gate check, reusable across all fetch
  /// methods (fetchLinkedDeliveryNote, fetchRelatedPackingSlips, fetchPosUpload).
  bool _isSuccessResponse(Response response) =>
      response.statusCode == 200 && response.data['data'] != null;

  // ── Document hydration ─────────────────────────────────────────────────────

  /// Deserialises the raw API map into a [PackingSlip], writes it to the
  /// reactive [packingSlip] observable, and anchors the clean-state snapshot.
  /// Single responsibility: reactive state population for a fetched document.
  void _hydratePackingSlip(Map<String, dynamic> data) {
    final slip = PackingSlip.fromJson(data);
    packingSlip.value = slip;
    _updateOriginalState(slip);
  }

  // ── Fetch error handlers ───────────────────────────────────────────────────

  /// Called when the server responds but the payload is missing or status
  /// is non-200. Distinct from a network/exception failure.
  void _onFetchPackingSlipBadResponse() =>
      GlobalSnackbar.error(message: 'Failed to fetch packing slip details');

  /// Called when an exception is thrown during the fetch (network error,
  /// timeout, parse failure). Receives the raw error for diagnostics.
  void _onFetchPackingSlipError(Object e) =>
      GlobalSnackbar.error(message: 'Failed to load data: ${e.toString()}');

  // ── Orchestrator ───────────────────────────────────────────────────────────

  Future<void> fetchDocument() async {
    isLoading.value = true;
    try {
      final response = await _provider.getPackingSlip(name);
      if (_isSuccessResponse(response)) {
        _hydratePackingSlip(response.data['data']);
        _fetchLinkedDocumentsIfPresent(packingSlip.value!.deliveryNote);
      } else {
        _onFetchPackingSlipBadResponse();
      }
    } catch (e) {
      _onFetchPackingSlipError(e);
    } finally {
      isLoading.value = false;
    }
  }

  // ── DN hydration ───────────────────────────────────────────────────────────

  /// Deserialises the raw API map into a [DeliveryNote] and writes it to the
  /// [linkedDeliveryNote] observable.
  /// Single responsibility: reactive state population for the linked DN.
  void _hydrateLinkedDeliveryNote(Map<String, dynamic> data) {
    linkedDeliveryNote.value = DeliveryNote.fromJson(data);
  }

  // ── POS Upload side-effect trigger ─────────────────────────────────────────

  /// Triggers [fetchPosUpload] when the given [DeliveryNote] carries a
  /// non-empty PO number.
  /// Single responsibility: POS Upload conditional fetch guard.
  void _fetchPosUploadIfPresent(DeliveryNote dn) {
    if (dn.poNo != null && dn.poNo!.isNotEmpty) fetchPosUpload(dn.poNo!);
  }

  // ── Customer back-fill ─────────────────────────────────────────────────────

  /// Copies the DN customer onto the current packing slip when the slip has
  /// no customer set yet.
  ///
  /// Also re-anchors the clean-state snapshot for edit-mode documents so
  /// the back-fill is not treated as a dirty change by [_checkForChanges].
  ///
  /// Single responsibility: customer field propagation from linked DN to slip.
  /// Two distinct invariants owned here:
  ///   1. Only back-fill when slip.customer is null or empty.
  ///   2. Only re-anchor the snapshot when not in new-document mode.
  void _backfillCustomerFromDn(DeliveryNote dn) {
    final slip = packingSlip.value;
    if (slip == null) return;
    final customerMissing =
        slip.customer == null || slip.customer!.isEmpty;
    if (!customerMissing) return;
    packingSlip.value = slip.copyWith(customer: dn.customer);
    if (mode != 'new') _updateOriginalState(packingSlip.value!);
  }

  // ── dn_detail refresh ─────────────────────────────────────────────────────

  /// Ensures every in-memory packing slip item has a [dnDetail] that
  /// corresponds to an actual row in the just-loaded [dn].
  ///
  /// Two cases are handled:
  ///   • **Empty** – the Frappe REST API returned [dn_detail] as null (e.g.
  ///     field-permission restriction).  Stored as '' by [PackingSlipItem.fromJson].
  ///   • **Stale** – the stored value is non-empty but no longer exists as a
  ///     row name in [dn] (e.g. the DN was amended and items were re-keyed).
  ///     Frappe silently clears stale Link values during document hydration, so
  ///     [validate_items] receives null and throws "Row N: Please provide a
  ///     valid Delivery Note Item reference."
  ///
  /// A [dnDetail] is considered **valid** if it appears in the set of names
  /// returned by the current DN GET response. If it is missing or stale we
  /// attempt an unambiguous re-match using:
  ///   1. [itemCode] equals the slip item's [itemCode].
  ///   2. [customInvoiceSerialNumber] (or sentinel '0') matches.
  ///   3. [batchNo] matches when the slip item carries a non-empty batch.
  ///
  /// Intentionally does NOT call [_updateOriginalState] after patching — the
  /// corrected values ride along on the next user-triggered save, keeping the
  /// dirty-state logic intact.
  void _refreshDnDetails(DeliveryNote dn) {
    final slip = packingSlip.value;
    if (slip == null) return;

    final result = resolveDnReferences(
      slipItems:    slip.items,
      dnItems:      dn.items,
      remainingQty: _calcRemainingQtyForDnItem,
    );

    if (result.fixed > 0) {
      packingSlip.value = slip.copyWith(items: result.items);
      _checkForChanges();
    }
  }

  // ── DN-reference validity (Items-tab indicator) ────────────────────────────

  /// Names of the linked DN's item rows that are valid link targets.
  Set<String> get _validDnNames =>
      validDnItemNames(linkedDeliveryNote.value?.items ?? const []);

  /// Slip rows whose `dn_detail` is empty or stale (would block ERPNext submit).
  /// Empty while the linked DN is not loaded — validity is unknown then.
  List<PackingSlipItem> get unlinkedItems {
    if (linkedDeliveryNote.value == null) return const [];
    final names = _validDnNames;
    return packingSlip.value?.items
            .where((i) => !isSlipItemLinked(i, names))
            .toList() ??
        const [];
  }

  /// Reactive validity status consumed by [PackingSlipDnLinkBanner].
  DnRefStatus get dnRefStatus => computeDnRefStatus(
        items:      packingSlip.value?.items ?? const [],
        validNames: _validDnNames,
        dnLoaded:   linkedDeliveryNote.value != null,
      );

  // ── User-triggered reference resolution ────────────────────────────────────

  /// Re-matches orphaned `dn_detail` references and persists the slip so it
  /// becomes immediately submittable in ERPNext. Guarded to draft documents
  /// with a loaded Delivery Note.
  Future<void> resolveDnReferencesAndSave() async {
    final dn   = linkedDeliveryNote.value;
    final slip = packingSlip.value;
    if (dn == null || slip == null) {
      GlobalSnackbar.error(message: 'Delivery Note not loaded yet.');
      return;
    }
    if (slip.docstatus != 0) return;

    final result = resolveDnReferences(
      slipItems:    slip.items,
      dnItems:      dn.items,
      remainingQty: _calcRemainingQtyForDnItem,
    );

    if (result.fixed > 0) {
      packingSlip.value = slip.copyWith(items: result.items);
      _checkForChanges();
      if (isDirty.value) await saveDocument();
    }

    // saveDocument() swallows errors and shows its own snackbar; if the patch
    // failed to persist, isDirty stays true — suppress the success message so
    // the user isn't told the links were saved when they weren't.
    final saveFailed = result.fixed > 0 && isDirty.value;
    if (!saveFailed) {
      _announceResolveResult(result.fixed, result.unresolved);
    }
  }

  /// Surfaces the outcome of [resolveDnReferencesAndSave] as a snackbar.
  void _announceResolveResult(int fixed, int unresolved) {
    if (fixed == 0 && unresolved == 0) {
      GlobalSnackbar.info(
          message: 'All items already linked to the Delivery Note.');
      return;
    }
    final parts = <String>[];
    if (fixed > 0) parts.add('Linked $fixed item(s) to the Delivery Note');
    if (unresolved > 0) {
      parts.add('$unresolved could not be matched — remove them to proceed');
    }
    final msg = parts.join('. ');
    if (unresolved > 0) {
      GlobalSnackbar.warning(message: msg);
    } else {
      GlobalSnackbar.success(message: msg);
    }
  }

  // ── Fetch error handler ────────────────────────────────────────────────────

  /// Called when an exception is thrown during the linked DN fetch.
  /// Logs silently — a missing linked DN is non-fatal; the slip can still
  /// be viewed without its DN context.
  void _onFetchLinkedDeliveryNoteError(Object e) =>
      log('Failed to fetch linked DN: $e');

  // ── Orchestrator ───────────────────────────────────────────────────────────

  Future<void> fetchLinkedDeliveryNote(String dnName) async {
    try {
      final response = await _deliveryNoteProvider.getDeliveryNote(dnName);
      if (_isSuccessResponse(response)) {
        _hydrateLinkedDeliveryNote(response.data['data']);
        _fetchPosUploadIfPresent(linkedDeliveryNote.value!);
        _backfillCustomerFromDn(linkedDeliveryNote.value!);
        _refreshDnDetails(linkedDeliveryNote.value!);
      }
    } catch (e) {
      _onFetchLinkedDeliveryNoteError(e);
    }
  }

  Future<void> fetchPosUpload(String posName) async {
    try {
      final response = await _posUploadProvider.getPosUpload(posName);
      if (response.statusCode == 200 && response.data['data'] != null) {
        posUpload.value = PosUpload.fromJson(response.data['data']);
      }
    } catch (e) {
      log('Failed to fetch linked POS Upload: $e');
    }
  }

  Future<void> fetchRelatedPackingSlips(String dnName) async {
    try {
      final response = await _provider.getPackingSlips(
        limit: 1000,
        filters: {'delivery_note': dnName},
      );
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        relatedPackingSlips.value =
            data.map((json) => PackingSlip.fromJson(json)).toList();
      }
    } catch (e) {
      log('Failed to fetch related packing slips: $e');
    }
  }

  void _updateOriginalState(PackingSlip slip) {
    _originalJson = jsonEncode(slip.toJson());
    isDirty.value = false;
  }

  void _checkForChanges() {
    if (packingSlip.value == null) return;
    if (mode == 'new') { isDirty.value = true; scheduleAutoSave(); return; }
    final currentJson = jsonEncode(packingSlip.value!.toJson());
    isDirty.value = currentJson != _originalJson;
    if (isDirty.value) scheduleAutoSave();
  }

  // ── POS qty cap helpers ────────────────────────────────────────────────────

  /// Returns true when no POS Upload document is currently loaded.
  ///
  /// When the upload is absent the quantity cap is undefined — callers that
  /// need a numeric sentinel should return [double.infinity] (no ceiling).
  bool _isPosUploadAbsent() => posUpload.value == null;

  /// Converts an invoice serial number string to its integer index.
  ///
  /// Returns `null` when [serial] cannot be parsed as an integer, which
  /// indicates the serial does not map to any [PosUploadItem].
  int? _serialToIdx(String serial) => int.tryParse(serial);

  /// Looks up the quantity for the [PosUploadItem] matching [idx].
  ///
  /// Returns `0.0` when no item with that index exists in the loaded upload,
  /// treating an unmatched serial as a zero-quantity line rather than an
  /// uncapped one. This distinguishes "item exists but is zero" from
  /// "no upload loaded" ([double.infinity]).
  double _posItemQtyForIdx(int idx) {
    final item = posUpload.value!.items.firstWhereOrNull((i) => i.idx == idx);
    return item?.quantity?.toDouble() ?? 0.0;
  }

  // ── Public cap resolver ────────────────────────────────────────────────────

  /// Returns the POS Upload quantity cap for the given invoice [serial] number.
  ///
  /// Resolution chain:
  ///   1. If no POS Upload is loaded → [double.infinity] (no ceiling; the
  ///      [SharedInvoiceSerialNumberField] badge is hidden in this state).
  ///   2. If [serial] cannot be parsed as an integer index → `0.0` (the serial
  ///      does not correspond to any POS Upload line).
  ///   3. Otherwise → the matched [PosUploadItem.quantity] as a [double], or
  ///      `0.0` if no item with that index exists.
  ///
  /// The two zero-returning branches are semantically distinct:
  ///   - An unparseable serial means the data is malformed.
  ///   - A matched-but-zero (or unmatched) item means the line is exhausted.
  /// Both safely prevent over-packing.
  double posQtyCapForSerial(String serial) {
    if (_isPosUploadAbsent()) return double.infinity;
    final idx = _serialToIdx(serial);
    if (idx == null) return 0.0;
    return _posItemQtyForIdx(idx);
  }

  // ── Multi-serial sheet options ─────────────────────────────────────────────

  /// Ordered serial options for the open item sheet — one per invoice serial
  /// whose DN row matches the current item (and scanned batch, when present).
  ///
  /// In edit mode the row being edited is excluded from "packed" so its own
  /// qty does not mark its serial Full (mirrors the DN dropdown semantics).
  List<PsSerialOption> serialOptionsForSheet() {
    final dn = linkedDeliveryNote.value;
    final code = currentItemCode;
    if (dn == null || code == null) return const [];
    return buildPsSerialOptions(
      items: dn.items,
      code: code,
      batch: currentScannedBatch,
      remainingQty: (row) => _calcRemainingQtyForDnItem(
        row,
        excludeSlipItemName: isEditing.value ? currentItemNameKey : null,
      ),
    );
  }

  /// Re-seeds the open add-mode sheet session to [serial]'s DN row:
  /// dnDetail, batch, uom, serial context, and the qty cap. The child
  /// controller re-prefills its qty field afterwards.
  void retargetSheetToSerial(String serial) {
    final option = serialOptionsForSheet()
        .firstWhereOrNull((o) => o.serial == serial);
    if (option == null) return;
    _populateItemDetails(option.dnRow);
    bsMaxQty.value = option.remaining;
  }

  // ---------------------------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------------------------

  void toggleInvoiceExpand(String key) =>
      expandedInvoice.value = expandedInvoice.value == key ? '' : key;

  void setFilter(String filter) => itemFilter.value = filter;

  // ---------------------------------------------------------------------------
  // Grouping & counting
  // ---------------------------------------------------------------------------

  Map<String, List<PackingSlipItem>> get groupedItems {
    if (packingSlip.value == null || packingSlip.value!.items.isEmpty) return {};
    return groupBy(packingSlip.value!.items,
        (PackingSlipItem item) => item.customInvoiceSerialNumber ?? '0');
  }

  List<String> get _allDnSerials {
    if (linkedDeliveryNote.value == null) return [];
    return linkedDeliveryNote.value!.items
        .map((i) => i.customInvoiceSerialNumber ?? '0')
        .toSet()
        .toList()
      ..sort((a, b) {
        final intA = int.tryParse(a) ?? 9999;
        final intB = int.tryParse(b) ?? 9999;
        return intA.compareTo(intB);
      });
  }

  String getPosItemName(String serial) {
    if (posUpload.value == null) return '';
    final int idx = int.tryParse(serial) ?? 0;
    final item =
        posUpload.value!.items.firstWhereOrNull((i) => i.idx == idx);
    return item?.itemName ?? '';
  }

  List<DeliveryNoteItem> getDnItemsForSerial(String serial) {
    if (linkedDeliveryNote.value == null) return [];
    return linkedDeliveryNote.value!.items
        .where((item) => (item.customInvoiceSerialNumber ?? '0') == serial)
        .toList();
  }

  double getTotalDnQtyForSerial(String serial) {
    if (linkedDeliveryNote.value == null) return 0.0;
    return linkedDeliveryNote.value!.items
        .where((item) => (item.customInvoiceSerialNumber ?? '0') == serial)
        .fold(0.0, (sum, item) => sum + item.qty);
  }

  double getPackedQtyForDnItem(String? dnDetail) {
    if (dnDetail == null) return 0.0;
    double total = 0.0;
    final currentSlipName = packingSlip.value?.name;
    for (var slip in relatedPackingSlips) {
      if (slip.name == currentSlipName) continue;
      for (var i in slip.items) {
        if (i.dnDetail == dnDetail) total += i.qty;
      }
    }
    for (var i in (packingSlip.value?.items ?? [])) {
      if (i.dnDetail == dnDetail) total += i.qty;
    }
    return total;
  }

  PackingSlipItem? getCurrentSlipItem(String? dnDetail) {
    if (dnDetail == null) return null;
    return packingSlip.value?.items
        .firstWhereOrNull((i) => i.dnDetail == dnDetail);
  }

  double getGlobalPackedQty(String serial) {
    double total = 0.0;
    final currentSlipName = packingSlip.value?.name;
    for (var slip in relatedPackingSlips) {
      if (slip.name == currentSlipName) continue;
      for (var i in slip.items) {
        if ((i.customInvoiceSerialNumber ?? '0') == serial) total += i.qty;
      }
    }
    for (var i in (packingSlip.value?.items ?? [])) {
      if ((i.customInvoiceSerialNumber ?? '0') == serial) total += i.qty;
    }
    return total;
  }

  int get allCount       => _allDnSerials.length;
  int get pendingCount   =>
      _allDnSerials.where((s) => getGlobalPackedQty(s) < getTotalDnQtyForSerial(s)).length;
  int get completedCount =>
      _allDnSerials.where((s) => getGlobalPackedQty(s) >= getTotalDnQtyForSerial(s)).length;

  List<String> get visibleGroupKeys {
    final serials = _allDnSerials;
    final filter  = itemFilter.value;
    if (filter == 'All' || filter.isEmpty) return serials;
    return serials.where((s) {
      final required = getTotalDnQtyForSerial(s);
      final packed   = getGlobalPackedQty(s);
      if (filter == 'Pending')   return packed < required;
      if (filter == 'Completed') return packed >= required;
      return true;
    }).toList();
  }

  double? getRequiredQty(String dnDetail) {
    if (linkedDeliveryNote.value == null) return null;
    return linkedDeliveryNote.value!.items
        .firstWhereOrNull((e) => e.name == dnDetail)
        ?.qty;
  }

  // ---------------------------------------------------------------------------
  // Optimistic-lock reload
  // ---------------------------------------------------------------------------

  @override
  Future<void> reloadDocument() async {
    await fetchDocument();
    GlobalSnackbar.success(message: 'Document reloaded successfully');
  }

  // ── Pre-scan header validation ──────────────────────────────────────────────

  /// Returns true when the header is in a valid state to process a scan.
  ///
  /// The linked Delivery Note must be loaded before any item can be resolved
  /// and added to the slip. Shows an error snackbar and returns false when
  /// the precondition is not met.
  ///
  /// Mirrors [StockEntryFormController._validateHeaderBeforeScan] and
  /// [DeliveryNoteFormController._validateHeaderBeforeScan].
  bool _validateHeaderBeforeScan() {
    if (linkedDeliveryNote.value == null) {
      GlobalSnackbar.error(message: 'Delivery Note not loaded yet.');
      return false;
    }
    return true;
  }

  // ── Scan result handlers ───────────────────────────────────────────────────

  /// Resolves a successful [ScanResult] to the matching [DeliveryNoteItem]
  /// and opens the add-item sheet.
  ///
  /// Mirrors [DeliveryNoteFormController._handleScanResult]: sets the EAN
  /// context field, then delegates to the sheet opener.
  /// Single responsibility: success-path routing after a resolved scan.
  Future<void> _handleScanResult(ScanResult result) async {
    currentScannedEan = result.rawCode ?? '';
    final match = _findItemInDN(
      result.itemData!.itemCode,
      result.batchNo,
    );
    if (match != null) {
      prepareSheetForAdd(match, scannedBatch: result.batchNo);
    } else {
      final code = result.itemData!.itemCode;
      final batch = result.batchNo;
      final dnItems = linkedDeliveryNote.value?.items ?? const [];
      // This predicate mirrors findScannedDnItem's code/batch filter (minus
      // skipRow/remainingQty), so a null match here means "matches existed but were all skipped".
      final hasAnyMatch = dnItems.any((i) =>
          i.itemCode == code && (batch == null || i.batchNo == batch));
      if (hasAnyMatch) {
        GlobalSnackbar.error(
          message:
              'All serials for $code have mismatched Strap/Buckle quantities. '
              'Packing blocked until the Delivery Note is balanced.',
        );
      } else {
        GlobalSnackbar.error(
          message: 'Item $code not found in Delivery Note or Batch mismatch.',
        );
      }
    }
  }

  /// Called when [ScanService] returns a failed or unresolvable result.
  /// Single responsibility: failure-path feedback.
  void _onScanFailed(ScanResult result) =>
      GlobalSnackbar.error(message: result.message ?? 'Scan failed');

  /// Called when an exception is thrown during scan processing.
  /// Single responsibility: exception-path feedback.
  void _onScanError(Object e) =>
      GlobalSnackbar.error(message: 'Scan processing error: $e');

  // ── Orchestrator ────────────────────────────────────────────────────────────

  /// Processes a raw barcode string from DataWedge.
  ///
  /// Guard order mirrors [StockEntryFormController.scanBarcode]:
  ///   1. Sheet-open guard (handled upstream by [_scanWorker] — sheet-level
  ///      scans are routed by the child controller's BarcodeAwareMixin).
  ///   2. Stale-document guard.
  ///   3. Empty-barcode guard.
  ///   4. Header-validity guard ([_validateHeaderBeforeScan]).
  ///
  /// Delegates barcode resolution to [ScanService.processScan] — the same
  /// path used by Stock Entry and Delivery Note — instead of manual string
  /// splitting. This ensures EAN/batch parsing rules are consistent across
  /// all form controllers.
  Future<void> scanBarcode(String barcode) async {
    if (isItemSheetOpen.value) return;
    if (checkStaleAndBlock()) return;
    if (barcode.isEmpty) return;
    if (!_validateHeaderBeforeScan()) return;

    final cleanBarcode = barcode.trim();
    isScanning.value = true;
    try {
      final result = await _scanService.processScan(cleanBarcode);
      if (result.isSuccess && result.itemData != null) {
        await _handleScanResult(result);
      } else {
        _onScanFailed(result);
      }
    } catch (e) {
      _onScanError(e);
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  /// Same item code can appear on multiple DN rows (one per invoice serial).
  /// Delegates to [findScannedDnItem] so a scan advances to the first row
  /// that still has qty remaining instead of always resolving to row #1.
  DeliveryNoteItem? _findItemInDN(String code, String? batch) {
    final dnItems = linkedDeliveryNote.value!.items;
    return findScannedDnItem(
      items:        dnItems,
      code:         code,
      batch:        batch,
      remainingQty: _calcRemainingQtyForDnItem,
      skipRow: (row) =>
          isPairedItemGroup(row.itemGroup) &&
          isSerialStrapBuckleUnbalanced(
              dnItems, row.customInvoiceSerialNumber ?? ''),
    );
  }

  // ── Serial badge predicate ─────────────────────────────────────────────────

  /// Returns true when the invoice-serial badge ([SharedInvoiceSerialNumberField])
  /// should be rendered in the item sheet.
  ///
  /// All four conditions must hold:
  ///   1. A POS Upload is loaded (the badge shows the POS qty cap).
  ///   2. [currentSerial] is non-null.
  ///   3. [currentSerial] is not empty.
  ///   4. [currentSerial] is not the sentinel value `'0'` (items with no
  ///      serial are stored as `'0'` by convention).
  bool _shouldShowSerialBadge() =>
      posUpload.value != null &&
          currentSerial != null &&
          currentSerial!.isNotEmpty &&
          currentSerial != '0';

  // ── Custom fields builder ──────────────────────────────────────────────────

  /// Builds the ordered list of custom field widgets for the item sheet.
  ///
  /// - [BatchDisplayTile] is shown when a batch number is present on the
  ///   current DN item — it is read-only, displaying the resolved batch.
  /// - [SharedInvoiceSerialNumberField] is shown only when
  ///   [_shouldShowSerialBadge] passes, providing the POS qty cap badge.
  ///
  /// Single responsibility: custom field composition. Widget identity and
  /// conditional inclusion rules are owned here; [_openItemSheet] receives
  /// a ready-made list.
  List<Widget> _buildItemSheetCustomFields(
      PackingSlipItemFormController child,
      ) {
    final fields = <Widget>[];

    // Reactive: re-targeting the sheet to another serial's DN row can change
    // (or clear) the batch — the tile follows bsBatchNo.
    fields.add(Obx(() {
      final batch = bsBatchNo.value;
      if (batch == null || batch.isEmpty) return const SizedBox.shrink();
      return BatchDisplayTile(batchNo: batch);
    }));

    if (_shouldShowSerialBadge()) {
      final serial = currentSerial!;
      fields.add(
        SharedInvoiceSerialNumberField(
          c:           child,
          accentColor: Colors.teal,
          label:       'Invoice Serial No',
          hint:        serial,
          // Read the live selection — the open-time serial is only the
          // fallback before anything is selected.
          posItemQtyOverride: () =>
              posQtyCapForSerial(child.selectedSerial.value ?? serial),
        ),
      );
    }

    return fields;
  }

  // ── Sheet presentation ─────────────────────────────────────────────────────

  /// Presents the [UniversalItemFormSheet] inside a [DraggableScrollableSheet]
  /// and awaits its dismissal.
  ///
  /// Single responsibility: sheet widget construction and bottom-sheet
  /// presentation. Receives all variable inputs as parameters so the
  /// function is free of direct state reads.
  Future<void> _presentItemSheet(
      PackingSlipItemFormController child,
      List<Widget> customFields,
      ) =>
      Get.bottomSheet(
        DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize:     0.4,
          maxChildSize:     0.95,
          expand:           false,
          builder: (context, sc) => UniversalItemFormSheet(
            key:              ValueKey(child.editingItemName.value ?? 'new'),
            controller:       child,
            scrollController: sc,
            onSubmit:         () => addItem(),
            onScan:           null,
            isSaveEnabled:    packingSlip.value?.docstatus == 0,
            customFields:     customFields,
          ),
        ),
        isScrollControlled: true,
      );

  // ── Sheet teardown ─────────────────────────────────────────────────────────

  /// Resets the sheet-open flag and removes the child controller from the
  /// GetX registry.
  ///
  /// Always called after [_presentItemSheet] resolves, regardless of how the
  /// sheet was dismissed (user swipe, submit, or auto-submit).
  /// Single responsibility: post-sheet cleanup. Mirrors the teardown pattern
  /// in [StockEntryFormController._openItemSheet] and
  /// [DeliveryNoteFormController._openItemSheet].
  void _teardownItemSheet() {
    isItemSheetOpen.value = false;
    Get.delete<PackingSlipItemFormController>();
  }

  // ── Orchestrator ───────────────────────────────────────────────────────────

  Future<void> _openItemSheet(PackingSlipItemFormController child) async {
    isItemSheetOpen.value = true;
    final customFields = _buildItemSheetCustomFields(child);
    await _presentItemSheet(child, customFields);
    _teardownItemSheet();
  }

  // ── Sheet-open guard ───────────────────────────────────────────────────────

  /// Returns true when a bottom sheet is already open and a new one must
  /// not be presented.
  ///
  /// Checks both the reactive [isItemSheetOpen] flag (owned by this
  /// controller) and [Get.isBottomSheetOpen] (the GetX global sheet state)
  /// so that sheets opened outside this controller's lifecycle are also
  /// detected.
  ///
  /// Shared by [prepareSheetForAdd] and [editItem] — both must block when
  /// a sheet is already active.
  bool _isSheetAlreadyOpen() =>
      isItemSheetOpen.value || Get.isBottomSheetOpen == true;

  // ── Add-mode session state reset ───────────────────────────────────────────

  /// Resets all session-context fields to their add-mode defaults.
  ///
  /// - [itemFormKey] is recreated so the new sheet gets a clean form state.
  /// - [isEditing] is set false — this session is an add, not an edit.
  /// - [currentItemNameKey] is cleared — no existing item is being targeted.
  /// - Metadata shims are cleared — they carry no meaning for a new item.
  /// - [_populateItemDetails] copies DN item fields into the current-item
  ///   context fields consumed by [_openItemSheet] and [addItemWithQty].
  void _resetSessionForAdd(DeliveryNoteItem item) {
    itemFormKey        = GlobalKey<FormState>();
    isEditing.value    = false;
    currentItemNameKey = null;
    bsItemOwner.value      = null;
    _populateItemDetails(item);
  }

  // ── Remaining qty calculation ──────────────────────────────────────────────

  /// Calculates the quantity remaining to be packed for the given
  /// [DeliveryNoteItem] across all related packing slips and the current slip.
  ///
  /// Algorithm:
  ///   1. Sum qty from all *other* related slips whose items reference
  ///      [item.name] as their [dnDetail].
  ///   2. Sum qty from the current slip's items that reference [item.name].
  ///   3. Subtract the total packed from the DN line qty.
  ///   4. Clamp to zero — negative remaining is treated as fully packed.
  ///
  /// Single responsibility: packed-qty aggregation and cap derivation.
  /// Used by both [prepareSheetForAdd] (full line remaining) and
  /// [editItem] (line remaining excluding the item being edited).
  double _calcRemainingQtyForDnItem(DeliveryNoteItem dnItem, {String? excludeSlipItemName}) {
    double packed = 0.0;
    final currentSlipName = packingSlip.value?.name;

    for (final slip in relatedPackingSlips) {
      if (slip.name == currentSlipName) continue;
      for (final i in slip.items) {
        if (i.dnDetail == dnItem.name) packed += i.qty;
      }
    }
    for (final i in (packingSlip.value?.items ?? [])) {
      if (i.dnDetail == dnItem.name && i.name != excludeSlipItemName) {
        packed += i.qty;
      }
    }

    final remaining = dnItem.qty - packed;
    return remaining < 0 ? 0 : remaining;
  }

  // ── Sheet qty shim seeding ─────────────────────────────────────────────────

  /// Seeds the qty shim fields ([bsQtyController], [_initialQty], [bsMaxQty])
  /// for a sheet session and fires the validation listener.
  ///
  /// [maxQty] is the computed remaining capacity for the current line.
  /// [initialQty] defaults to [maxQty] for add-mode (pre-fill with the full
  /// remaining qty) but is the existing item qty for edit-mode.
  ///
  /// Single responsibility: qty shim initialisation. Keeps the three coupled
  /// assignments and the [_validateSheetShim] trigger in one place.
  void _seedSheetQty({required double maxQty, double? initialQty}) {
    bsMaxQty.value = maxQty;
  }

  // ── Child controller wiring ────────────────────────────────────────────────

  /// Creates, initialises, and wires the auto-submit callback for a new
  /// [PackingSlipItemFormController] in add mode.
  ///
  /// Single responsibility: child controller lifecycle setup for add path.
  /// Returns the ready-to-use child so [prepareSheetForAdd] can pass it
  /// directly to [_openItemSheet].
  PackingSlipItemFormController _wireChildForAdd(DeliveryNoteItem item) {
    final child = Get.put(PackingSlipItemFormController());
    child.initialise(
      parent:    this,
      itemCode:  item.itemCode,
      itemName:  item.itemName ?? '',
      itemGroup: item.itemGroup ?? '',
      variantOf: item.customVariantOf ?? '',
    );
    child.setupAutoSubmit(onValid: _onAutoSubmitValid);
    return child;
  }

  // ── Auto-submit callback ───────────────────────────────────────────────────

  /// Callback passed to [setupAutoSubmit] for both add and edit sheet sessions.
  ///
  /// Mirrors the auto-submit wiring pattern in [StockEntryFormController]
  /// (_wireAutoSubmit). The [isAddingItem] flag prevents concurrent submits
  /// during the debounce window.
  Future<void> _onAutoSubmitValid() async {
    isAddingItem.value = true;
    await Future.delayed(const Duration(milliseconds: 500));
    await addItem();
    isAddingItem.value = false;
  }

  // ── Orchestrator ───────────────────────────────────────────────────────────

  void prepareSheetForAdd(DeliveryNoteItem item, {String? scannedBatch}) {
    if (_isSheetAlreadyOpen()) return;
    currentScannedBatch = scannedBatch;
    _resetSessionForAdd(item);
    final remaining = _calcRemainingQtyForDnItem(item);
    _seedSheetQty(maxQty: remaining);
    final child = _wireChildForAdd(item);
    _openItemSheet(child);
  }

  // ── Edit-mode loading flags ────────────────────────────────────────────────

  /// Sets the loading-indicator flags while the edit sheet is being prepared.
  ///
  /// Called before async DN resolution so the UI can show a per-item spinner
  /// immediately. Mirrors the flag pattern in
  /// [DeliveryNoteFormController.editItem].
  void _beginItemEditLoading(String? itemName) {
    isLoadingItemEdit.value  = true;
    loadingForItemName.value = itemName;
  }

  /// Clears the loading-indicator flags after the edit sheet has opened
  /// (or after an early return due to a missing DN item).
  ///
  /// Always called in a [finally] block so flags are reset regardless of
  /// how the preparation path exits.
  void _endItemEditLoading() {
    isLoadingItemEdit.value  = false;
    loadingForItemName.value = null;
  }

  // ── DN item resolution ─────────────────────────────────────────────────────

  /// Resolves the [DeliveryNoteItem] that backs the given [PackingSlipItem].
  ///
  /// Returns null when the linked Delivery Note is not loaded or when no
  /// DN item matches [slipItem.dnDetail]. The caller must treat null as a
  /// non-recoverable early-exit condition — the sheet cannot be opened
  /// without a backing DN item.
  DeliveryNoteItem? _resolveDnItemForSlipItem(PackingSlipItem slipItem) =>
      linkedDeliveryNote.value?.items
          .firstWhereOrNull((d) => d.name == slipItem.dnDetail);

  // ── Edit-mode session state reset ──────────────────────────────────────────

  /// Resets all session-context fields to their edit-mode values.
  ///
  /// - [itemFormKey] is recreated so the sheet gets a clean form state.
  /// - [isEditing] is set true — this session targets an existing item.
  /// - [currentItemNameKey] is set to the slip item's name so
  ///   [addItemWithQty] can locate the correct list entry.
  /// - Metadata shims are populated from the existing item so they are
  ///   preserved on the round-trip through [addItemWithQty].
  /// - [_populateItemDetails] copies DN item fields into the current-item
  ///   context fields consumed by [_openItemSheet].
  void _resetSessionForEdit(PackingSlipItem slipItem, DeliveryNoteItem dnItem) {
    itemFormKey        = GlobalKey<FormState>();
    isEditing.value    = true;
    currentItemNameKey = slipItem.name;
    bsItemOwner.value      = slipItem.owner;
    _populateItemDetails(dnItem);
  }

  // ── Child controller wiring (edit) ─────────────────────────────────────────

  /// Creates, initialises, and wires the auto-submit callback for a new
  /// [PackingSlipItemFormController] in edit mode.
  ///
  /// Passes [editingItem] to [child.initialise] so the child controller can
  /// pre-populate its fields from the existing slip item.
  /// Single responsibility: child controller lifecycle setup for edit path.
  PackingSlipItemFormController _wireChildForEdit(
      DeliveryNoteItem dnItem,
      PackingSlipItem  slipItem,
      ) {
    final child = Get.put(PackingSlipItemFormController());
    child.initialise(
      parent:      this,
      itemCode:    dnItem.itemCode,
      itemName:    dnItem.itemName ?? '',
      itemGroup:   dnItem.itemGroup ?? '',
      variantOf:   dnItem.customVariantOf ?? '',
      editingItem: slipItem,
    );
    child.setupAutoSubmit(onValid: _onAutoSubmitValid);
    return child;
  }

  // ── Orchestrator ───────────────────────────────────────────────────────────

  Future<void> editItem(PackingSlipItem item) async {
    if (_isSheetAlreadyOpen()) return;
    _beginItemEditLoading(item.name);
    try {
      final dnItem = _resolveDnItemForSlipItem(item);
      if (dnItem == null) return;
      _resetSessionForEdit(item, dnItem);
      currentScannedBatch = null;
      final remaining = _calcRemainingQtyForDnItem(
        dnItem,
        excludeSlipItemName: item.name,
      );
      _seedSheetQty(maxQty: remaining, initialQty: item.qty);
      final child = _wireChildForEdit(dnItem, item);
      _openItemSheet(child);
    } finally {
      _endItemEditLoading();
    }
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  void deleteItem(PackingSlipItem item) {
    if (isItemSheetOpen.value) {
      if (Get.isBottomSheetOpen == true) Get.back();
    }
    GlobalDialog.showConfirmation(
      title:   'Remove Item?',
      message: 'Are you sure you want to remove ${item.itemCode} from this package?',
      onConfirm: () async {
        final items = packingSlip.value?.items.toList() ?? [];
        items.removeWhere((i) => i.name == item.name);
        packingSlip.value = packingSlip.value?.copyWith(items: items);
        _checkForChanges();
        GlobalSnackbar.success(message: 'Item removed');
        if (isDirty.value) await saveDocument();
      },
    );
  }

  void _populateItemDetails(DeliveryNoteItem item) {
    currentItemDnDetail  = item.name;
    currentItemCode      = item.itemCode;
    currentItemName      = item.itemName;
    currentBatchNo       = item.batchNo;
    bsBatchNo.value      = item.batchNo;
    currentUom           = item.uom;
    currentSerial        = item.customInvoiceSerialNumber;
    currentNetWeight     = 0.0;
    currentWeightUom     = 0.0;
  }

  /// E1 fix: PackingSlipItemFormController.adjustQty takes int, but delta
  /// arrives here as double from the stepper.  Cast at the call site.
  void adjustQty(double delta) {
    if (isItemSheetOpen.value) {
      Get.find<PackingSlipItemFormController>().adjustQty(delta.toInt());
    }
  }

  // ── Item list mutations ────────────────────────────────────────────────────

  /// Replaces the qty on the [PackingSlipItem] identified by [nameKey].
  ///
  /// All other fields are preserved from the existing item — only [qty] is
  /// written. This is the edit-path mutation, equivalent to
  /// [StockEntryFormController.updateItem] and
  /// [DeliveryNoteFormController.updateItem].
  ///
  /// Returns silently if no item with [nameKey] exists in the current list.
  void updateItem(String nameKey, double qty) {
    final items = packingSlip.value?.items.toList() ?? [];
    final index = items.indexWhere((i) => i.name == nameKey);
    if (index == -1) return;

    final existing = items[index];
    items[index] = PackingSlipItem(
      name:       existing.name,
      dnDetail:   existing.dnDetail,
      itemCode:   existing.itemCode,
      itemName:   existing.itemName,
      qty:        qty,
      uom:        existing.uom,
      batchNo:    existing.batchNo,
      netWeight:  existing.netWeight,
      weightUom:  existing.weightUom,
      customInvoiceSerialNumber: existing.customInvoiceSerialNumber,
      customVariantOf:           existing.customVariantOf,
      customCountryOfOrigin:     existing.customCountryOfOrigin,
      creation:   existing.creation,
      owner:      existing.owner,
      modified:   existing.modified,
      modifiedBy: existing.modifiedBy,
    );
    packingSlip.value = packingSlip.value?.copyWith(items: items);
  }

  /// Accumulates [qty] into an existing [PackingSlipItem] whose [dnDetail]
  /// matches [currentItemDnDetail].
  ///
  /// PS-specific: multiple scans of the same DN line accumulate into one
  /// row rather than creating duplicate rows. SE and DN do not have this
  /// path — they always create unique rows.
  ///
  /// Returns silently if no matching row is found (caller must fall through
  /// to [_addItemToList]).
  bool _mergeItemQty(List<PackingSlipItem> items, double qty) {
    final index = items.indexWhere((i) => i.dnDetail == currentItemDnDetail);
    if (index == -1) return false;

    final existing = items[index];
    items[index] = PackingSlipItem(
      name:       existing.name,
      dnDetail:   existing.dnDetail,
      itemCode:   existing.itemCode,
      itemName:   existing.itemName,
      qty:        existing.qty + qty,
      uom:        existing.uom,
      batchNo:    existing.batchNo,
      netWeight:  existing.netWeight,
      weightUom:  existing.weightUom,
      customInvoiceSerialNumber: existing.customInvoiceSerialNumber,
      customVariantOf:           existing.customVariantOf,
      customCountryOfOrigin:     existing.customCountryOfOrigin,
      creation:   existing.creation,
      owner:      existing.owner,
      modified:   existing.modified,
      modifiedBy: existing.modifiedBy,
    );
    return true;
  }

  /// Appends a brand-new [PackingSlipItem] to [items] built from the current
  /// session context fields.
  ///
  /// Equivalent to [StockEntryFormController._addItemToList] and
  /// [DeliveryNoteFormController._addItemToList]: constructs the item from
  /// the controller's context state and appends it to the list.
  void _addItemToList(List<PackingSlipItem> items, double qty) {
    items.add(PackingSlipItem(
      name:        '',
      dnDetail:    currentItemDnDetail!,
      itemCode:    currentItemCode!,
      itemName:    currentItemName ?? '',
      qty:         qty,
      uom:         currentUom ?? '',
      batchNo:     currentBatchNo ?? '',
      netWeight:   0.0,
      weightUom:   0.0,
      customInvoiceSerialNumber: currentSerial,
      customVariantOf:           null,
      customCountryOfOrigin:     null,
      creation:    DateTime.now().toString(),
      owner:       bsItemOwner.value,
      modified:    null,
      modifiedBy:  null,
    ));
  }

  // ── Post-commit persistence ────────────────────────────────────────────────

  /// Applies [items] to the packing slip, checks for changes, and triggers
  /// a background save when the document is dirty.
  ///
  /// Deferred to the next frame so the sheet's exit animation fully unmounts
  /// [SharedQtyField] (and its [TextEditingController]) before the Obx
  /// rebuild fires. Without this deferral, [_AnimatedState.didUpdateWidget]
  /// calls addListener on an already-disposed controller → crash.
  ///
  /// Mirrors the deferred-save pattern used in
  /// [StockEntryFormController.addItem].
  void _applyAndPersist(List<PackingSlipItem> items) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      packingSlip.value = packingSlip.value?.copyWith(items: items);
      _checkForChanges();
      if (isDirty.value) await saveDocument();
    });
  }

  // ── Orchestrators ──────────────────────────────────────────────────────────

  /// Commits the given [qty] to the packing slip item list.
  ///
  /// Three paths — edit, add-merge, add-create — are each delegated to a
  /// single-responsibility mutation function.
  ///
  /// Mirrors the structural split of [StockEntryFormController.updateItem]
  /// (edit path) and [StockEntryFormController._addItemToList] (add path).
  Future<void> addItemWithQty(double qty) async {
    if (qty <= 0) return;

    if (isEditing.value && currentItemNameKey != null) {
      updateItem(currentItemNameKey!, qty);
      Get.key.currentState?.pop();
      _applyAndPersist(packingSlip.value?.items.toList() ?? []);
      return;
    }

    final items = packingSlip.value?.items.toList() ?? [];
    final merged = _mergeItemQty(items, qty);
    if (!merged) _addItemToList(items, qty);
    Get.key.currentState?.pop();
    _applyAndPersist(items);
  }

  /// Entry point called by the sheet's submit button and auto-submit.
  ///
  /// Parses the qty from [bsQtyController], pops the sheet on zero-qty,
  /// then delegates to [addItemWithQty].
  ///
  /// Mirrors [StockEntryFormController.addItem] as the thin coordinator
  /// that reads form state and hands off to the mutation layer.
  Future<void> addItem() async {
    // Read qty from the child controller's field — that is what the user typed into.
    final child = Get.find<PackingSlipItemFormController>();
    final qty = double.tryParse(child.qtyController.text) ?? 0.0;
    if (qty <= 0) {
      Get.key.currentState?.pop();
      return;
    }
    await addItemWithQty(qty);
  }

  // ---------------------------------------------------------------------------
  // deleteCurrentItem — called by child.deleteCurrentItem()
  // ---------------------------------------------------------------------------

  Future<void> deleteCurrentItem() async {
    if (currentItemNameKey == null) return;
    GlobalDialog.showConfirmation(
      title:       'Remove Item?',
      message:     'Are you sure you want to remove this item from the package?',
      confirmText: 'Remove',
      onConfirm: () async {
        if (Get.isBottomSheetOpen == true) Get.key.currentState?.pop();
        // Defer state mutation to the next frame so the sheet's exit animation
        // fully unmounts SharedQtyField (and its TextEditingController) before
        // the Obx rebuild fires. Mutating packingSlip.value on the same call
        // stack as pop() causes _AnimatedState.didUpdateWidget to call
        // addListener on the already-disposed TextEditingController → crash.
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final items = packingSlip.value?.items.toList() ?? [];
          items.removeWhere((i) => i.name == currentItemNameKey);
          packingSlip.value = packingSlip.value?.copyWith(items: items);
          _checkForChanges();
          if (isDirty.value) await saveDocument();
        });
      },
    );
  }

  // ── Item payload serialisation helper ──────────────────────────────────────

  /// Serialises a single [PackingSlipItem] into the API payload map.
  ///
  /// Only the fields the server accepts on create/update are included.
  /// The [name] field is conditionally included — new items (empty name)
  /// must not send a name, otherwise ERPNext treats the row as an update
  /// to a non-existent child row.
  ///
  /// Extracted as a named helper so [_buildItemsPayload] is free of
  /// per-field construction logic. Mirrors SE's [_stripLocalName] and
  /// item-field helpers inside [_buildItemsPayload].
  Map<String, dynamic> _serialiseItem(PackingSlipItem item) {
    final json = <String, dynamic>{
      'item_code':                    item.itemCode,
      'qty':                          item.qty,
      'dn_detail':                    item.dnDetail,
      'custom_invoice_serial_number': item.customInvoiceSerialNumber,
    };
    if (item.name.isNotEmpty) json['name'] = item.name;
    return json;
  }

  // ── Payload builders ───────────────────────────────────────────────────────

  /// Builds the document-level (header) fields for the save payload.
  ///
  /// Does not include the items array — that is composed separately by
  /// [_buildItemsPayload] and merged by the orchestrator. Mirrors
  /// [StockEntryFormController._buildHeaderPayload].
  Map<String, dynamic> _buildHeaderPayload() => {
    'delivery_note': packingSlip.value!.deliveryNote,
    'from_case_no':  packingSlip.value!.fromCaseNo,
    'to_case_no':    packingSlip.value!.toCaseNo,
    'custom_po_no':  packingSlip.value!.customPoNo,
    'modified':      packingSlip.value?.modified,
  };

  /// Builds the items array for the save payload.
  ///
  /// Delegates per-item serialisation to [_serialiseItem] so this function
  /// owns only the mapping concern, not the per-field construction detail.
  /// Mirrors [StockEntryFormController._buildItemsPayload].
  List<Map<String, dynamic>> _buildItemsPayload() =>
      (packingSlip.value?.items ?? []).map(_serialiseItem).toList();

  // ── Create / update document calls ─────────────────────────────────────────

  /// Calls the create-document API, applies the returned document to state,
  /// transitions [mode] to `'edit'`, and shows the creation snackbar.
  ///
  /// Single responsibility: the create path and its post-save state
  /// mutations. Mirrors [StockEntryFormController._createDocument].
  Future<void> _createDocument(Map<String, dynamic> data) async {
    final response =
    await _apiProvider.createDocument('Packing Slip', data);
    if (response.statusCode == 200 && response.data['data'] != null) {
      final saved = PackingSlip.fromJson(response.data['data']);
      packingSlip.value = saved;
      _updateOriginalState(saved);
      name = saved.name;
      mode = 'edit';
      await startRealtimeSyncAfterCreate();
      GlobalSnackbar.success(message: 'Packing Slip Created: ${saved.name}');
      _setSaveResult(SaveResult.success);
    } else {
      GlobalSnackbar.error(message: 'Failed to save Packing Slip');
      _setSaveResult(SaveResult.error);
    }
  }

  /// Calls the update-document API, applies the returned document to state,
  /// and shows the save snackbar.
  ///
  /// Single responsibility: the update path and its post-save state
  /// mutations. Mirrors [StockEntryFormController._updateDocument].
  Future<void> _updateDocument(Map<String, dynamic> data) async {
    final response =
    await _apiProvider.updateDocument('Packing Slip', name, data);
    if (response.statusCode == 200 && response.data['data'] != null) {
      final saved = PackingSlip.fromJson(response.data['data']);
      packingSlip.value = saved;
      _updateOriginalState(saved);
      GlobalSnackbar.success(message: 'Packing Slip Saved');
      _setSaveResult(SaveResult.success);
    } else {
      GlobalSnackbar.error(message: 'Failed to save Packing Slip');
      _setSaveResult(SaveResult.error);
    }
  }

  // ── Error handler ──────────────────────────────────────────────────────────

  /// Extracts the human-readable message from a Frappe exception string.
  ///
  /// Frappe formats exceptions as `ExceptionClassName: message`. This method
  /// returns everything after the first `: ` so the user sees, e.g.,
  /// "Row 1: Please provide a valid Delivery Note Item reference" rather
  /// than the full class-prefixed string.
  String _parseFrappeException(String raw) {
    final idx = raw.indexOf(': ');
    return idx >= 0 ? raw.substring(idx + 2).trim() : raw.trim();
  }

  /// Handles exceptions thrown during [saveDocument].
  ///
  /// Priority:
  ///   1. Version-conflict (TimestampMismatchError / 409) → stale-doc dialog.
  ///   2. Frappe validation error in response body → human-readable snackbar.
  ///   3. Fallback → generic error snackbar.
  void _handleSaveError(Object e) {
    _setSaveResult(SaveResult.error);
    if (handleVersionConflict(e)) return;
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final raw = data['exception']?.toString() ?? '';
        if (raw.isNotEmpty) {
          GlobalSnackbar.error(message: _parseFrappeException(raw));
          return;
        }
      }
    }
    GlobalSnackbar.error(message: 'Save failed: $e');
  }

  // ── Orchestrator ───────────────────────────────────────────────────────────

  /// Persists the current packing slip to the server.
  ///
  /// Guard order mirrors [StockEntryFormController.saveDocument]:
  ///   1. Dirty guard — skip if nothing has changed (except on new docs).
  ///   2. Concurrent-save guard — skip if a save is already in flight.
  ///   3. Stale-document guard — block if the document has been modified
  ///      externally since it was last fetched.
  ///
  /// Delegates payload construction to [_buildHeaderPayload] /
  /// [_buildItemsPayload], API calls to [_createDocument] / [_updateDocument],
  /// and error handling to [_handleSaveError]. The orchestrator contains no
  /// field access, no JSON construction, and no snackbar calls.
  @override
  Future<void> saveDocument() async {
    if (!isDirty.value && mode != 'new') return;
    if (isSaving.value) return;
    if (checkStaleAndBlock()) return;

    isSaving.value = true;
    final data = _buildHeaderPayload()
      ..['items'] = _buildItemsPayload();
    try {
      if (mode == 'new') {
        await _createDocument(data);
      } else {
        await _updateDocument(data);
      }
    } catch (e) {
      _handleSaveError(e);
    } finally {
      isSaving.value = false;
    }
  }
}
