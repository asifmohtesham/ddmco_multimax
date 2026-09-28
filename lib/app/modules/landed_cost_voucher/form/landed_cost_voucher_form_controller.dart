import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:intl/intl.dart';
import 'package:multimax/app/data/enums/save_result.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/landed_cost_voucher_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/lcv_rules.dart';

/// Loads, creates, edits and submits one Landed Cost Voucher.
///
/// The app edits the header, the receipt list and the charges. ERPNext
/// derives the item rows and each item's share of the charges on save, so
/// this controller never edits items — see [buildLcvPayload]. Cancel stays
/// in Desk.
class LandedCostVoucherFormController extends GetxController
    with OptimisticLockingMixin {
  LandedCostVoucherFormController({
    String? name,
    String? mode,
    String? defaultCompany,
  })  : name = name ?? Get.arguments?['name'] ?? '',
        mode = mode ?? Get.arguments?['mode'] ?? 'view',
        _defaultCompany = defaultCompany;

  final LandedCostVoucherProvider _provider =
      Get.find<LandedCostVoucherProvider>();
  final String? _defaultCompany;

  String name;
  String mode;
  bool get isNew => mode == 'new';

  final isLoading = true.obs;
  final isSaving = false.obs;
  final isSubmitting = false.obs;
  final isDirty = false.obs;
  final isAddingReceipt = false.obs;
  final canSubmitPerm = false.obs;
  final saveResult = SaveResult.idle.obs;

  final voucher = Rx<LandedCostVoucher?>(null);
  final docMeta = <String, dynamic>{}.obs;
  final isMetaLoaded = false.obs;

  // Editable draft state, re-seeded from [voucher] on every load.
  final postingDate = ''.obs;
  final distributeChargesBasedOn = 'Qty'.obs;
  final receipts = <LandedCostPurchaseReceipt>[].obs;
  final charges = <LandedCostTaxesAndCharges>[].obs;

  /// Set when a receipt is added or removed since the last load; tells
  /// [buildLcvPayload] to have the server rebuild the item rows.
  bool _receiptsChanged = false;
  String? _defaultChargeAccount;

  String get company => voucher.value?.company ?? '';

  double get totalCharges => charges.fold(0.0, (sum, c) => sum + c.amount);

  bool get _canWrite =>
      isNew ||
      Get.find<PermissionService>()
              .hasAccess('Landed Cost Voucher', permType: 'write') ==
          true;

  bool get isEditable =>
      _canWrite &&
      lcvIsEditable(
        docStatus: voucher.value?.docstatus,
        distributeChargesBasedOn: distributeChargesBasedOn.value,
      );

  bool get isManualDistribution =>
      distributeChargesBasedOn.value == kLcvManualDistribution;

  /// True while a save, submit or (re)load is in flight. Draft mutations
  /// are rejected while busy so a save's payload can't be edited out from
  /// under it — an edit that lands mid-save would otherwise be silently
  /// wiped by the post-save reload.
  bool get _isBusy =>
      isSaving.value || isSubmitting.value || isLoading.value;

  bool get canSubmit =>
      lcvCanSubmit(
        isNew: isNew,
        docStatus: voucher.value?.docstatus,
        isDirty: isDirty.value,
        isSaving: isSaving.value,
        isSubmitting: isSubmitting.value,
        canSubmitPerm: canSubmitPerm.value,
      ) &&
      !isManualDistribution &&
      !isAddingReceipt.value;

  @override
  void onInit() {
    super.onInit();
    _fetchMeta();
    if (isNew) {
      _initNew();
    } else {
      fetchDocument();
    }
  }

  Future<void> _fetchMeta() async {
    try {
      final res =
          await Get.find<ApiProvider>().getDocTypeMeta('Landed Cost Voucher');
      if (res.statusCode == 200 &&
          res.data['docs'] != null &&
          res.data['docs'].isNotEmpty) {
        docMeta.value = res.data['docs'][0];
        isMetaLoaded.value = true;
      }
    } catch (e) {
      // Labels fall back to their defaults when meta cannot be loaded.
    }
  }

  void _initNew() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final v = LandedCostVoucher(
      name: 'New Landed Cost Voucher',
      owner: null,
      creation: today,
      modified: '',
      status: 'Draft',
      docstatus: 0,
      company: _defaultCompany ?? Get.find<StorageService>().getCompany(),
      postingDate: today,
      distributeChargesBasedOn: kLcvDistributionOptions.first,
      totalTaxesAndCharges: 0,
      purchaseReceipts: [],
      items: [],
      taxes: [],
    );
    voucher.value = v;
    _loadDraft(v);
    isLoading.value = false;
  }

  void _loadDraft(LandedCostVoucher v) {
    postingDate.value = v.postingDate;
    distributeChargesBasedOn.value = v.distributeChargesBasedOn;
    receipts.assignAll(v.purchaseReceipts);
    charges.assignAll(v.taxes);
    _receiptsChanged = false;
    isDirty.value = false;
  }

  Future<void> fetchDocument() async {
    isLoading.value = true;
    try {
      final response = await _provider.getLandedCostVoucher(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final v = LandedCostVoucher.fromJson(response.data['data']);
        voucher.value = v;
        _loadDraft(v);
      } else {
        GlobalSnackbar.error(message: 'Failed to load document');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Error loading document: $e');
    } finally {
      isLoading.value = false;
    }
    await _refreshSubmitPermission();
  }

  /// Only saved drafts can be submitted; everything else is fail-closed.
  Future<void> _refreshSubmitPermission() async {
    final v = voucher.value;
    if (isNew || v == null || v.docstatus != 0) {
      canSubmitPerm.value = false;
      return;
    }
    canSubmitPerm.value = await _provider.canSubmit(name);
  }

  @override
  Future<void> reloadDocument() async {
    await fetchDocument();
    GlobalSnackbar.success(message: 'Document reloaded');
  }

  void _markDirty() {
    if (!isLoading.value && isEditable) isDirty.value = true;
  }

  // ── Header fields ───────────────────────────────────────────────────────

  void setPostingDate(String date) {
    if (!isEditable || _isBusy || date == postingDate.value) return;
    postingDate.value = date;
    _markDirty();
  }

  void setDistribution(String basis) {
    if (!isEditable || _isBusy || !kLcvDistributionOptions.contains(basis)) {
      return;
    }
    if (basis == distributeChargesBasedOn.value) return;
    distributeChargesBasedOn.value = basis;
    _markDirty();
  }

  // ── Receipts ────────────────────────────────────────────────────────────

  /// Looks up [receiptName], checks it the way ERPNext will on save, and adds
  /// it with the supplier/date/total Desk would have filled in.
  Future<void> addReceipt(String receiptName) async {
    if (!isEditable || _isBusy || isAddingReceipt.value) return;
    if (checkStaleAndBlock()) return;
    isAddingReceipt.value = true;
    try {
      final summary = await _provider.getReceiptSummary(receiptName);
      // Re-check: a submit/save/reload may have started while this awaited.
      if (!isEditable || _isBusy) return;
      if (summary == null) {
        GlobalSnackbar.error(message: 'Could not load $receiptName');
        return;
      }
      final rejection = lcvReceiptRejection(
        receipt: summary,
        company: company,
        alreadyAdded: receipts.map((r) => r.receiptDocument),
      );
      if (rejection != null) {
        GlobalSnackbar.warning(message: rejection);
        return;
      }
      receipts.add(LandedCostPurchaseReceipt(
        name: 'local_${DateTime.now().microsecondsSinceEpoch}',
        receiptDocumentType: kLcvReceiptType,
        receiptDocument: receiptName,
        supplier: summary['supplier'] as String?,
        postingDate: summary['posting_date'] as String?,
        grandTotal: (summary['grand_total'] as num?)?.toDouble() ?? 0.0,
      ));
      _receiptsChanged = true;
      _markDirty();
    } catch (e) {
      GlobalSnackbar.error(message: 'Could not load $receiptName: $e');
    } finally {
      isAddingReceipt.value = false;
    }
  }

  void removeReceipt(LandedCostPurchaseReceipt receipt) {
    if (!isEditable || _isBusy) return;
    receipts.remove(receipt);
    _receiptsChanged = true;
    _markDirty();
  }

  // ── Charges ─────────────────────────────────────────────────────────────

  /// Replaces the charge whose `name` matches [charge]'s (an edit — the sheet
  /// keeps the server-assigned name), or appends it (a new charge, always
  /// carrying a fresh `local_` name from the sheet). Matching by name rather
  /// than list index keeps this correct across an intervening reload.
  void upsertCharge(LandedCostTaxesAndCharges charge) {
    if (!isEditable || _isBusy) return;
    final existing = charges.indexWhere((c) => c.name == charge.name);
    if (existing == -1) {
      charges.add(charge);
    } else {
      charges[existing] = charge;
    }
    _markDirty();
  }

  void removeCharge(int index) {
    if (!isEditable || _isBusy) return;
    charges.removeAt(index);
    _markDirty();
  }

  Future<String?> defaultChargeAccount() async =>
      _defaultChargeAccount ??= await _provider.getDefaultChargeAccount(company);

  // ── Save / Submit ───────────────────────────────────────────────────────

  Future<void> saveDocument() async {
    if (isSaving.value || !isEditable || isAddingReceipt.value) return;
    if (checkStaleAndBlock()) return;
    final blocker = lcvSaveBlocker(receipts: receipts, charges: charges);
    if (blocker != null) {
      GlobalSnackbar.warning(message: blocker);
      return;
    }

    isSaving.value = true;
    final data = buildLcvPayload(
      company: company,
      postingDate: postingDate.value,
      distributeChargesBasedOn: distributeChargesBasedOn.value,
      receipts: receipts,
      charges: charges,
      items: voucher.value?.items ?? const [],
      receiptsChanged: _receiptsChanged,
      modified: isNew ? null : voucher.value?.modified,
    );

    try {
      final res = isNew
          ? await _provider.createLandedCostVoucher(data)
          : await _provider.updateLandedCostVoucher(name, data);
      if (res.statusCode == 200 && res.data['data'] != null) {
        if (isNew) {
          name = res.data['data']['name'] as String;
          mode = 'edit';
        }
        // Reload so the user sees the items and allocated charges ERPNext
        // just computed.
        await fetchDocument();
        saveResult.value = SaveResult.success;
        GlobalSnackbar.success(message: 'Landed Cost Voucher saved');
      } else {
        saveResult.value = SaveResult.error;
        GlobalSnackbar.error(message: 'Failed to save Landed Cost Voucher');
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      saveResult.value = SaveResult.error;
      GlobalSnackbar.error(message: _dioMessage(e, 'Save failed'));
    } catch (e) {
      saveResult.value = SaveResult.error;
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  /// Header Submit: confirm like Desk does, then [performSubmit].
  Future<void> submitDocument() async {
    if (!canSubmit) return;
    final confirmed = await GlobalDialog.confirm(
      title: 'Confirm',
      message: 'Permanently Submit $name? '
          'This updates the valuation of the linked receipts.',
      confirmText: 'Yes',
    );
    if (confirmed != true) return;
    await performSubmit();
  }

  Future<void> performSubmit() async {
    if (!canSubmit) return;
    isSubmitting.value = true;
    try {
      final res = await _provider.submitLandedCostVoucher(name,
          modified: voucher.value!.modified);
      if (res.statusCode == 200) {
        await fetchDocument(); // docstatus 1 → read-only, perm refreshed
        GlobalSnackbar.success(message: 'Landed Cost Voucher $name submitted');
      } else {
        GlobalSnackbar.error(message: 'Failed to submit Landed Cost Voucher');
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      GlobalSnackbar.error(message: _dioMessage(e, 'Submit failed'));
    } catch (e) {
      GlobalSnackbar.error(message: 'Submit failed: $e');
    } finally {
      isSubmitting.value = false;
    }
  }

  static String _dioMessage(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map) {
      if (data['exception'] != null) {
        return data['exception'].toString().split(':').last.trim();
      }
      if (data['_server_messages'] != null) {
        return 'Validation Error: Check form details';
      }
    }
    return fallback;
  }

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }
}
