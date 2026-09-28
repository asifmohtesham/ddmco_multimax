import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/landed_cost_voucher_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';

/// Read-only view of one Landed Cost Voucher. Every field is display-only;
/// vouchers are created, edited and submitted in ERPNext Desk.
class LandedCostVoucherFormScreen
    extends GetView<LandedCostVoucherFormController> {
  const LandedCostVoucherFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final voucher = controller.voucher.value;
      final isLoading = controller.isLoading.value;

      return DefaultTabController(
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
                onReload: isLoading ? null : controller.fetchDocument,
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

  Widget _buildDetailsView(BuildContext context) {
    final v = controller.voucher.value;
    if (v == null) return const SizedBox();

    return SingleChildScrollView(
      padding: _listPadding(context, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                value: v.postingDate,
                icon: Icons.calendar_today_outlined,
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
                value: v.distributeChargesBasedOn,
                icon: Icons.calculate_outlined,
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
      padding: _listPadding(context, 12),
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

  /// Each row shows the charge ERPNext allocated to that item — the figure
  /// a Landed Cost Voucher exists to produce.
  Widget _buildItemsView(BuildContext context) {
    final v = controller.voucher.value;
    if (v == null || v.items.isEmpty) {
      return const Center(child: Text('No Items'));
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
            trailing: Text(FormattingHelper.formatAmount(item.applicableCharges)),
          ),
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
      padding: _listPadding(context, 12),
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
