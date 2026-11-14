import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doc_detail_row.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/modules/global_widgets/form_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/inline_banner.dart';
import 'package:multimax/app/modules/global_widgets/option_picker_sheet.dart';
import 'package:multimax/app/modules/global_widgets/settings_controls.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/form/pricing_rule_form_controller.dart';
import 'package:multimax/app/modules/pricing/widgets/money_field.dart';
import 'package:multimax/app/modules/pricing/widgets/rule_summary_card.dart';
import 'package:multimax/app/modules/pricing/widgets/target_list_editor.dart';

class PricingRuleFormScreen extends GetView<PricingRuleFormController> {
  const PricingRuleFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Obx(() {
        final r = controller.rule.value;
        final isNew = controller.mode.value == 'new';
        final editable = controller.isEditable;
        final dirty = controller.isDirty.value;
        final loading = controller.isLoading.value;
        final title = r.title.trim().isNotEmpty
            ? r.title
            : (isNew ? 'New pricing rule' : controller.name);

        return PopScope(
          canPop: !dirty || !editable,
          onPopInvokedWithResult: (didPop, _) async {
            if (!didPop) await controller.confirmDiscard();
          },
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: NestedScrollView(
              headerSliverBuilder: (ctx, _) => [
                DocTypeFormHeader(
                  title: title,
                  docType: 'Pricing Rule',
                  statusLabel: loading
                      ? null
                      : (dirty && editable)
                          ? 'Not Saved'
                          : pricingRuleStatus(r, DateTime.now()),
                  canSave: editable && dirty,
                  isSaving: controller.isSaving.value,
                  saveResult: controller.saveResult.value,
                  onSave: editable ? controller.saveDocument : null,
                  onReload: isNew ? null : controller.reloadDocument,
                  extraActions: [
                    if (!isNew && !loading && !controller.notFound.value)
                      // Pricing Rule delete roles == write roles (v15 DocPerm);
                      // PermissionService has no real delete check.
                      DocTypeGuard(
                        doctype: 'Pricing Rule',
                        permType: 'write',
                        child: AsyncIconButton(
                          busy: controller.isDeleting,
                          onPressed: controller.deleteDocument,
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                  ],
                  bottom: TabBar(
                    tabs: [
                      Tab(child: _TabLabel('Rule', controller.tabHasError(0))),
                      Tab(child: _TabLabel('Discount', controller.tabHasError(1))),
                      Tab(child: _TabLabel('Conditions', controller.tabHasError(2))),
                    ],
                  ),
                ),
              ],
              body: loading
                  ? const Center(child: CircularProgressIndicator())
                  : controller.notFound.value
                      ? const Center(
                          child: FormEmptyState(
                            icon: Icons.search_off,
                            message: 'Pricing rule not found or not accessible.',
                          ),
                        )
                      : const TabBarView(
                          children: [_RuleTab(), _DiscountTab(), _ConditionsTab()],
                        ),
            ),
          ),
        );
      }),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel(this.label, this.hasError);

  final String label;
  final bool hasError;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (hasError) ...[
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: AppColors.red300, shape: BoxShape.circle),
            ),
          ],
        ],
      );
}

EdgeInsets _tabPadding(BuildContext context) => EdgeInsets.fromLTRB(
    12, 12, 12, 24 + MediaQuery.of(context).padding.bottom);

/// Banners + summary card at the top of every tab.
List<Widget> _prelude(PricingRuleFormController c, PricingRule r,
    {bool showLabel = false}) {
  return [
    if ((r.promotionalScheme ?? '').isNotEmpty) ...[
      InlineBanner(
        visible: true,
        type: BannerType.info,
        icon: Icons.lock_outline,
        message:
            'Locked · Promotional Scheme “${r.promotionalScheme}” overwrites edits. Open it on desktop.',
      ),
      const SizedBox(height: 12),
    ],
    if (c.serverError.value.isNotEmpty) ...[
      InlineBanner(
        visible: true,
        type: BannerType.error,
        message: "Couldn't save\n${c.serverError.value}",
      ),
      const SizedBox(height: 12),
    ],
    RuleSummaryCard(text: describePricingRule(r), showLabel: showLabel),
    const SizedBox(height: 12),
  ];
}

Widget _numField(TextEditingController ctrl, String label, bool editable,
        {String? error, String? prefix}) =>
    TextField(
      controller: ctrl,
      readOnly: !editable,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [decimalInputFormatter],
      decoration: InputDecoration(
        labelText: label,
        hintText: '0',
        prefixText: prefix == null ? null : '$prefix ',
        errorText: error,
        errorMaxLines: 2,
        border: const OutlineInputBorder(),
      ),
    );

class _RuleTab extends GetView<PricingRuleFormController> {
  const _RuleTab();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final r = controller.rule.value;
      final e = controller.fieldErrors;
      final editable = controller.isEditable;
      final s = context.scheme;
      final forValue = r.applicableFor.isEmpty ? 'Everyone' : r.applicableFor;
      return ListView(
        padding: _tabPadding(context),
        children: [
          ..._prelude(controller, r),
          DocSectionCard(
            title: 'Rule',
            margin: const EdgeInsets.only(bottom: 12),
            headerAction: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r.disable ? 'Disabled' : 'Enabled',
                    style: TextStyle(fontSize: 11, color: s.textMuted)),
                Switch(
                  value: !r.disable,
                  onChanged: editable ? controller.setEnabled : null,
                ),
              ],
            ),
            children: [
              TextField(
                controller: controller.titleController,
                readOnly: !editable,
                decoration: InputDecoration(
                  labelText: 'Title',
                  errorText: e['title'],
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DocPickerField(
                label: 'Side',
                icon: r.buying && !r.selling
                    ? Icons.local_shipping_outlined
                    : Icons.storefront_outlined,
                value: controller.sideLabel,
                onTap: editable
                    ? () => showOptionPickerSheet(
                          context,
                          title: 'Side',
                          options: const ['Selling', 'Buying', 'Selling & Buying'],
                          selected: controller.sideLabel,
                          onSelected: controller.setSide,
                        )
                    : null,
              ),
              FieldErrorText(e['selling']),
              const SizedBox(height: 12),
              DocPickerField(
                label: 'For',
                icon: Icons.groups_outlined,
                value: forValue,
                onTap: editable
                    ? () => showOptionPickerSheet(
                          context,
                          title: 'For',
                          options: controller.forOptions,
                          selected: forValue,
                          onSelected: controller.setApplicableFor,
                        )
                    : null,
              ),
              FieldErrorText(e['applicable_for']),
              if (r.applicableFor.isNotEmpty) ...[
                const SizedBox(height: 12),
                DocPickerField(
                  label: r.applicableFor,
                  icon: Icons.search,
                  value: r.party,
                  placeholder: 'Select ${r.applicableFor.toLowerCase()}',
                  trailingIcon: Icons.search,
                  onTap: editable ? controller.pickParty : null,
                ),
                FieldErrorText(e['party']),
              ],
            ],
          ),
          DocSectionCard(
            title: 'Applies on',
            margin: EdgeInsets.zero,
            headerAction: r.applyOn == 'Transaction'
                ? null
                : Text('${r.targets.length}',
                    style: TextStyle(fontSize: 11, color: s.textSubtle)),
            children: [
              SettingsSegmented<String>(
                options: [
                  for (final entry
                      in PricingRuleFormController.kApplyOnLabels.entries)
                    SegmentOption(value: entry.key, label: entry.value),
                ],
                value: r.applyOn,
                onChanged: editable ? controller.setApplyOn : (_) {},
              ),
              const SizedBox(height: 12),
              if (r.applyOn == 'Transaction')
                Text('Applies to the whole Delivery Note.',
                    style: TextStyle(fontSize: 12, color: s.textMuted))
              else
                TargetListEditor(
                  targets: r.targets,
                  applyOn: r.applyOn,
                  readOnly: !editable,
                  onAdd: controller.addTarget,
                  onRemove: controller.removeTarget,
                  onPickUom: controller.toggleTargetUom,
                ),
              FieldErrorText(e['targets']),
            ],
          ),
        ],
      );
    });
  }
}

class _DiscountTab extends GetView<PricingRuleFormController> {
  const _DiscountTab();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final r = controller.rule.value;
      final e = controller.fieldErrors;
      final editable = controller.isEditable;
      final rod = r.rateOrDiscount.isEmpty ? 'Discount Percentage' : r.rateOrDiscount;
      return ListView(
        padding: _tabPadding(context),
        children: [
          ..._prelude(controller, r, showLabel: true),
          DocSectionCard(
            title: 'What it gives',
            margin: EdgeInsets.zero,
            children: [
              // Product (free item) editing is desktop-only in v1.
              SettingsSegmented<String>(
                options: const [
                  SegmentOption(value: 'Price', label: 'Price'),
                  SegmentOption(value: 'Product', label: 'Product'),
                ],
                value: r.priceOrProductDiscount,
                onChanged: (_) {},
              ),
              const SizedBox(height: 12),
              if (r.priceOrProductDiscount == 'Product') ...[
                DocPickerField(
                  label: 'Free item',
                  icon: Icons.card_giftcard_outlined,
                  value: r.sameItem ? 'Same item' : r.freeItem,
                  helperText: 'Qty ${r.freeQty == r.freeQty.roundToDouble() ? r.freeQty.toInt() : r.freeQty}',
                ),
                const SizedBox(height: 12),
                const InlineBanner(
                  visible: true,
                  type: BannerType.info,
                  message:
                      'Product rules are read-only in the app. Free-item rules are set up and changed on desktop.',
                ),
              ] else ...[
                SettingsSegmented<String>(
                  options: const [
                    SegmentOption(value: 'Rate', label: 'Rate'),
                    SegmentOption(value: 'Discount Percentage', label: 'Discount %'),
                    SegmentOption(value: 'Discount Amount', label: 'Amount'),
                  ],
                  value: rod,
                  onChanged: editable ? controller.setRateOrDiscount : (_) {},
                ),
                FieldErrorText(e['rate_or_discount']),
                const SizedBox(height: 12),
                MoneyField(
                  key: ValueKey(rod),
                  label: switch (rod) {
                    'Rate' => 'Rate',
                    'Discount Amount' => 'Discount amount',
                    _ => 'Discount',
                  },
                  controller: controller.valueController,
                  prefix: rod == 'Discount Percentage' || r.currency.isEmpty
                      ? null
                      : r.currency,
                  suffix: switch (rod) {
                    'Rate' => '/ unit',
                    'Discount Amount' => 'per unit',
                    _ => '%',
                  },
                  decimals: rod == 'Discount Percentage' ? null : 2,
                  readOnly: !editable,
                  errorText: e['rate'] ?? e['discount_percentage'] ?? e['discount_amount'],
                ),
                if (rod != 'Rate') ...[
                  const SizedBox(height: 12),
                  DocPickerField(
                    label: 'Only for price list',
                    icon: Icons.sell_outlined,
                    value: r.forPriceList,
                    placeholder: 'Any price list',
                    helperText: r.forPriceList == null
                        ? 'Leave empty to apply on every list'
                        : 'Lines priced from other lists are not discounted',
                    onTap: editable ? controller.pickForPriceList : null,
                  ),
                  if (editable && r.forPriceList != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: controller.clearForPriceList,
                        child: const Text('Any price list'),
                      ),
                    ),
                ],
                if (r.applyOn == 'Transaction' && rod != 'Rate') ...[
                  const SizedBox(height: 12),
                  DocPickerField(
                    label: 'Apply discount on',
                    icon: Icons.receipt_long_outlined,
                    value: r.applyDiscountOn,
                    onTap: editable
                        ? () => showOptionPickerSheet(
                              context,
                              title: 'Apply discount on',
                              options: const ['Grand Total', 'Net Total'],
                              selected: r.applyDiscountOn,
                              onSelected: controller.setApplyDiscountOn,
                            )
                        : null,
                  ),
                ],
              ],
            ],
          ),
        ],
      );
    });
  }
}

class _ConditionsTab extends GetView<PricingRuleFormController> {
  const _ConditionsTab();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final r = controller.rule.value;
      final e = controller.fieldErrors;
      final editable = controller.isEditable;
      final s = context.scheme;
      final dark = Theme.of(context).brightness == Brightness.dark;
      final warnInk = dark ? AppColors.orange300 : AppColors.orange700;
      return ListView(
        padding: _tabPadding(context),
        children: [
          ..._prelude(controller, r),
          DocSectionCard(
            title: 'When',
            margin: const EdgeInsets.only(bottom: 12),
            children: [
              Row(
                children: [
                  Expanded(
                    child: DocPickerField(
                      label: 'Valid from',
                      icon: Icons.event_outlined,
                      value: r.validFrom == null ? null : displayDate(r.validFrom),
                      placeholder: 'Any date',
                      trailingIcon: Icons.edit_calendar_outlined,
                      onTap: editable
                          ? () => controller.pickDate(context, 'valid_from')
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DocPickerField(
                      label: 'Valid upto',
                      icon: Icons.event_outlined,
                      value: r.validUpto == null ? null : displayDate(r.validUpto),
                      placeholder: 'No end date',
                      trailingIcon: Icons.edit_calendar_outlined,
                      onTap: editable
                          ? () => controller.pickDate(context, 'valid_upto')
                          : null,
                    ),
                  ),
                ],
              ),
              FieldErrorText(e['valid_from'] ?? e['valid_upto']),
              if (editable && r.validUpto != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: controller.clearValidUpto,
                    child: const Text('No end date'),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _numField(controller.minQtyController, 'Min qty', editable)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _numField(controller.maxQtyController, 'Max qty', editable,
                          error: e['max_qty'])),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _numField(controller.minAmtController, 'Min amount', editable,
                          prefix: r.currency.isEmpty ? null : r.currency)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _numField(controller.maxAmtController, 'Max amount', editable,
                          prefix: r.currency.isEmpty ? null : r.currency,
                          error: e['max_amt'])),
                ],
              ),
              const SizedBox(height: 6),
              Text('0 = no limit', style: TextStyle(fontSize: 11, color: s.textMuted)),
            ],
          ),
          DocSectionCard(
            title: 'Priority',
            margin: const EdgeInsets.only(bottom: 12),
            children: [
              DocPickerField(
                label: 'Priority',
                icon: Icons.swap_vert,
                value: r.hasPriority && r.priority.isNotEmpty ? r.priority : null,
                placeholder: 'Not set',
                helperText: '1–20. When several rules match one line, the higher number wins.',
                onTap: editable ? () => controller.pickPriority(context) : null,
              ),
              FieldErrorText(e['priority']),
              if (!r.hasPriority)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 14, color: warnInk),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          "No priority set. If another rule matches the same Delivery Note line at the same priority, that note can't be saved.",
                          style: TextStyle(fontSize: 11, height: 1.35, color: warnInk),
                        ),
                      ),
                    ],
                  ),
                ),
              SettingsSwitchRow(
                title: 'Apply multiple rules',
                subtitle: 'Let other matching rules stack on top of this one',
                value: r.applyMultiplePricingRules,
                onChanged: editable ? controller.setApplyMultiple : (_) {},
              ),
              if (r.applyOn != 'Transaction') ...[
                SettingsSwitchRow(
                  title: 'Mixed conditions',
                  subtitle: 'Apply the qty and amount limits to the selected items combined',
                  value: r.mixedConditions,
                  onChanged: editable ? controller.setMixedConditions : (_) {},
                ),
                SettingsSwitchRow(
                  title: 'Cumulative',
                  subtitle: 'Count quantities across transactions in the validity period',
                  value: r.isCumulative,
                  onChanged: editable ? controller.setCumulative : (_) {},
                ),
              ],
            ],
          ),
          if (r.applyOn != 'Transaction')
            DocSectionCard(
              title: 'Warehouse',
              margin: const EdgeInsets.only(bottom: 12),
              children: [
                DocPickerField(
                  label: 'Warehouse',
                  icon: Icons.warehouse_outlined,
                  value: r.warehouse,
                  placeholder: 'Any warehouse',
                  onTap: editable ? controller.pickWarehouse : null,
                ),
                if (editable && r.warehouse != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: controller.clearWarehouse,
                      child: const Text('Any warehouse'),
                    ),
                  ),
              ],
            ),
          if (r.hasAdvanced)
            DocSectionCard(
              title: 'Advanced (read-only)',
              margin: EdgeInsets.zero,
              children: [
                if ((r.condition ?? '').isNotEmpty)
                  DocDetailRow(label: 'Condition', value: r.condition!),
                if (r.couponCodeBased)
                  const DocDetailRow(label: 'Coupon code based', value: 'Yes'),
                if (r.isRecursive) const DocDetailRow(label: 'Recursive', value: 'Yes'),
                if (r.marginRateOrAmount != 0)
                  DocDetailRow(
                      label: 'Margin',
                      value: '${r.marginType ?? ''} ${r.marginRateOrAmount}'.trim()),
                if (r.validateAppliedRule)
                  const DocDetailRow(label: 'Validate applied rule', value: 'Yes'),
                if (r.thresholdPercentage != 0)
                  DocDetailRow(
                      label: 'Suggestion threshold', value: '${r.thresholdPercentage}%'),
                if (r.applyDiscountOnRate)
                  const DocDetailRow(label: 'Discount on discounted rate', value: 'Yes'),
              ],
            ),
        ],
      );
    });
  }
}
