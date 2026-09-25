import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/data/providers/landed_cost_voucher_provider.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/data/mixins/realtime_sync_mixin.dart';
import 'package:multimax/app/modules/global_widgets/link_search_sheet.dart';
import 'package:multimax/app/modules/landed_cost_voucher/landed_cost_voucher_controller.dart';

class LandedCostVoucherFormController extends GetxController with RealtimeSyncMixin {
  final LandedCostVoucherProvider _provider =
      Get.find<LandedCostVoucherProvider>();

  String name = Get.arguments?['name'] ?? '';
  String mode = Get.arguments?['mode'] ?? 'new';

  var isLoading = true.obs;
  @override var isSaving = false.obs;
  @override var isDirty = false.obs;

  var saveResult = SaveResult.idle.obs;

  @override String get realtimeDoctype => 'Landed Cost Voucher';
  @override String get realtimeDocname => name;

  var voucher = Rx<LandedCostVoucher?>(null);
  var docMeta = <String, dynamic>{}.obs;
  var isMetaLoaded = false.obs;

  final companyController = TextEditingController();
  final postingDateController = TextEditingController();
  final distributeChargesController = TextEditingController(text: 'Qty');

  @override
  void onInit() {
    super.onInit();
    _fetchMeta();
    if (mode == 'new') {
      _initNewDocument();
    } else {
      fetchDocument();
    }

    _setupListeners();
  }

  void _setupListeners() {
    companyController.addListener(_markDirty);
    postingDateController.addListener(_markDirty);
    distributeChargesController.addListener(_markDirty);
  }

  void _markDirty() {
    if (!isDirty.value && !isLoading.value) {
      isDirty.value = true;
    }
  }

  void confirmDiscard() {
    if (!isDirty.value) {
      Get.back();
      return;
    }
    GlobalDialog.showUnsavedChanges(onDiscard: () {
      Get.back(); // close dialog
      Get.back(); // close screen
    });
  }
  
  @override
  Future<void> reloadDocument() async {
    await fetchDocument();
  }

  void showDistributeChargesSheet() {
    Get.bottomSheet(
      Container(
        color: Theme.of(Get.context!).colorScheme.surface,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ['Qty', 'Amount', 'Dist. Manual']
                .map((e) => ListTile(
                      title: Text(e),
                      onTap: () {
                        distributeChargesController.text = e;
                        Get.back();
                      },
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  void showCompanySearchSheet() {
    showLinkSearchSheet(
      doctype: 'Company',
      title: 'Select Company',
      onSelected: (val) {
        companyController.text = val;
      },
    );
  }

  Future<void> _fetchMeta() async {
    try {
      final res = await Get.find<ApiProvider>().getDocTypeMeta('Landed Cost Voucher');
      if (res.statusCode == 200 && res.data['docs'] != null && res.data['docs'].isNotEmpty) {
        docMeta.value = res.data['docs'][0];
        isMetaLoaded.value = true;
      }
    } catch (e) {
      // Ignore meta fail
    }
  }

  void _initNewDocument() {
    voucher.value = LandedCostVoucher(
      name: '',
      owner: '',
      creation: DateTime.now().toIso8601String(),
      modified: DateTime.now().toIso8601String(),
      status: 'Draft',
      docstatus: 0,
      company: '',
      postingDate: DateTime.now().toIso8601String().split('T')[0],
      distributeChargesBasedOn: 'Qty',
      totalTaxesAndCharges: 0.0,
      purchaseReceipts: [],
      items: [],
      taxes: [],
    );
    _populateFields();
    isLoading.value = false;
  }

  Future<void> fetchDocument() async {
    isLoading.value = true;
    try {
      final response = await _provider.getLandedCostVoucher(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        voucher.value = LandedCostVoucher.fromJson(response.data['data']);
        _populateFields();
        isDirty.value = false;
      } else {
        AppNotification.error('Failed to load document');
      }
    } catch (e) {
      AppNotification.error('Error loading document: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void _populateFields() {
    final v = voucher.value;
    if (v == null) return;

    companyController.text = v.company;
    postingDateController.text = v.postingDate;
    distributeChargesController.text = v.distributeChargesBasedOn;
  }

  @override
  Future<void> saveDocument() async {
    if (isSaving.value) return;

    final v = voucher.value;
    if (v == null) return;

    isSaving.value = true;

    final data = {
      'company': companyController.text,
      'posting_date': postingDateController.text,
      'distribute_charges_based_on': distributeChargesController.text,
      // Add other fields and children
      'purchase_receipts': v.purchaseReceipts.map((e) => e.toJson()).toList(),
      'items': v.items.map((e) => e.toJson()).toList(),
      'taxes': v.taxes.map((e) => e.toJson()).toList(),
      if (v.vendorInvoices != null)
        'vendor_invoices': v.vendorInvoices!.map((e) => e.toJson()).toList(),
    };

    try {
      saveResult.value = SaveResult.idle;
      if (mode == 'new') {
        final res = await _provider.createLandedCostVoucher(data);
        if (res.statusCode == 200 && res.data['data'] != null) {
          name = res.data['data']['name'];
          mode = 'edit';
          Get.find<LandedCostVoucherController>().fetchLandedCostVouchers(clear: true);
        } else {
          throw Exception('Failed to create document');
        }
      } else {
        final res = await _provider.updateLandedCostVoucher(name, data);
        if (res.statusCode != 200) {
          throw Exception('Failed to update document');
        }
      }
      saveResult.value = SaveResult.success;
      isDirty.value = false;
      await fetchDocument();
    } catch (e) {
      saveResult.value = SaveResult.error;
      AppNotification.error('Error saving document: $e');
    } finally {
      isSaving.value = false;
    }
  }
}
