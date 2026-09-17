import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/enums/save_result.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/models/item_price_model.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/option_picker_sheet.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_bottom_sheet.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_column.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_config.dart';

/// Item Price form. Modes from `Get.arguments`: `new` (optionally with
/// `item_code` prefill from the Item form), `edit`, `view`. Users without
/// write access get a read-only form regardless of mode.
class ItemPriceFormController extends GetxController with OptimisticLockingMixin {
  final ItemPriceProvider _provider = Get.find<ItemPriceProvider>();

  String name = (Get.arguments is Map ? Get.arguments['name'] : null) ?? '';
  final RxString mode =
      RxString((Get.arguments is Map ? Get.arguments['mode'] : null) ?? 'view');
  final String _prefillItem =
      (Get.arguments is Map ? Get.arguments['item_code'] : null) ?? '';

  final price = ItemPrice().obs;
  final priceLists = <PriceListInfo>[].obs;
  final itemUoms = <String>[].obs;

  final isLoading = true.obs;
  final isSaving = false.obs;
  final isDeleting = false.obs;
  final isDirty = false.obs;
  final notFound = false.obs;
  final moreOpen = false.obs;
  final saveResult = SaveResult.idle.obs;
  final serverError = ''.obs;
  final fieldErrors = <String, String>{}.obs;

  final rateController = TextEditingController();
  final packingUnitController = TextEditingController();
  final leadTimeController = TextEditingController();
  final noteController = TextEditingController();

  bool _seeding = false;
  String _originalJson = '';

  bool get canWrite =>
      Get.find<PermissionService>().hasAccess('Item Price',
          permType: mode.value == 'new' ? 'create' : 'write') ==
      true;

  bool get isEditable => mode.value != 'view' && canWrite;

  PriceListInfo? get selectedList =>
      priceLists.where((l) => l.name == price.value.priceList).firstOrNull;

  bool get isSellingList => selectedList?.selling ?? price.value.selling;

  String get currency => selectedList?.currency ?? price.value.currency;

  @override
  void onInit() {
    super.onInit();
    for (final c in [
      rateController,
      packingUnitController,
      leadTimeController,
      noteController,
    ]) {
      c.addListener(_syncText);
    }
    _start();
  }

  @override
  void onClose() {
    rateController.dispose();
    packingUnitController.dispose();
    leadTimeController.dispose();
    noteController.dispose();
    super.onClose();
  }

  Future<void> _start() async {
    await _loadPriceLists();
    if (mode.value == 'new') {
      await _initNew();
    } else {
      await fetchDocument();
    }
  }

  Future<void> _loadPriceLists() async {
    try {
      final res = await _provider.getPriceLists();
      priceLists.assignAll([
        for (final e in (res.data['data'] as List?) ?? const [])
          PriceListInfo.fromJson(Map<String, dynamic>.from(e as Map)),
      ]);
    } catch (_) {}
  }

  Future<void> _initNew() async {
    // 'Standard Selling' is the list ERPNext's setup wizard creates.
    final list = priceLists.where((l) => l.name == 'Standard Selling').firstOrNull ??
        priceLists.firstOrNull;
    price.value = ItemPrice(
      priceList: list?.name ?? '',
      selling: list?.selling ?? false,
      buying: list?.buying ?? false,
      currency: list?.currency ?? '',
      validFrom: frappeDate(DateTime.now()),
    );
    _seed();
    isDirty.value = true;
    isLoading.value = false;
    if (_prefillItem.isNotEmpty) await applyItem(_prefillItem);
  }

  Future<void> fetchDocument() async {
    isLoading.value = true;
    try {
      final res = await _provider.getItemPrice(name);
      price.value = ItemPrice.fromJson(
          Map<String, dynamic>.from(res.data['data'] as Map));
      _seed();
      _originalJson = jsonEncode(price.value.toJson());
      isDirty.value = false;
      notFound.value = false;
      serverError.value = '';
      fieldErrors.clear();
      _loadItemUoms(price.value.itemCode);
    } catch (_) {
      notFound.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  @override
  Future<void> reloadDocument() => fetchDocument();

  void _seed() {
    _seeding = true;
    final p = price.value;
    rateController.text = p.rate.toStringAsFixed(2);
    packingUnitController.text = p.packingUnit == 0 ? '' : '${p.packingUnit}';
    leadTimeController.text = p.leadTimeDays == 0 ? '' : '${p.leadTimeDays}';
    noteController.text = p.note ?? '';
    _seeding = false;
  }

  void _syncText() {
    if (_seeding) return;
    final p = price.value;
    p.rate = double.tryParse(rateController.text.replaceAll(',', '')) ?? 0;
    p.packingUnit = int.tryParse(packingUnitController.text) ?? 0;
    p.leadTimeDays = int.tryParse(leadTimeController.text) ?? 0;
    p.note = noteController.text.isEmpty ? null : noteController.text;
    price.refresh();
    _checkDirty();
  }

  void _checkDirty() {
    if (mode.value == 'new') {
      isDirty.value = true;
      return;
    }
    isDirty.value = jsonEncode(price.value.toJson()) != _originalJson;
  }

  void _edit(void Function(ItemPrice p) change) {
    if (!isEditable) return;
    price.update((p) => change(p!));
    _checkDirty();
  }

  // ── Item + units ─────────────────────────────────────────────────────

  Future<void> applyItem(String code) async {
    try {
      final res = await _provider.getItem(code);
      final d = Map<String, dynamic>.from(res.data['data'] as Map);
      if (pricingBool(d['has_variants'])) {
        fieldErrors['item_code'] =
            'Item Price cannot be created for the template item $code';
        return;
      }
      final uoms = uomsFromItem(d);
      itemUoms.assignAll(uoms);
      price.update((p) {
        p!.itemCode = code;
        p.itemName = (d['item_name'] ?? code).toString();
        p.brand = pricingLink(d['brand']);
        if (!uoms.contains(p.uom)) {
          p.uom = pricingLink(d['stock_uom']) ?? (uoms.isEmpty ? '' : uoms.first);
        }
      });
      fieldErrors.remove('item_code');
      _checkDirty();
    } catch (_) {
      GlobalSnackbar.error(message: 'Could not load item $code');
    }
  }

  Future<void> _loadItemUoms(String code) async {
    if (code.isEmpty) return;
    try {
      final res = await _provider.getItem(code);
      itemUoms.assignAll(
          uomsFromItem(Map<String, dynamic>.from(res.data['data'] as Map)));
    } catch (_) {}
  }

  Future<void> pickItem() async {
    if (!isEditable || mode.value != 'new') return;
    final row = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: 'Item',
        title: 'Select item',
        columns: [
          DocTypePickerColumn(fieldname: 'name', label: 'Item code', isPrimary: true),
          DocTypePickerColumn(fieldname: 'item_name', label: 'Name', isSecondary: true),
        ],
        filters: const [
          ['Item', 'has_variants', '=', 0],
          ['Item', 'disabled', '=', 0],
        ],
        enableBarcodeScan: true,
      ),
    );
    if (row != null) await applyItem(row['name'] as String);
  }

  void pickUom(BuildContext context) {
    if (!isEditable || itemUoms.isEmpty) return;
    showOptionPickerSheet(
      context,
      title: 'Unit',
      options: itemUoms.toList(),
      selected: price.value.uom,
      onSelected: (u) => _edit((p) => p.uom = u),
    );
  }

  // ── Price list / party / batch / dates ───────────────────────────────

  void pickPriceList(BuildContext context) {
    if (!isEditable) return;
    showOptionPickerSheet(
      context,
      title: 'Price list',
      options: [for (final l in priceLists) l.name],
      selected: price.value.priceList,
      onSelected: setPriceList,
    );
  }

  /// Mirrors item_price.py: the list decides selling/buying/currency; a
  /// selling list drops the supplier and a buying list drops the customer.
  void setPriceList(String listName) {
    final l = priceLists.where((x) => x.name == listName).firstOrNull;
    if (l == null) return;
    _edit((p) {
      p.priceList = l.name;
      p.selling = l.selling;
      p.buying = l.buying;
      p.currency = l.currency;
      if (!l.selling) p.customer = null;
      if (!l.buying) p.supplier = null;
    });
  }

  Future<void> pickParty() async {
    if (!isEditable) return;
    final doctype = isSellingList ? 'Customer' : 'Supplier';
    final row = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: doctype,
        title: 'Select ${doctype.toLowerCase()}',
        columns: [DocTypePickerColumn(fieldname: 'name', label: doctype, isPrimary: true)],
      ),
    );
    if (row == null) return;
    final v = row['name'] as String;
    _edit((p) => doctype == 'Customer' ? p.customer = v : p.supplier = v);
  }

  void clearParty() => _edit((p) {
        p.customer = null;
        p.supplier = null;
      });

  Future<void> pickBatch() async {
    final code = price.value.itemCode;
    if (!isEditable || code.isEmpty) return;
    final row = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: 'Batch',
        title: 'Select batch',
        columns: [DocTypePickerColumn(fieldname: 'name', label: 'Batch', isPrimary: true)],
        filters: [
          ['Batch', 'item', '=', code]
        ],
      ),
    );
    if (row != null) _edit((p) => p.batchNo = row['name'] as String);
  }

  void clearBatch() => _edit((p) => p.batchNo = null);

  Future<void> pickDate(BuildContext context, String field) async {
    if (!isEditable) return;
    final current = parseFrappeDate(
        field == 'valid_from' ? price.value.validFrom : price.value.validUpto);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    _edit((p) => field == 'valid_from'
        ? p.validFrom = frappeDate(picked)
        : p.validUpto = frappeDate(picked));
  }

  void clearValidUpto() => _edit((p) => p.validUpto = null);

  // ── Save / delete / discard ──────────────────────────────────────────

  Future<void> saveDocument() async {
    if (isSaving.value || !isEditable) return;
    final errors = validateItemPrice(price.value);
    final templateError = fieldErrors['item_code'];
    if (templateError != null && errors['item_code'] == null) {
      errors['item_code'] = templateError;
    }
    fieldErrors.assignAll(errors);
    if (errors.isNotEmpty) {
      saveResult.value = SaveResult.error;
      GlobalSnackbar.error(message: errors.values.first);
      return;
    }
    if (checkStaleAndBlock()) return;

    isSaving.value = true;
    serverError.value = '';
    final data = price.value.toJson();
    if (mode.value != 'new') data['modified'] = price.value.modified;

    try {
      final res = mode.value == 'new'
          ? await _provider.createItemPrice(data)
          : await _provider.updateItemPrice(name, data);
      final saved = res.data is Map ? res.data['data'] : null;
      if (saved is Map && saved['name'] != null) name = saved['name'].toString();
      mode.value = 'edit';
      await fetchDocument();
      saveResult.value = SaveResult.success;
      GlobalSnackbar.success(message: 'Item price saved');
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      saveResult.value = SaveResult.error;
      serverError.value = ItemFormController.parseServerMessage(e.response?.data);
    } catch (e) {
      saveResult.value = SaveResult.error;
      serverError.value = e.toString();
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(onDiscard: () {
      isDirty.value = false;
      Get.back();
    });
  }

  Future<void> deleteDocument() async {
    if (isDeleting.value) return;
    final p = price.value;
    final confirmed = await GlobalDialog.confirm(
      title: 'Delete this price?',
      message: '${p.itemName} · ${p.priceList} · '
          '${formatMoney(p.rate, p.currency)} / ${p.uom}. Delivery Notes already '
          'saved keep their rate; new ones will find no price.',
      confirmText: 'Delete',
      confirmColor: AppColors.red700,
      icon: Icons.delete_outline,
    );
    if (confirmed != true) return;
    if (await performDelete()) Get.back();
  }

  /// Network half of [deleteDocument], testable without the dialog.
  Future<bool> performDelete() async {
    if (isDeleting.value) return false;
    isDeleting.value = true;
    try {
      final res = await _provider.deleteItemPrice(name);
      final ok = res.statusCode == 200 || res.statusCode == 202 || res.statusCode == 204;
      if (ok) {
        isDirty.value = false;
        GlobalSnackbar.success(message: 'Item price deleted');
      } else {
        GlobalSnackbar.error(message: 'Failed to delete item price');
      }
      return ok;
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to delete item price: $e');
      return false;
    } finally {
      isDeleting.value = false;
    }
  }
}
