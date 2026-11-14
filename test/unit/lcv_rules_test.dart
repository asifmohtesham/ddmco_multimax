import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/lcv_rules.dart';

LandedCostPurchaseReceipt _receipt(String doc, {String? name}) =>
    LandedCostPurchaseReceipt(
      name: name,
      receiptDocumentType: kLcvReceiptType,
      receiptDocument: doc,
      supplier: 'Acme',
      postingDate: '2026-09-20',
      grandTotal: 1000,
    );

LandedCostTaxesAndCharges _charge({
  String? name,
  String description = 'Freight',
  double amount = 150,
  String? account = 'Freight - KA',
  String? accountCurrency,
  double exchangeRate = 1,
}) =>
    LandedCostTaxesAndCharges(
      name: name,
      description: description,
      amount: amount,
      expenseAccount: account,
      accountCurrency: accountCurrency,
      exchangeRate: exchangeRate,
      baseAmount: amount * exchangeRate,
    );

final _item = LandedCostItem(
  name: 'row-item-1',
  itemCode: 'WATCH-001',
  receiptDocumentType: kLcvReceiptType,
  receiptDocument: 'MAT-PRE-0001',
  qty: 10,
  rate: 100,
  amount: 1000,
  applicableCharges: 150,
  purchaseReceiptItem: 'pri-1',
  costCenter: 'Main - KA',
);

void main() {
  group('lcvIsEditable', () {
    test('only drafts with an automatic basis are editable', () {
      expect(lcvIsEditable(docStatus: 0, distributeChargesBasedOn: 'Qty'), isTrue);
      expect(lcvIsEditable(docStatus: 0, distributeChargesBasedOn: 'Amount'), isTrue);
      expect(lcvIsEditable(docStatus: 1, distributeChargesBasedOn: 'Qty'), isFalse);
      expect(lcvIsEditable(docStatus: 2, distributeChargesBasedOn: 'Qty'), isFalse);
      expect(lcvIsEditable(docStatus: null, distributeChargesBasedOn: 'Qty'), isFalse);
    });

    test('a manually distributed draft stays read-only', () {
      expect(
        lcvIsEditable(docStatus: 0, distributeChargesBasedOn: kLcvManualDistribution),
        isFalse,
      );
    });
  });

  group('lcvCanSubmit', () {
    bool can({
      bool isNew = false,
      int? docStatus = 0,
      bool isDirty = false,
      bool isSaving = false,
      bool isSubmitting = false,
      bool perm = true,
    }) =>
        lcvCanSubmit(
          isNew: isNew,
          docStatus: docStatus,
          isDirty: isDirty,
          isSaving: isSaving,
          isSubmitting: isSubmitting,
          canSubmitPerm: perm,
        );

    test('a clean saved draft with permission can be submitted', () {
      expect(can(), isTrue);
    });

    test('anything else cannot', () {
      expect(can(isNew: true), isFalse);
      expect(can(docStatus: 1), isFalse);
      expect(can(isDirty: true), isFalse);
      expect(can(isSaving: true), isFalse);
      expect(can(isSubmitting: true), isFalse);
      expect(can(perm: false), isFalse);
    });
  });

  group('lcvReceiptRejection', () {
    Map<String, dynamic> pr({int docstatus = 1, String company = 'KA'}) => {
          'name': 'MAT-PRE-0002',
          'docstatus': docstatus,
          'company': company,
        };

    test('a submitted receipt of the same company is accepted', () {
      expect(
        lcvReceiptRejection(receipt: pr(), company: 'KA', alreadyAdded: const []),
        isNull,
      );
    });

    test('duplicates, drafts, cancelled and other-company receipts are rejected', () {
      expect(
        lcvReceiptRejection(
            receipt: pr(), company: 'KA', alreadyAdded: const ['MAT-PRE-0002']),
        contains('already'),
      );
      expect(
        lcvReceiptRejection(receipt: pr(docstatus: 0), company: 'KA', alreadyAdded: const []),
        contains('not submitted'),
      );
      expect(
        lcvReceiptRejection(receipt: pr(docstatus: 2), company: 'KA', alreadyAdded: const []),
        contains('not submitted'),
      );
      expect(
        lcvReceiptRejection(receipt: pr(company: 'Other'), company: 'KA', alreadyAdded: const []),
        contains('Other'),
      );
    });
  });

  group('lcvSaveBlocker', () {
    test('needs a receipt and a complete charge', () {
      expect(lcvSaveBlocker(receipts: const [], charges: [_charge()]),
          contains('Purchase Receipt'));
      expect(lcvSaveBlocker(receipts: [_receipt('A')], charges: const []),
          contains('charge'));
      expect(lcvSaveBlocker(receipts: [_receipt('A')], charges: [_charge(amount: 0)]),
          contains('amount'));
      expect(lcvSaveBlocker(receipts: [_receipt('A')], charges: [_charge(description: ' ')]),
          contains('description'));
      expect(lcvSaveBlocker(receipts: [_receipt('A')], charges: [_charge(account: null)]),
          contains('expense account'));
      expect(lcvSaveBlocker(receipts: [_receipt('A')], charges: [_charge()]), isNull);
    });
  });

  group('buildLcvPayload', () {
    Map<String, dynamic> build({required bool receiptsChanged, String? modified}) =>
        buildLcvPayload(
          company: 'KA',
          postingDate: '2026-09-28',
          distributeChargesBasedOn: 'Amount',
          receipts: [
            _receipt('MAT-PRE-0001', name: 'row-pr-1'),
            _receipt('MAT-PRE-0002', name: 'local_123'),
          ],
          charges: [_charge(name: 'row-tax-1'), _charge(name: 'local_456')],
          items: [_item],
          receiptsChanged: receiptsChanged,
          modified: modified,
        );

    test('changed receipts make the server rebuild items', () {
      expect(build(receiptsChanged: true)['items'], isEmpty);
    });

    test('unchanged receipts send the existing item rows back', () {
      final items = build(receiptsChanged: false)['items'] as List;
      expect(items.single['name'], 'row-item-1');
      expect(items.single['purchase_receipt_item'], 'pri-1');
    });

    test('server row names are kept and local ones dropped', () {
      final p = build(receiptsChanged: false);
      final prs = p['purchase_receipts'] as List;
      expect(prs[0]['name'], 'row-pr-1');
      expect(prs[1].containsKey('name'), isFalse);
      expect(prs[1]['receipt_document_type'], 'Purchase Receipt');
      expect(prs[1]['supplier'], 'Acme');
      final taxes = p['taxes'] as List;
      expect(taxes[0]['name'], 'row-tax-1');
      expect(taxes[1].containsKey('name'), isFalse);
      expect(taxes[1]['expense_account'], 'Freight - KA');
    });

    test('a foreign-currency exchange rate and account currency are carried '
        'on the taxes rows (Final review, Finding 3)', () {
      final p = buildLcvPayload(
        company: 'KA',
        postingDate: '2026-09-28',
        distributeChargesBasedOn: 'Amount',
        receipts: [_receipt('MAT-PRE-0001', name: 'row-pr-1')],
        charges: [
          _charge(
            name: 'row-tax-1',
            accountCurrency: 'USD',
            exchangeRate: 83.5,
          ),
        ],
        items: const [],
        receiptsChanged: true,
      );
      final tax = (p['taxes'] as List).single;
      expect(tax['exchange_rate'], 83.5);
      expect(tax['account_currency'], 'USD');
    });

    test('header fields and the optimistic-lock timestamp are sent', () {
      final p = build(receiptsChanged: false, modified: '2026-09-28 10:00:00.000');
      expect(p['company'], 'KA');
      expect(p['posting_date'], '2026-09-28');
      expect(p['distribute_charges_based_on'], 'Amount');
      expect(p['modified'], '2026-09-28 10:00:00.000');
      expect(build(receiptsChanged: false).containsKey('modified'), isFalse);
    });
  });
}
