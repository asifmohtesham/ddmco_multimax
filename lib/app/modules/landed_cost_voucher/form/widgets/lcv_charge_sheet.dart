import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/modules/global_widgets/link_field_widget.dart';
import 'package:multimax/app/modules/global_widgets/link_search_sheet.dart';

Future<void> showLcvChargeSheet({
  required String company,
  LandedCostTaxesAndCharges? initial,
  Future<String?> Function()? defaultAccount,
  required ValueChanged<LandedCostTaxesAndCharges> onSaved,
}) =>
    Get.bottomSheet(
      LcvChargeSheet(
        company: company,
        initial: initial,
        defaultAccount: defaultAccount,
        onSaved: onSaved,
      ),
      isScrollControlled: true,
    );

/// Add or edit one landed-cost charge: description, amount, expense account.
/// A new charge's account is prefilled from [defaultAccount].
class LcvChargeSheet extends StatefulWidget {
  final String company;
  final LandedCostTaxesAndCharges? initial;
  final Future<String?> Function()? defaultAccount;
  final ValueChanged<LandedCostTaxesAndCharges> onSaved;

  const LcvChargeSheet({
    super.key,
    required this.company,
    this.initial,
    this.defaultAccount,
    required this.onSaved,
  });

  @override
  State<LcvChargeSheet> createState() => _LcvChargeSheetState();
}

class _LcvChargeSheetState extends State<LcvChargeSheet> {
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late final TextEditingController _account;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _description = TextEditingController(text: c?.description ?? '');
    _amount = TextEditingController(
        text: c == null ? '' : c.amount.toString());
    _account = TextEditingController(text: c?.expenseAccount ?? '');
    for (final t in [_description, _amount, _account]) {
      t.addListener(() => setState(() {}));
    }
    if (c == null && widget.defaultAccount != null) {
      widget.defaultAccount!().then((acc) {
        if (mounted && acc != null && _account.text.isEmpty) {
          _account.text = acc;
        }
      });
    }
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _account.dispose();
    super.dispose();
  }

  double get _amountValue => double.tryParse(_amount.text.trim()) ?? 0;

  bool get _valid =>
      _description.text.trim().isNotEmpty &&
      _amountValue > 0 &&
      _account.text.isNotEmpty;

  void _save() {
    final base = widget.initial;
    widget.onSaved(LandedCostTaxesAndCharges(
      name: base?.name ?? 'local_${DateTime.now().microsecondsSinceEpoch}',
      description: _description.text.trim(),
      amount: _amountValue,
      expenseAccount: _account.text,
      accountCurrency: base?.accountCurrency,
      exchangeRate: base?.exchangeRate ?? 1,
      baseAmount: _amountValue * (base?.exchangeRate ?? 1),
    ));
    // maybePop: never pops the root route when the sheet is hosted directly
    // (widget tests).
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null ? 'Add Charge' : 'Edit Charge',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Description *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(labelText: 'Amount *'),
            ),
            const SizedBox(height: 12),
            LinkFieldWidget(
              controller: _account,
              labelText: 'Expense Account',
              hintText: 'Select Account',
              prefixIcon: Icons.account_balance_outlined,
              isRequired: true,
              onTap: () => showLinkSearchSheet(
                doctype: 'Account',
                title: 'Expense Account',
                filters: {'company': widget.company, 'is_group': 0},
                onSelected: (acc) => _account.text = acc,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _valid ? _save : null,
              child: const Text('Save Charge'),
            ),
          ],
        ),
      ),
    );
  }
}
