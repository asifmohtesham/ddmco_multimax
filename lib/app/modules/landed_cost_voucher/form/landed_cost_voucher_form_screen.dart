import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/landed_cost_voucher_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/app/modules/global_widgets/link_field_widget.dart';
import 'package:multimax/app/modules/global_widgets/link_search_sheet.dart';
import 'package:multimax/app/shared/item_card/doc_item_card.dart';
import 'package:multimax/app/shared/item_card/item_card_data.dart';

class LandedCostVoucherFormScreen
    extends GetView<LandedCostVoucherFormController> {
  const LandedCostVoucherFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final voucher = controller.voucher.value;
      final isLoading = controller.isLoading.value;
      final isSaving = controller.isSaving.value;
      final isDirty = controller.isDirty.value;

      final title = controller.mode == 'new'
          ? 'New Landed Cost Voucher'
          : (voucher?.name ?? 'Loading...');

      return PopScope(
        canPop: !isDirty,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          // Add discard confirmation dialog logic if needed
        },
        child: DefaultTabController(
          length: 4, // Details, Purchase Receipts, Items, Taxes
          child: Scaffold(
            body: NestedScrollView(
              headerSliverBuilder: (ctx, _) => [
                DocTypeFormHeader(
                  title: title,
                  docType: 'Landed Cost Voucher',
                  statusLabel: voucher?.status,
                  docStatus: voucher?.docstatus ?? 0,
                  canSave: isDirty,
                  isSaving: isSaving,
                  onSave: (voucher?.docstatus == 0 && isDirty)
                      ? controller.saveDocument
                      : null,
                  onReload: (controller.mode != 'new' && !isDirty)
                      ? controller.fetchDocument
                      : null,
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
                        _buildDetailsView(context),
                        _buildPurchaseReceiptsView(context),
                        _buildItemsView(context),
                        _buildTaxesView(context),
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

  Widget _buildDetailsView(BuildContext context) {
    final v = controller.voucher.value;
    if (v == null) return const SizedBox();
    final isEditable = v.docstatus == 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DocSectionCard(
            title: 'General Information',
            children: [
              LinkFieldWidget(
                controller: controller.companyController,
                labelText: _getLabel('company', 'Company'),
                hintText: 'Select Company',
                prefixIcon: Icons.business,
                isReadOnly: !isEditable,
                onTap: () {
                  if (!isEditable) return;
                  showLinkSearchSheet(
                    doctype: 'Company',
                    title: 'Select Company',
                    onSelected: (val) {
                      controller.companyController.text = val;
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DocPickerField(
                      label: _getLabel('posting_date', 'Posting Date'),
                      value: controller.postingDateController.text,
                      icon: Icons.calendar_today_outlined,
                      trailingIcon: Icons.edit_calendar_outlined,
                      onTap: isEditable ? () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          controller.postingDateController.text =
                              '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                        }
                      } : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          DocSectionCard(
            title: 'Settings',
            children: [
              DocPickerField(
                label: _getLabel('distribute_charges_based_on', 'Distribute Charges Based On'),
                value: controller.distributeChargesController.text,
                icon: Icons.calculate_outlined,
                onTap: isEditable ? () {
                  // Usually a Select field picker
                  Get.bottomSheet(
                    Container(
                      color: Theme.of(context).colorScheme.surface,
                      child: SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: ['Qty', 'Amount', 'Dist. Manual']
                              .map((e) => ListTile(
                                    title: Text(e),
                                    onTap: () {
                                      controller.distributeChargesController.text = e;
                                      Get.back();
                                    },
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                  );
                } : null,
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
                  Text(FormattingHelper.formatAmount(v.totalTaxesAndCharges)),
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
                    Text(
                      FormattingHelper.formatAmount(
                        v.totalVendorInvoicesCost ?? 0.0,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseReceiptsView(BuildContext context) {
    final v = controller.voucher.value;
    if (v == null || v.purchaseReceipts.isEmpty) {
      return const Center(child: Text('No Purchase Receipts'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: v.purchaseReceipts.length,
      itemBuilder: (context, index) {
        final pr = v.purchaseReceipts[index];
        return Card(
          child: ListTile(
            title: Text(pr.receiptDocument),
            subtitle: Text(pr.supplier ?? 'No Supplier'),
            trailing: Text(FormattingHelper.formatAmount(pr.grandTotal)),
          ),
        );
      },
    );
  }

  Widget _buildItemsView(BuildContext context) {
    final v = controller.voucher.value;
    if (v == null || v.items.isEmpty) {
      return const Center(child: Text('No Items'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: v.items.length,
      itemBuilder: (context, index) {
        final item = v.items[index];
        final cardData = ItemCardData.fromLandedCostItem(
          item,
          index: index,
          isEditable: v.docstatus == 0,
        );

        return DocItemCard(
          data: cardData,
          onTap: v.docstatus == 0 ? () {} : null,
          onDelete: v.docstatus == 0 ? () {} : null,
        );
      },
    );
  }

  Widget _buildTaxesView(BuildContext context) {
    final v = controller.voucher.value;
    if (v == null || v.taxes.isEmpty) {
      return const Center(child: Text('No Taxes and Charges'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: v.taxes.length,
      itemBuilder: (context, index) {
        final tax = v.taxes[index];
        return Card(
          child: ListTile(
            title: Text(tax.description),
            subtitle: Text('Expense Account: ${tax.expenseAccount ?? 'N/A'}'),
            trailing: Text(FormattingHelper.formatAmount(tax.amount)),
          ),
        );
      },
    );
  }
}
