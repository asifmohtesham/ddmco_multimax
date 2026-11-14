import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/modules/delivery_note/form/so_pick.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';

/// Assigns each picked row of an SO-bound Delivery Note to a line of the
/// POS Upload (Sales Voucher) that was linked to the order after picking
/// began. Several rows may share one voucher line, up to its qty.
class VoucherAssignmentSheet extends StatefulWidget {
  final String uploadName;
  final List<DeliveryNoteItem> rows;
  final List<PosUploadItem> lines;
  final RxBool busy;

  /// Applies the assignment (row index → voucher line idx); returns an
  /// error message, or null once linked and saved.
  final Future<String?> Function(Map<int, int> assignment) onConfirm;

  const VoucherAssignmentSheet({
    super.key,
    required this.uploadName,
    required this.rows,
    required this.lines,
    required this.busy,
    required this.onConfirm,
  });

  @override
  State<VoucherAssignmentSheet> createState() => _VoucherAssignmentSheetState();
}

class _VoucherAssignmentSheetState extends State<VoucherAssignmentSheet> {
  final Map<int, int> _pick = {};
  String? _error;

  Map<int, double> get _lineQty =>
      {for (final l in widget.lines) l.idx: l.quantity.toDouble()};

  Map<int, double> get _assigned {
    final out = <int, double>{};
    _pick.forEach((row, line) =>
        out[line] = (out[line] ?? 0) + widget.rows[row].qty);
    return out;
  }

  Map<int, double> get _over => SoPick.overAllocatedLines(
      [for (final e in _pick.entries) (serial: e.value, qty: widget.rows[e.key].qty)],
      _lineQty);

  bool get _complete => _pick.length == widget.rows.length;

  static String _q(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

  Future<void> _confirm() async {
    if (!_complete) {
      setState(() => _error = 'Assign every row to a voucher line.');
      return;
    }
    final err = await widget.onConfirm(Map.of(_pick));
    if (!mounted) return;
    if (err == null) {
      Get.back();
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final errInk = isDark ? AppColors.red300 : AppColors.red700;
    final okInk = isDark ? AppColors.green300 : AppColors.green700;
    final assigned = _assigned;
    final over = _over;
    final bottom = MediaQuery.of(context).padding.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: scheme.fg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: scheme.borderStrong,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Assign voucher lines',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: scheme.text)),
                        const SizedBox(height: 2),
                        Text(
                            'Match each picked row to its line on '
                            'POS Upload ${widget.uploadName}.',
                            style: TextStyle(
                                fontSize: 13, color: scheme.textMuted)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Get.back(),
                    icon: Icon(Icons.close, color: scheme.textMuted),
                  ),
                ],
              ),
            ),
            // Voucher line fill — live, so over-allocation shows up front.
            Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final l in widget.lines)
                    _FillChip(
                      label: '#${l.idx} · ${_q(assigned[l.idx] ?? 0)}/${_q(l.quantity.toDouble())}',
                      ink: over.containsKey(l.idx)
                          ? errInk
                          : (assigned[l.idx] ?? 0) >= l.quantity
                              ? okInk
                              : scheme.textMuted,
                    ),
                ],
              ),
            ),
            Divider(color: scheme.border, height: 16),
            Expanded(
              child: Scrollbar(
                controller: scroll,
                child: ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  itemCount: widget.rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final r = widget.rows[i];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.subtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${r.itemCode} · ${r.itemName ?? ''}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.text)),
                          const SizedBox(height: 2),
                          Text(
                              'Qty ${_q(r.qty)}'
                              '${(r.batchNo ?? '').isEmpty ? '' : ' · ${r.batchNo}'}',
                              style: TextStyle(
                                  fontSize: 12.5, color: scheme.textMuted)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<int>(
                            key: Key('voucher_line_$i'),
                            value: _pick[i],
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Voucher line',
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: scheme.fg,
                              isDense: true,
                            ),
                            items: [
                              for (final l in widget.lines)
                                DropdownMenuItem(
                                  value: l.idx,
                                  child: Text(
                                    '#${l.idx} · ${l.itemName} (${_q(l.quantity.toDouble())})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(() {
                              if (v != null) _pick[i] = v;
                              _error = null;
                            }),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12 + bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null || over.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _error ??
                            'Over-filled: ${over.entries.map((e) => '#${e.key} by ${_q(e.value)}').join(', ')}',
                        style: TextStyle(
                            color: errInk, fontWeight: FontWeight.w600),
                      ),
                    ),
                  AsyncFilledButton(
                    busy: widget.busy,
                    onPressed: _confirm,
                    icon: const Icon(Icons.link),
                    label: _complete
                        ? 'Link & save'
                        : 'Assign ${widget.rows.length - _pick.length} more',
                    loadingLabel: 'Saving…',
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FillChip extends StatelessWidget {
  final String label;
  final Color ink;
  const _FillChip({required this.label, required this.ink});

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.subtle,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.border),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: ink)),
    );
  }
}
