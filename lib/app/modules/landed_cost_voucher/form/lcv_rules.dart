import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';

/// The only receipt type the app links; Purchase Invoices stay in Desk.
const String kLcvReceiptType = 'Purchase Receipt';

const String kLcvManualDistribution = 'Distribute Manually';

/// Bases the app can edit. Manual distribution needs per-item charge entry,
/// which stays in Desk, so such vouchers open read-only.
const List<String> kLcvDistributionOptions = ['Qty', 'Amount'];

bool lcvIsEditable({
  required int? docStatus,
  required String distributeChargesBasedOn,
}) =>
    docStatus == 0 && distributeChargesBasedOn != kLcvManualDistribution;

/// A voucher may be submitted only when it is a saved, clean draft the user
/// is permitted to submit, with no save/submit already running.
bool lcvCanSubmit({
  required bool isNew,
  required int? docStatus,
  required bool isDirty,
  required bool isSaving,
  required bool isSubmitting,
  required bool canSubmitPerm,
}) =>
    !isNew &&
    docStatus == 0 &&
    !isDirty &&
    !isSaving &&
    !isSubmitting &&
    canSubmitPerm;

/// Why [receipt] (a Purchase Receipt summary with `name`, `docstatus` and
/// `company`) cannot be added, or null if it can. Mirrors the checks ERPNext
/// runs on save so the user hears about them at pick time.
String? lcvReceiptRejection({
  required Map<String, dynamic> receipt,
  required String company,
  required Iterable<String> alreadyAdded,
}) {
  final name = receipt['name'] as String? ?? '';
  if (alreadyAdded.contains(name)) return '$name is already on this voucher';
  if (receipt['docstatus'] != 1) return '$name is not submitted';
  final owner = receipt['company'] as String? ?? '';
  if (owner != company) return '$name belongs to $owner, not $company';
  return null;
}

/// The first reason the voucher cannot be saved yet, or null.
String? lcvSaveBlocker({
  required List<LandedCostPurchaseReceipt> receipts,
  required List<LandedCostTaxesAndCharges> charges,
}) {
  if (receipts.isEmpty) return 'Add at least one Purchase Receipt';
  if (charges.isEmpty) return 'Add at least one charge';
  for (final c in charges) {
    if (c.description.trim().isEmpty || c.amount <= 0) {
      return 'Every charge needs a description and an amount above zero';
    }
    if ((c.expenseAccount ?? '').isEmpty) {
      return 'Every charge needs an expense account';
    }
  }
  return null;
}

/// Builds the save body.
///
/// ERPNext fills `items` from the linked receipts only when that table is
/// empty, and re-spreads the charges across items on every save. So when
/// the receipt set changed we send `items: []` to make the server rebuild
/// them; otherwise we send the existing rows back untouched.
Map<String, dynamic> buildLcvPayload({
  required String company,
  required String postingDate,
  required String distributeChargesBasedOn,
  required List<LandedCostPurchaseReceipt> receipts,
  required List<LandedCostTaxesAndCharges> charges,
  required List<LandedCostItem> items,
  required bool receiptsChanged,
  String? modified,
}) {
  bool isServerRow(String? name) => name != null && !name.startsWith('local_');

  return {
    'company': company,
    'posting_date': postingDate,
    'distribute_charges_based_on': distributeChargesBasedOn,
    if (modified != null && modified.isNotEmpty) 'modified': modified,
    'purchase_receipts': [
      for (final r in receipts)
        {
          if (isServerRow(r.name)) 'name': r.name,
          'receipt_document_type': r.receiptDocumentType,
          'receipt_document': r.receiptDocument,
          if (r.supplier != null) 'supplier': r.supplier,
          if (r.postingDate != null) 'posting_date': r.postingDate,
          'grand_total': r.grandTotal,
        },
    ],
    'taxes': [
      for (final c in charges)
        {
          if (isServerRow(c.name)) 'name': c.name,
          'description': c.description,
          'amount': c.amount,
          if (c.expenseAccount != null) 'expense_account': c.expenseAccount,
        },
    ],
    'items': receiptsChanged
        ? <Map<String, dynamic>>[]
        : [for (final i in items) i.toJson()],
  };
}
