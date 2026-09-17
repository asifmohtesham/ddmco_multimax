import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/enums/save_result.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/models/item_price_model.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/data/providers/pricing_rule_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';
import 'package:multimax/app/modules/pricing/widgets/priority_picker_sheet.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_bottom_sheet.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_column.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_config.dart';

/// Pricing Rule form (modes `new`/`edit`/`view`). Price-discount rules are
/// editable; promotional-scheme and free-item (Product) rules are read-only.
class PricingRuleFormController extends GetxController with OptimisticLockingMixin {
  final PricingRuleProvider _provider = Get.find<PricingRuleProvider>();

  static const Map<String, String> kApplyOnLabels = {
    'Item Code': 'Item',
    'Item Group': 'Group',
    'Brand': 'Brand',
    'Transaction': 'Transaction',
  };

  String name = (Get.arguments is Map ? Get.arguments['name'] : null) ?? '';
  final RxString mode =
      RxString((Get.arguments is Map ? Get.arguments['mode'] : null) ?? 'view');

  final rule = PricingRule().obs;
  final isLoading = true.obs;
  final isSaving = false.obs;
  final isDeleting = false.obs;
  final isDirty = false.obs;
  final notFound = false.obs;
  final saveResult = SaveResult.idle.obs;
  final serverError = ''.obs;
  final fieldErrors = <String, String>{}.obs;

  final titleController = TextEditingController();
  final valueController = TextEditingController();
  final minQtyController = TextEditingController();
  final maxQtyController = TextEditingController();
  final minAmtController = TextEditingController();
  final maxAmtController = TextEditingController();

  List<TextEditingController> get _textControllers => [
        titleController,
        valueController,
        minQtyController,
        maxQtyController,
        minAmtController,
        maxAmtController,
      ];

  bool _seeding = false;
  String _originalJson = '';

  bool get canWrite =>
      Get.find<PermissionService>().hasAccess('Pricing Rule',
          permType: mode.value == 'new' ? 'create' : 'write') ==
      true;

  bool get isEditable => mode.value != 'view' && !rule.value.isLocked && canWrite;

  String get sideLabel {
    final r = rule.value;
    if (r.selling && r.buying) return 'Selling & Buying';
    return r.buying ? 'Buying' : 'Selling';
  }

  List<String> get forOptions => [
        'Everyone',
        ...applicableForOptions(
            selling: rule.value.selling, buying: rule.value.buying),
      ];

  bool tabHasError(int tab) =>
      fieldErrors.keys.any((k) => kPricingRuleFieldTab[k] == tab);

  @override
  void onInit() {
    super.onInit();
    for (final c in _textControllers) {
      c.addListener(_syncText);
    }
    if (mode.value == 'new') {
      _initNew();
    } else {
      fetchDocument();
    }
  }

  @override
  void onClose() {
    for (final c in _textControllers) {
      c.dispose();
    }
    super.onClose();
  }

  // ── Load ─────────────────────────────────────────────────────────────

  Future<void> _initNew() async {
    rule.value = PricingRule(validFrom: frappeDate(DateTime.now()));
    _seedControllers();
    isDirty.value = true;
    isLoading.value = false;
    try {
      final company = await _provider.getDefaultCompany();
      if (company != null) {
        rule.update((r) {
          r!.company = company.name;
          r.currency = company.currency;
        });
      }
    } catch (_) {
      // Currency stays blank; the server's "Currency is required" surfaces
      // in the banner on save.
    }
  }

  Future<void> fetchDocument() async {
    isLoading.value = true;
    try {
      final res = await _provider.getRule(name);
      rule.value =
          PricingRule.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
      _seedControllers();
      _originalJson = jsonEncode(rule.value.toJson());
      isDirty.value = false;
      notFound.value = false;
      serverError.value = '';
      fieldErrors.clear();
    } catch (_) {
      notFound.value = true;
    } finally {
      isLoading.value = false;
    }
    // `label`/`variantOf` are client-only and absent from the child rows, so a
    // reloaded rule would show bare codes and skip the variant/template check.
    // After isLoading, so the form paints without waiting on this.
    if (!notFound.value && rule.value.applyOn == 'Item Code') {
      await _provider.attachItemLabels(rule.value.targets);
      rule.refresh();
    }
  }

  @override
  Future<void> reloadDocument() => fetchDocument();

  static double _parse(String s) =>
      double.tryParse(s.replaceAll(',', '').trim()) ?? 0;

  static String _show(double v) => v == 0
      ? ''
      : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  double _value(PricingRule r) => switch (r.rateOrDiscount) {
        'Rate' => r.rate,
        'Discount Amount' => r.discountAmount,
        _ => r.discountPercentage,
      };

  void _seedControllers() {
    _seeding = true;
    final r = rule.value;
    titleController.text = r.title;
    valueController.text = _show(_value(r));
    minQtyController.text = _show(r.minQty);
    maxQtyController.text = _show(r.maxQty);
    minAmtController.text = _show(r.minAmt);
    maxAmtController.text = _show(r.maxAmt);
    _seeding = false;
  }

  void _syncText() {
    if (_seeding || !isEditable) return;
    final r = rule.value;
    r.title = titleController.text;
    final v = _parse(valueController.text);
    switch (r.rateOrDiscount) {
      case 'Rate':
        r.rate = v;
      case 'Discount Amount':
        r.discountAmount = v;
      default:
        r.discountPercentage = v;
    }
    r.minQty = _parse(minQtyController.text);
    r.maxQty = _parse(maxQtyController.text);
    r.minAmt = _parse(minAmtController.text);
    r.maxAmt = _parse(maxAmtController.text);
    rule.refresh();
    _checkDirty();
  }

  void _checkDirty() {
    if (mode.value == 'new') {
      isDirty.value = true;
      return;
    }
    isDirty.value = jsonEncode(rule.value.toJson()) != _originalJson;
  }

  void _edit(void Function(PricingRule r) change) {
    if (!isEditable) return;
    rule.update((r) => change(r!));
    _checkDirty();
  }

  // ── Rule tab ─────────────────────────────────────────────────────────

  void setEnabled(bool enabled) => _edit((r) => r.disable = !enabled);

  /// pricing_rule.js: a party type that no longer fits the side is cleared.
  void setSide(String label) => _edit((r) {
        r.selling = label != 'Buying';
        r.buying = label != 'Selling';
        if (r.applicableFor.isNotEmpty &&
            !applicableForOptions(selling: r.selling, buying: r.buying)
                .contains(r.applicableFor)) {
          r.applicableFor = '';
          r.party = null;
        }
      });

  void setApplicableFor(String option) => _edit((r) {
        final v = option == 'Everyone' ? '' : option;
        if (v != r.applicableFor) {
          r.applicableFor = v;
          r.party = null;
        }
      });

  Future<void> pickParty() async {
    final type = rule.value.applicableFor;
    if (!isEditable || type.isEmpty) return;
    final row = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: type,
        title: 'Select ${type.toLowerCase()}',
        columns: [DocTypePickerColumn(fieldname: 'name', label: type, isPrimary: true)],
      ),
    );
    if (row != null) _edit((r) => r.party = row['name'] as String);
  }

  void setApplyOn(String value) => _edit((r) {
        if (r.applyOn != value) {
          r.applyOn = value;
          r.targets = [];
        }
      });

  Future<void> addTarget() async {
    final current = rule.value;
    if (!isEditable || current.applyOn == 'Transaction') return;
    final isItem = current.applyOn == 'Item Code';
    final doctype = isItem ? 'Item' : current.applyOn;
    final row = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: doctype,
        title: 'Add ${doctype.toLowerCase()}',
        columns: [
          DocTypePickerColumn(fieldname: 'name', label: doctype, isPrimary: true),
          if (isItem)
            DocTypePickerColumn(fieldname: 'item_name', label: 'Name', isSecondary: true),
        ],
        extraFields: isItem ? const ['variant_of'] : const [],
        filters: isItem
            ? const [
                ['Item', 'disabled', '=', 0]
              ]
            : const [],
        enableBarcodeScan: isItem,
      ),
    );
    if (row == null) return;
    final value = row['name'] as String;
    if (current.targets.any((t) => t.value == value)) {
      GlobalSnackbar.info(message: '$value is already in this rule');
      return;
    }
    _edit((r) => r.targets = [
          ...r.targets,
          PricingRuleTarget(
            value: value,
            label: pricingLink(row['item_name']),
            variantOf: pricingLink(row['variant_of']),
          ),
        ]);
  }

  void removeTarget(int index) =>
      _edit((r) => r.targets = [...r.targets]..removeAt(index));

  /// Tap on a unit chip: clears a set unit ("Any unit"), otherwise picks one.
  Future<void> toggleTargetUom(int index) async {
    if (!isEditable) return;
    if (rule.value.targets[index].uom != null) {
      _edit((r) => r.targets[index].uom = null);
      return;
    }
    final row = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: 'UOM',
        title: 'Select unit',
        columns: [DocTypePickerColumn(fieldname: 'name', label: 'Unit', isPrimary: true)],
      ),
    );
    if (row != null) _edit((r) => r.targets[index].uom = row['name'] as String);
  }

  // ── Discount tab ─────────────────────────────────────────────────────

  void setRateOrDiscount(String value) {
    _edit((r) {
      r.rateOrDiscount = value;
      if (value == 'Rate') r.forPriceList = null;
    });
    _seeding = true;
    valueController.text = _show(_value(rule.value));
    _seeding = false;
  }

  Future<void> pickForPriceList() async {
    final r0 = rule.value;
    if (!isEditable || r0.rateOrDiscount == 'Rate') return;
    final row = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: 'Price List',
        title: 'Only for price list',
        columns: [
          DocTypePickerColumn(fieldname: 'name', label: 'Price list', isPrimary: true),
          DocTypePickerColumn(fieldname: 'currency', label: 'Currency', isSecondary: true),
        ],
        // Mirrors the desk query: same selling/buying flags and currency.
        filters: [
          ['Price List', 'enabled', '=', 1],
          ['Price List', 'selling', '=', r0.selling ? 1 : 0],
          ['Price List', 'buying', '=', r0.buying ? 1 : 0],
          if (r0.currency.isNotEmpty) ['Price List', 'currency', '=', r0.currency],
        ],
      ),
    );
    if (row != null) _edit((r) => r.forPriceList = row['name'] as String);
  }

  void clearForPriceList() => _edit((r) => r.forPriceList = null);

  void setApplyDiscountOn(String value) => _edit((r) => r.applyDiscountOn = value);

  // ── Conditions tab ───────────────────────────────────────────────────

  Future<void> pickDate(BuildContext context, String field) async {
    if (!isEditable) return;
    final current = parseFrappeDate(
        field == 'valid_from' ? rule.value.validFrom : rule.value.validUpto);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    _edit((r) => field == 'valid_from'
        ? r.validFrom = frappeDate(picked)
        : r.validUpto = frappeDate(picked));
  }

  void clearValidUpto() => _edit((r) => r.validUpto = null);

  Future<void> pickPriority(BuildContext context) async {
    if (!isEditable) return;
    final v = await showPriorityPicker(context, current: rule.value.priority);
    if (v == null) return;
    _edit((r) {
      r.priority = v;
      r.hasPriority = v.isNotEmpty;
    });
  }

  void setApplyMultiple(bool v) => _edit((r) => r.applyMultiplePricingRules = v);

  void setMixedConditions(bool v) => _edit((r) => r.mixedConditions = v);

  void setCumulative(bool v) => _edit((r) => r.isCumulative = v);

  Future<void> pickWarehouse() async {
    if (!isEditable) return;
    final row = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: 'Warehouse',
        title: 'Select warehouse',
        columns: [DocTypePickerColumn(fieldname: 'name', label: 'Warehouse', isPrimary: true)],
      ),
    );
    if (row != null) _edit((r) => r.warehouse = row['name'] as String);
  }

  void clearWarehouse() => _edit((r) => r.warehouse = null);

  // ── Save / delete / discard ──────────────────────────────────────────

  Future<void> saveDocument() async {
    if (isSaving.value || !isEditable) return;
    final errors = validatePricingRule(rule.value);
    fieldErrors.assignAll(errors);
    if (errors.isNotEmpty) {
      saveResult.value = SaveResult.error;
      GlobalSnackbar.error(message: errors.values.first);
      return;
    }
    if (checkStaleAndBlock()) return;

    isSaving.value = true;
    serverError.value = '';
    final data = rule.value.toJson();
    if (mode.value != 'new') data['modified'] = rule.value.modified;

    try {
      final res = mode.value == 'new'
          ? await _provider.createRule(data)
          : await _provider.updateRule(name, data);
      final saved = res.data is Map ? res.data['data'] : null;
      if (saved is Map && saved['name'] != null) name = saved['name'].toString();
      mode.value = 'edit';
      await fetchDocument();
      saveResult.value = SaveResult.success;
      GlobalSnackbar.success(message: 'Pricing rule saved');
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      saveResult.value = SaveResult.error;
      serverError.value = ItemFormController.parseServerMessage(e.response?.data);
      // A silent failure reads as a successful save; the banner can be off-screen.
      GlobalSnackbar.error(message: serverError.value);
    } catch (e) {
      saveResult.value = SaveResult.error;
      serverError.value = e.toString();
      GlobalSnackbar.error(message: serverError.value);
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
    final confirmed = await GlobalDialog.confirm(
      title: 'Delete pricing rule?',
      message: '${rule.value.title}. Delivery Notes already saved keep their '
          'discount; new ones will not get it.',
      confirmText: 'Delete',
      confirmColor: AppColors.red700,
      icon: Icons.delete_outline,
    );
    if (confirmed != true) return;
    if (await performDelete()) Get.back();
  }

  Future<bool> performDelete() async {
    if (isDeleting.value) return false;
    isDeleting.value = true;
    try {
      final res = await _provider.deleteRule(name);
      final ok = res.statusCode == 200 || res.statusCode == 202 || res.statusCode == 204;
      if (ok) {
        isDirty.value = false;
        GlobalSnackbar.success(message: 'Pricing rule deleted');
      } else {
        GlobalSnackbar.error(message: 'Failed to delete pricing rule');
      }
      return ok;
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to delete pricing rule: $e');
      return false;
    } finally {
      isDeleting.value = false;
    }
  }
}
