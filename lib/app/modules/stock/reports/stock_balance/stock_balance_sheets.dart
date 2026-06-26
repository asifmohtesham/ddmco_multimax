import 'package:flutter/material.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

// ── Stock Balance drill-down bottom sheets (Phase 2, feature 4) ──────────────────
//
// Three tap-to-navigate destinations, all opened as modal bottom sheets (no
// Stock Ledger route exists in the app):
//   • Stock Ledger   — the item+warehouse ledger over the report period.
//   • Reservations   — the Sales Orders reserving the on-hand stock.
//   • Customer items — the items mapped to a customer code.
//
// Content widgets take already-resolved data so they can be rendered in widget
// tests; the show* opener functions handle the async fetch + sheet presentation.

double _toNum(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

// ── Shared sheet chrome ──────────────────────────────────────────────────────────

Future<void> _present(BuildContext context, Widget child) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => child,
  );
}

class _SheetShell extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;
  final IconData routeIcon;
  final String routeLabel;
  final Widget child;     // the list / body
  final Widget? cta;

  const _SheetShell({
    required this.eyebrow,
    required this.title,
    this.subtitle,
    required this.routeIcon,
    required this.routeLabel,
    required this.child,
    this.cta,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eyebrow.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: cs.onSurfaceVariant,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Route / breadcrumb line.
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(routeIcon, size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      routeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Flexible(child: child),
            if (cta != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    16, 8, 16, 12 + media.padding.bottom),
                child: SizedBox(width: double.infinity, child: cta),
              )
            else
              SizedBox(height: 12 + media.padding.bottom),
          ],
        ),
      ),
    );
  }
}

class _SheetEmpty extends StatelessWidget {
  final IconData icon;
  final String message;
  const _SheetEmpty({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Column(
        children: [
          Icon(icon, size: 44, color: cs.outlineVariant),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

Widget _columnHeader(BuildContext context, List<String> labels) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
    child: Row(
      children: [
        Expanded(
          child: Text(labels.first,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: cs.onSurfaceVariant)),
        ),
        for (final l in labels.skip(1))
          SizedBox(
            width: 84,
            child: Text(l,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: cs.onSurfaceVariant)),
          ),
      ],
    ),
  );
}

// ── 1 · Stock Ledger sheet ────────────────────────────────────────────────────────

class StockLedgerSheetBody extends StatelessWidget {
  final String itemCode;
  final String itemName;
  final String warehouse;
  final List<Map<String, dynamic>> entries;

  const StockLedgerSheetBody({
    super.key,
    required this.itemCode,
    required this.itemName,
    required this.warehouse,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SheetShell(
      eyebrow: 'Stock Ledger',
      title: itemCode,
      subtitle: itemName,
      routeIcon: Icons.receipt_long_outlined,
      routeLabel: 'Stock Ledger › $itemCode'
          '${warehouse.isNotEmpty ? ' · $warehouse' : ''}',
      child: entries.isEmpty
          ? const _SheetEmpty(
              icon: Icons.receipt_long_outlined,
              message: 'No ledger movements in the selected period',
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _columnHeader(context, const ['Voucher', 'Qty', 'Balance']),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: cs.outlineVariant),
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      final qty = _toNum(e['qty']);
                      final voucher = (e['voucher_no'] ?? '').toString();
                      final type = (e['voucher_type'] ?? '').toString();
                      final date = (e['date'] ?? '').toString();
                      final qtyColor = qty > 0
                          ? Colors.green.shade600
                          : qty < 0
                              ? Colors.red.shade600
                              : cs.onSurfaceVariant;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    voucher.isEmpty ? '—' : voucher,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    [type, date]
                                        .where((s) => s.isNotEmpty)
                                        .join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 84,
                              child: Text(
                                qty == 0
                                    ? '—'
                                    : '${qty > 0 ? '+' : '−'}'
                                        '${FormattingHelper.formatQtyGrouped(qty.abs())}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: qtyColor),
                              ),
                            ),
                            SizedBox(
                              width: 84,
                              child: Text(
                                FormattingHelper.formatQtyGrouped(
                                    _toNum(e['balance'])),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// ── 2 · Reservations sheet ──────────────────────────────────────────────────────

class ReservationsSheetBody extends StatelessWidget {
  final String itemCode;
  final String itemName;
  final double reserved;
  final List<Map<String, dynamic>> reservations;

  const ReservationsSheetBody({
    super.key,
    required this.itemCode,
    required this.itemName,
    required this.reserved,
    required this.reservations,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SheetShell(
      eyebrow: 'Reserved stock',
      title: '${FormattingHelper.formatQtyGrouped(reserved)} committed',
      subtitle: '$itemCode · $itemName',
      routeIcon: Icons.bookmark_added_outlined,
      routeLabel: 'Sales Orders reserving $itemCode',
      child: reservations.isEmpty
          ? const _SheetEmpty(
              icon: Icons.bookmark_border_outlined,
              message: 'No reservation details available',
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _columnHeader(context, const ['Sales Order', 'Reserved']),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: reservations.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: cs.outlineVariant),
                    itemBuilder: (_, i) {
                      final r = reservations[i];
                      final voucher = (r['voucher_no'] ?? '').toString();
                      final status = (r['status'] ?? '').toString();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    voucher.isEmpty ? '—' : voucher,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  if (status.isNotEmpty) ...[
                                    const SizedBox(height: 1),
                                    Text(status,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: cs.onSurfaceVariant)),
                                  ],
                                ],
                              ),
                            ),
                            Text(
                              FormattingHelper.formatQtyGrouped(
                                  _toNum(r['reserved'])),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orange.shade800),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// ── 3 · Customer items sheet ────────────────────────────────────────────────────

class CustomerItemsSheetBody extends StatelessWidget {
  final String customerCode;
  final List<Map<String, dynamic>> items;
  final VoidCallback? onFilter;

  const CustomerItemsSheetBody({
    super.key,
    required this.customerCode,
    required this.items,
    this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SheetShell(
      eyebrow: 'Customer Code',
      title: customerCode,
      subtitle: '${items.length} linked '
          '${items.length == 1 ? 'item' : 'items'}',
      routeIcon: Icons.badge_outlined,
      routeLabel: 'Items mapped to $customerCode',
      cta: onFilter == null
          ? null
          : FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(context).pop();
                onFilter!();
              },
              icon: const Icon(Icons.filter_alt_outlined),
              label: const Text('Filter report to this customer'),
            ),
      child: items.isEmpty
          ? const _SheetEmpty(
              icon: Icons.inventory_2_outlined,
              message: 'No items mapped to this customer in the report',
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _columnHeader(context, const ['Item', 'Balance']),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: cs.outlineVariant),
                    itemBuilder: (_, i) {
                      final r = items[i];
                      final code = (r['item_code'] ?? '').toString();
                      final name = (r['item_name'] ?? '').toString();
                      final bal = _toNum(
                          r['bal_qty'] ?? r['balance_qty']);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    code.isEmpty ? '—' : code,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  if (name.isNotEmpty) ...[
                                    const SizedBox(height: 1),
                                    Text(name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: cs.onSurfaceVariant)),
                                  ],
                                ],
                              ),
                            ),
                            Text(
                              FormattingHelper.formatQtyGrouped(bal),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: bal < 0
                                    ? Colors.red.shade600
                                    : cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Openers ──────────────────────────────────────────────────────────────────────

Future<void> showStockLedgerSheet(
  BuildContext context, {
  required String itemCode,
  required String itemName,
  required String warehouse,
  required Future<List<Map<String, dynamic>>> entries,
}) {
  return _present(
    context,
    FutureBuilder<List<Map<String, dynamic>>>(
      future: entries,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _SheetLoading();
        }
        return StockLedgerSheetBody(
          itemCode: itemCode,
          itemName: itemName,
          warehouse: warehouse,
          entries: snap.data ?? const [],
        );
      },
    ),
  );
}

Future<void> showReservationsSheet(
  BuildContext context, {
  required String itemCode,
  required String itemName,
  required double reserved,
  required Future<List<Map<String, dynamic>>> reservations,
}) {
  return _present(
    context,
    FutureBuilder<List<Map<String, dynamic>>>(
      future: reservations,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _SheetLoading();
        }
        return ReservationsSheetBody(
          itemCode: itemCode,
          itemName: itemName,
          reserved: reserved,
          reservations: snap.data ?? const [],
        );
      },
    ),
  );
}

Future<void> showCustomerItemsSheet(
  BuildContext context, {
  required String customerCode,
  required List<Map<String, dynamic>> items,
  VoidCallback? onFilter,
}) {
  return _present(
    context,
    CustomerItemsSheetBody(
      customerCode: customerCode,
      items: items,
      onFilter: onFilter,
    ),
  );
}

class _SheetLoading extends StatelessWidget {
  const _SheetLoading();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
}
