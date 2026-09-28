import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/global_widgets/link_search_sheet.dart';
import 'package:multimax/app/modules/global_widgets/option_picker_sheet.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/landed_cost_voucher_form_controller.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/lcv_rules.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/widgets/lcv_charge_sheet.dart';

/// One Landed Cost Voucher. Drafts are editable (receipts, charges, posting
/// date, Qty/Amount basis); ERPNext recomputes items and their allocated
/// charges on every save. Submitted, cancelled and manually distributed
/// vouchers are read-only. Cancel stays in Desk.
class LandedCostVoucherFormScreen
    extends GetView<LandedCostVoucherFormController> {
  const LandedCostVoucherFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final voucher = controller.voucher.value;
      final isLoading = controller.isLoading.value;
      // Read here, not inside headerSliverBuilder: NestedScrollView calls
      // that closure after this builder returns, so Obx would not track it.
      final editable = voucher != null && controller.isEditable;
      final isDirty = controller.isDirty.value;
      final isSaving = controller.isSaving.value;
      final saveResult = controller.saveResult.value;
      final isSubmitting = controller.isSubmitting.value;
      final canSubmit = controller.canSubmit;
      // The tab builders below run eagerly inside this Obx, so their reads of
      // receipts/charges/postingDate are tracked too.

      return PopScope(
        canPop: !isDirty,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await controller.confirmDiscard();
        },
        child: DefaultTabController(
          length: 4, // Details, Purchase Receipts, Items, Taxes
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: NestedScrollView(
              headerSliverBuilder: (ctx, _) => [
                DocTypeFormHeader(
                  title: voucher?.name ?? 'Loading...',
                  docType: 'Landed Cost Voucher',
                  statusLabel: voucher?.status,
                  docStatus: voucher?.docstatus ?? 0,
                  onReload: isLoading || controller.isNew
                      ? null
                      : controller.reloadDocument,
                  // Save while dirty; Submit once clean (SE convention).
                  onSave: editable && isDirty ? controller.saveDocument : null,
                  canSave: editable && isDirty,
                  isSaving: isSaving,
                  saveResult: saveResult,
                  onSubmit: controller.submitDocument,
                  canSubmit: canSubmit,
                  isSubmitting: isSubmitting,
                  bottom: const TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(text: 'Details'),
                      Tab(text: 'Purchase Receipts'),
                      Tab(text: 'Items'),
                      Tab(text: 'Taxes'),
                    ],
                  ),
                ),
              ],
              body: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : voucher == null
                      ? const Center(child: Text('Document not found.'))
                      : TabBarView(
                          children: [
                            _buildDetailsView(context, editable),
                            _buildPurchaseReceiptsView(context, editable),
                            _buildItemsView(context),
                            _buildTaxesView(context, editable),
                          ],
                        ),
            ),
          ),
        ),
      );
    });
  }

  String _getLabel(String fieldname, String fallback) {
    if (controller.isMetaLoaded.value) {
      final fields = controller.docMeta['fields'] as List?;
      if (fields != null) {
        final field = fields.firstWhere(
            (f) => f['fieldname'] == fieldname,
            orElse: () => null);
        if (field != null && field['label'] != null) {
          return field['label'];
        }
      }
    }
    return fallback;
  }

  /// Bottom inset so the last row clears the system navigation bar.
  EdgeInsets _listPadding(BuildContext context, double all) =>
      EdgeInsets.fromLTRB(
          all, all, all, all + MediaQuery.of(context).padding.bottom);

  Future<void> _pickPostingDate(BuildContext context) async {
    DateTime initial;
    try {
      initial = DateFormat('yyyy-MM-dd').parse(controller.postingDate.value);
    } catch (_) {
      initial = DateTime.now();
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      controller.setPostingDate(DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  Widget _buildDetailsView(BuildContext context, bool editable) {
    final v = controller.voucher.value;
    if (v == null) return const SizedBox();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return SingleChildScrollView(
      padding: _listPadding(context, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (v.docstatus == 0 && controller.isManualDistribution)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Charges on this voucher are distributed manually. '
                'Edit it in ERPNext Desk.',
                style: TextStyle(color: muted),
              ),
            ),
          DocSectionCard(
            title: 'General Information',
            children: [
              DocPickerField(
                label: _getLabel('company', 'Company'),
                value: v.company,
                icon: Icons.business,
              ),
              const SizedBox(height: 12),
              DocPickerField(
                label: _getLabel('posting_date', 'Posting Date'),
                value: controller.postingDate.value,
                icon: Icons.calendar_today_outlined,
                onTap: editable ? () => _pickPostingDate(context) : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          DocSectionCard(
            title: 'Settings',
            children: [
              DocPickerField(
                label: _getLabel('distribute_charges_based_on',
                    'Distribute Charges Based On'),
                value: controller.distributeChargesBasedOn.value,
                icon: Icons.calculate_outlined,
                onTap: editable
                    ? () => showOptionPickerSheet(
                          context,
                          title: 'Distribute Charges Based On',
                          options: kLcvDistributionOptions,
                          selected: controller.distributeChargesBasedOn.value,
                          onSelected: controller.setDistribution,
                        )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          DocSectionCard(
            title: 'Totals',
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Taxes and Charges',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(FormattingHelper.formatAmount(controller.totalCharges)),
                ],
              ),
              if (v.totalVendorInvoicesCost != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Vendor Invoices Cost',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(FormattingHelper.formatAmount(
                        v.totalVendorInvoicesCost ?? 0.0)),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _addButton(String label, VoidCallback? onPressed, {bool busy = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          onPressed: busy ? null : onPressed,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add),
          label: Text(label),
        ),
      );

  Widget _buildPurchaseReceiptsView(BuildContext context, bool editable) {
    final receipts = controller.receipts;
    return ListView(
      padding: _listPadding(context, 12),
      children: [
        if (editable)
          _addButton(
            'Add Purchase Receipt',
            () => showLinkSearchSheet(
              doctype: kLcvReceiptType,
              title: 'Purchase Receipt',
              filters: {'docstatus': 1, 'company': controller.company},
              onSelected: controller.addReceipt,
            ),
            busy: controller.isAddingReceipt.value,
          ),
        if (receipts.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: Text('No Purchase Receipts')),
          ),
        for (final pr in receipts)
          Card(
            child: ListTile(
              title: Text(pr.receiptDocument),
              subtitle: Text(pr.supplier ?? 'No Supplier'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(FormattingHelper.formatAmount(pr.grandTotal)),
                  if (editable)
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close),
                      onPressed: () => controller.removeReceipt(pr),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Each row shows the charge ERPNext allocated to that item — the figure
  /// a Landed Cost Voucher exists to produce. Items are server-derived, so
  /// after a receipt change they appear on the next save.
  Widget _buildItemsView(BuildContext context) {
    final v = controller.voucher.value;
    if (v == null || v.items.isEmpty) {
      return const Center(
          child: Text('No Items yet — they are filled in when you save'));
    }

    return ListView.builder(
      padding: _listPadding(context, 12),
      itemCount: v.items.length,
      itemBuilder: (context, index) {
        final item = v.items[index];
        return Card(
          child: ListTile(
            title: Text(item.itemCode),
            subtitle: Text(
              '${item.description ?? ''}\n'
              '${item.receiptDocument} · Qty ${FormattingHelper.formatQty(item.qty)}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing:
                Text(FormattingHelper.formatAmount(item.applicableCharges)),
          ),
        );
      },
    );
  }

  Widget _buildTaxesView(BuildContext context, bool editable) {
    final charges = controller.charges;

    void openSheet({LandedCostTaxesAndCharges? initial, int? index}) =>
        showLcvChargeSheet(
          company: controller.company,
          initial: initial,
          defaultAccount: controller.defaultChargeAccount,
          onSaved: (c) => controller.upsertCharge(c, index: index),
        );

    return ListView(
      padding: _listPadding(context, 12),
      children: [
        if (editable) _addButton('Add Charge', () => openSheet()),
        if (charges.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: Text('No Taxes and Charges')),
          ),
        for (var i = 0; i < charges.length; i++)
          Card(
            child: ListTile(
              title: Text(charges[i].description),
              subtitle:
                  Text('Expense Account: ${charges[i].expenseAccount ?? 'N/A'}'),
              onTap: editable
                  ? () => openSheet(initial: charges[i], index: i)
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(FormattingHelper.formatAmount(charges[i].amount)),
                  if (editable)
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close),
                      onPressed: () => controller.removeCharge(i),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
