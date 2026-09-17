import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/item_price_model.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doc_detail_row.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/modules/global_widgets/form_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/inline_banner.dart';
import 'package:multimax/app/modules/pricing/item_price/form/item_price_form_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';
import 'package:multimax/app/modules/pricing/widgets/money_field.dart';

class ItemPriceFormScreen extends GetView<ItemPriceFormController> {
  const ItemPriceFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final p = controller.price.value;
      final isNew = controller.mode.value == 'new';
      final editable = controller.isEditable;
      final dirty = controller.isDirty.value;
      final loading = controller.isLoading.value;
      final status = dirty
          ? 'Not Saved'
          : pricingStatusLabel(
              disabled: false, validity: itemPriceValidity(p, DateTime.now()));
      final title = p.itemName.isNotEmpty
          ? p.itemName
          : (isNew ? 'New item price' : 'Item Price');

      return PopScope(
        canPop: !dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop) await controller.confirmDiscard();
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: NestedScrollView(
            headerSliverBuilder: (ctx, _) => [
              DocTypeFormHeader(
                title: title,
                docType: 'Item Price',
                statusLabel: loading ? null : status,
                canSave: editable && dirty,
                isSaving: controller.isSaving.value,
                saveResult: controller.saveResult.value,
                onSave: editable ? controller.saveDocument : null,
                onReload: isNew ? null : controller.reloadDocument,
                extraActions: [
                  if (!isNew && !loading && !controller.notFound.value)
                    // Item Price delete roles == write roles (v15 DocPerm);
                    // PermissionService has no real delete check.
                    DocTypeGuard(
                      doctype: 'Item Price',
                      permType: 'write',
                      child: AsyncIconButton(
                        busy: controller.isDeleting,
                        onPressed: controller.deleteDocument,
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                ],
              ),
            ],
            body: loading
                ? const Center(child: CircularProgressIndicator())
                : controller.notFound.value
                    ? const Center(
                        child: FormEmptyState(
                          icon: Icons.search_off,
                          message: 'Item price not found or not accessible.',
                        ),
                      )
                    : _body(context, p, isNew, editable),
          ),
        ),
      );
    });
  }

  Widget _body(BuildContext context, ItemPrice p, bool isNew, bool editable) {
    final s = context.scheme;
    final e = controller.fieldErrors;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          12, 12, 12, 80 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mounted only when there is an error, and `animate: false` because
          // on device the entrance animation left the banner at zero height —
          // a failed save then looked like no feedback at all. Verified with a
          // probe widget: the rebuild fires, only the banner was collapsed.
          if (controller.serverError.value.isNotEmpty) ...[
            InlineBanner(
              visible: true,
              animate: false,
              type: BannerType.error,
              message: "Couldn't save\n${controller.serverError.value}",
            ),
            const SizedBox(height: 12),
          ],
          DocSectionCard(
            title: 'Price',
            margin: const EdgeInsets.only(bottom: 12),
            children: [
              DocPickerField(
                label: 'Item',
                icon: Icons.inventory_2_outlined,
                value: p.itemCode.isEmpty ? null : '${p.itemCode} · ${p.itemName}',
                placeholder: 'Select item',
                trailingIcon: isNew ? Icons.search : Icons.lock_outline,
                onTap: editable && isNew ? controller.pickItem : null,
              ),
              FieldErrorText(e['item_code']),
              const SizedBox(height: 12),
              DocPickerField(
                label: 'Price list',
                icon: Icons.sell_outlined,
                value: p.priceList.isEmpty ? null : p.priceList,
                helperText: p.priceList.isEmpty
                    ? null
                    : (controller.isSellingList ? 'Selling' : 'Buying'),
                onTap: editable ? () => controller.pickPriceList(context) : null,
              ),
              FieldErrorText(e['price_list']),
              const SizedBox(height: 12),
              MoneyField(
                label: 'Rate',
                controller: controller.rateController,
                prefix: controller.currency.isEmpty ? null : controller.currency,
                suffix: p.uom.isEmpty ? null : '/ ${p.uom}',
                readOnly: !editable,
                errorText: e['price_list_rate'],
              ),
              const SizedBox(height: 12),
              DocPickerField(
                label: 'Unit',
                icon: Icons.straighten,
                value: p.uom.isEmpty ? null : p.uom,
                helperText: isNew
                    ? "Item's stock unit · only the item's units are offered"
                    : null,
                onTap: editable && controller.itemUoms.isNotEmpty
                    ? () => controller.pickUom(context)
                    : null,
              ),
              FieldErrorText(e['uom']),
            ],
          ),
          DocSectionCard(
            title: 'Validity',
            margin: const EdgeInsets.only(bottom: 12),
            children: [
              Row(
                children: [
                  Expanded(
                    child: DocPickerField(
                      label: 'Valid from',
                      icon: Icons.event_outlined,
                      value: p.validFrom == null ? null : displayDate(p.validFrom),
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
                      value: p.validUpto == null ? null : displayDate(p.validUpto),
                      placeholder: 'No end date',
                      trailingIcon: Icons.edit_calendar_outlined,
                      onTap: editable
                          ? () => controller.pickDate(context, 'valid_upto')
                          : null,
                    ),
                  ),
                ],
              ),
              FieldErrorText(e['valid_upto']),
              if (editable && p.validUpto != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: controller.clearValidUpto,
                    child: const Text('No end date'),
                  ),
                ),
            ],
          ),
          DocSectionCard(
            title: 'More options',
            margin: EdgeInsets.zero,
            headerAction: IconButton(
              tooltip: controller.moreOpen.value ? 'Collapse' : 'Expand',
              icon: Icon(controller.moreOpen.value
                  ? Icons.expand_less
                  : Icons.expand_more),
              onPressed: controller.moreOpen.toggle,
            ),
            children: controller.moreOpen.value
                ? _moreOptions(context, p, editable)
                : [
                    Text(_moreSummary(p, editable),
                        style: TextStyle(fontSize: 12, color: s.textMuted)),
                  ],
          ),
          if (!editable)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Read-only · you can view prices but not change them',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: s.textSubtle),
              ),
            ),
        ],
      ),
    );
  }

  String _moreSummary(ItemPrice p, bool editable) {
    final set = [
      if (p.customer != null) 'Customer ${p.customer}',
      if (p.supplier != null) 'Supplier ${p.supplier}',
      if (p.batchNo != null) 'Batch ${p.batchNo}',
      if (p.leadTimeDays > 0) '${p.leadTimeDays} days lead time',
      if (p.packingUnit > 0) 'Packing unit ${p.packingUnit}',
    ];
    if (set.isNotEmpty) return set.join(' · ');
    return editable ? 'Customer, batch, lead time…' : 'None set';
  }

  List<Widget> _moreOptions(BuildContext context, ItemPrice p, bool editable) {
    final selling = controller.isSellingList;
    final party = selling ? p.customer : p.supplier;
    return [
      DocPickerField(
        label: selling ? 'Customer' : 'Supplier',
        icon: selling ? Icons.person_outline : Icons.local_shipping_outlined,
        value: party,
        placeholder: selling ? 'Any customer' : 'Any supplier',
        helperText: selling
            ? 'Only for selling price lists'
            : 'Only for buying price lists',
        trailingIcon: Icons.search,
        onTap: editable ? controller.pickParty : null,
      ),
      if (editable && party != null)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
              onPressed: controller.clearParty, child: const Text('Clear')),
        ),
      const SizedBox(height: 12),
      DocPickerField(
        label: 'Batch',
        icon: Icons.tag,
        value: p.batchNo,
        placeholder: 'Any batch',
        onTap: editable && p.itemCode.isNotEmpty ? controller.pickBatch : null,
      ),
      if (editable && p.batchNo != null)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
              onPressed: controller.clearBatch, child: const Text('Clear')),
        ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
              child: _intField(
                  controller.leadTimeController, 'Lead time (days)', editable)),
          const SizedBox(width: 10),
          Expanded(
              child: _intField(
                  controller.packingUnitController, 'Packing unit', editable)),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: controller.noteController,
        readOnly: !editable,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Note',
          border: OutlineInputBorder(),
        ),
      ),
      if (p.brand != null) ...[
        const SizedBox(height: 12),
        DocDetailRow(label: 'Brand', value: p.brand!),
      ],
    ];
  }

  Widget _intField(TextEditingController c, String label, bool editable) =>
      TextField(
        controller: c,
        readOnly: !editable,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          hintText: '0',
          border: const OutlineInputBorder(),
        ),
      );
}
