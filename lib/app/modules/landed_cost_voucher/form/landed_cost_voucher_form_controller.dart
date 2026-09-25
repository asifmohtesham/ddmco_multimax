import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/data/providers/landed_cost_voucher_provider.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

class LandedCostVoucherFormController extends GetxController {
  final LandedCostVoucherProvider _provider =
      Get.find<LandedCostVoucherProvider>();

  String name = Get.arguments?['name'] ?? '';
  String mode = Get.arguments?['mode'] ?? 'new';

  var isLoading = true.obs;
  var isSaving = false.obs;
  var isDirty = false.obs;

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
      if (mode == 'new') {
        // Implement create
        // final res = await _provider.createLandedCostVoucher(data);
        // handle response
      } else {
        // Implement update
        // final res = await _provider.updateLandedCostVoucher(name, data);
        // handle response
      }
    } catch (e) {
      AppNotification.error('Error saving document: $e');
    } finally {
      isSaving.value = false;
    }
  }
}
