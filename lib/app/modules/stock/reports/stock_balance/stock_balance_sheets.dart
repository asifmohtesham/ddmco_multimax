import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/data/utils/report_error.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_anchor.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_controller.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_sheet.dart';

import 'stock_ledger_fields.dart';

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

Future<void> _present(BuildContext context, Widget child, {bool useSafeArea = false}) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: useSafeArea,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => child,
  );
}

class _SheetShell extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final IconData routeIcon;
  final String routeLabel;
  final Widget child;     // the list / body
  final Widget? cta;

  const _SheetShell({
    this.eyebrow,
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
                        if (eyebrow case final caption?) ...[
                          Text(
                            caption.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(height: 3),
                        ],
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

class StockLedgerSheetBody extends StatefulWidget {
  const StockLedgerSheetBody({
    super.key,
    required this.itemCode,
    required this.itemName,
    required this.warehouse,
    this.entries = const [],
    this.load,
    this.ownerIsCurrent,
  });

  final String itemCode;
  final String itemName;
  final String warehouse;
  final List<Map<String, dynamic>> entries;
  final Future<StockLedgerReportResult> Function()? load;
  final bool Function()? ownerIsCurrent;

  @override
  State<StockLedgerSheetBody> createState() => _StockLedgerSheetBodyState();
}

class _StockLedgerSheetBodyState extends State<StockLedgerSheetBody> {
  late final _fields = ScopedReportFieldsController.forReport(
    stockLedgerFields(),
  );
  late final Worker _ownerWorker;
  late List<Map<String, dynamic>> _entries;
  List<DeskColumn>? _columns;
  int _ownerGeneration = 0;
  bool _loading = false;
  bool _ownerInvalidated = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ownerInvalidated = widget.ownerIsCurrent?.call() == false;
    _entries = _ownerInvalidated ? const [] : widget.entries;
    _ownerGeneration = _fields.ownerGeneration;
    _ownerWorker = ever(_fields.state, (_) {
      final owner = _fields.ownerGeneration;
      if (_ownerGeneration == owner) return;
      _ownerGeneration = owner;
      setState(() {
        _loading = false;
        _entries = const [];
        _columns = null;
        _ownerInvalidated = true;
        _error = null;
      });
    });
    unawaited(_fields.bind());
    if (widget.load != null) unawaited(_load());
  }

  Future<void> _load() async {
    final load = widget.load;
    if (load == null || _loading || _ownerInvalidated) return;
    final owner = _fields.ownerGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await load();
      if (!mounted || owner != _fields.ownerGeneration) return;
      _fields.replaceDefinition(stockLedgerFields(result.columns));
      setState(() {
        _columns = result.columns;
        _entries = result.rows;
      });
    } catch (error) {
      if (!mounted || owner != _fields.ownerGeneration) return;
      setState(
        () => _error = readableReportError(error, reportName: 'Stock Ledger'),
      );
    } finally {
      if (mounted && owner == _fields.ownerGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _ownerWorker.dispose();
    _fields.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      minChildSize: .45,
      maxChildSize: .95,
      builder: (context, scroll) => Obx(() {
        final fields = _fields.state.value;
        final ids = stockLedgerOccurrenceIds(_entries);
        return ReportFieldsResults(
          controller: _fields,
          scrollController: scroll,
          result: _entries,
          occurrenceIds: ids,
          builder: (context, anchors) => CustomScrollView(
            controller: scroll,
            slivers: [
              anchors.header(
                DocTypeListHeader(
                  title: 'Stock Ledger',
                  extraActions: [
                    if (!_ownerInvalidated)
                      ReportFieldsAction(controller: _fields),
                  ],
                ),
              ),
              if (!_ownerInvalidated)
                SliverToBoxAdapter(child: _ledgerContext(context)),
              if (_ownerInvalidated)
                const SliverToBoxAdapter(
                  child: _SheetEmpty(
                    icon: Icons.info_outline,
                    message: 'Open the ledger from a new Stock Balance result.',
                  ),
                )
              else if (_loading)
                const SliverToBoxAdapter(child: _SheetLoading())
              else if (_error case final error?)
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      _SheetEmpty(icon: Icons.error_outline, message: error),
                      if (widget.load != null)
                        FilledButton.tonalIcon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                    ],
                  ),
                )
              else if (_entries.isEmpty)
                const SliverToBoxAdapter(
                  child: _SheetEmpty(
                    icon: Icons.receipt_long_outlined,
                    message: 'No ledger movements in the selected period',
                  ),
                )
              else ...[
                SliverToBoxAdapter(child: _ledgerHeader(context, fields)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList.builder(
                    itemCount: _entries.length,
                    itemBuilder: (context, index) => anchors.row(
                      ids[index],
                      index,
                      _ledgerRow(context, _entries[index], fields),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: ListEndFooter(
                    hasMore: false,
                    bottomPadding: inset,
                    label: stockLedgerFooterLabel(_entries, _columns),
                  ),
                ),
              ],
              if (_loading || _error != null || _entries.isEmpty)
                SliverToBoxAdapter(child: SizedBox(height: 12 + inset)),
            ],
          ),
        );
      }),
    );
  }

  Widget _ledgerContext(BuildContext context) {
    final scheme = context.scheme;
    final text = Theme.of(context).textTheme;
    String caption(String key, String fallback, String value) {
      final columns = _columns ?? const <DeskColumn>[];
      final column = columns.where(
        (column) => (column.fieldname == key ||
            key == 'item_code' && column.fieldname == 'item') &&
            column.label.trim().isNotEmpty,
      ).firstOrNull;
      return '${column?.label ?? fallback} $value';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.itemCode,
            style: text.titleMedium,
            semanticsLabel: caption('item_code', 'Item', widget.itemCode),
          ),
          if (widget.itemName.isNotEmpty)
            Text(
              widget.itemName,
              style: text.bodyMedium,
              semanticsLabel: caption('item_name', 'Item Name', widget.itemName),
            ),
          if (widget.warehouse.isNotEmpty) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                Icon(Icons.place_outlined, size: 16, color: scheme.textMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.warehouse,
                    semanticsLabel: caption('warehouse', 'Warehouse', widget.warehouse),
                    style: text.bodySmall?.copyWith(color: scheme.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _ledgerHeader(BuildContext context, FieldsState fields) =>
      _columnHeader(context, [
        stockLedgerLabel(fields, 'voucher_no'),
        'Qty',
        if (fields.shows('qty_after_transaction'))
          stockLedgerLabel(fields, 'qty_after_transaction'),
      ]);

  Widget _ledgerRow(
    BuildContext context,
    Map<String, dynamic> entry,
    FieldsState fields,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final qty = (entry['qty'] as num?)?.toDouble();
    final balance = (entry['balance'] as num?)?.toDouble();
    final voucher = (entry['voucher_no'] ?? '').toString();
    final type = (entry['voucher_type'] ?? '').toString();
    final date = (entry['date'] ?? '').toString();
    final qtyColor = switch (qty ?? 0.0) {
      > 0 => isDark ? AppColors.green300 : AppColors.green700,
      < 0 => isDark ? AppColors.red300 : AppColors.red700,
      _ => cs.onSurfaceVariant,
    };
    final shownVoucher = voucher.isEmpty ? '—' : voucher;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shownVoucher,
                      semanticsLabel:
                          '${stockLedgerLabel(fields, 'voucher_no')} $shownVoucher',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      [type, date].where((part) => part.isNotEmpty).join(' · '),
                      semanticsLabel: [
                        if (type.isNotEmpty)
                          '${stockLedgerLabel(fields, 'voucher_type')} $type',
                        if (date.isNotEmpty)
                          '${stockLedgerLabel(fields, 'date')} $date',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 84,
                child: Text(
                  qty == null || qty == 0
                      ? '—'
                      : '${qty > 0 ? '+' : '−'}${FormattingHelper.formatQtyGrouped(qty.abs())}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: qtyColor,
                  ),
                ),
              ),
              if (fields.shows('qty_after_transaction'))
                SizedBox(
                  width: 84,
                  child: Text(
                    balance == null
                        ? '—'
                        : FormattingHelper.formatQtyGrouped(balance),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
      ],
    );
  }
}

// ── 2 · Reservations sheet ──────────────────────────────────────────────────────

class ReservationsSheetBody extends StatelessWidget {
  final String itemCode;
  final String itemName;
  final double reserved;
  final String reservedLabel;
  final List<Map<String, dynamic>> reservations;

  const ReservationsSheetBody({
    super.key,
    required this.itemCode,
    required this.itemName,
    required this.reserved,
    this.reservedLabel = 'Reserved Stock',
    required this.reservations,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SheetShell(
      title: '$reservedLabel ${FormattingHelper.formatQtyGrouped(reserved)}',
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
                      final isSalesOrder =
                          (r['voucher_type'] ?? 'Sales Order').toString() ==
                              'Sales Order';
                      final tappable = isSalesOrder && voucher.isNotEmpty;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: tappable
                              ? () {
                                  Get.back(); // close the sheet first
                                  Get.toNamed(AppRoutes.SALES_ORDER_FORM,
                                      arguments: {
                                        'name': voucher,
                                        'mode': 'view',
                                      });
                                }
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                      color: cs.brightness == Brightness.dark
                                          ? AppColors.orange300
                                          : AppColors.orange700),
                                ),
                                if (tappable) ...[
                                  const SizedBox(width: 4),
                                  Icon(Icons.chevron_right,
                                      size: 18, color: cs.onSurfaceVariant),
                                ],
                              ],
                            ),
                          ),
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
  final String itemLabel;
  final String balanceLabel;
  final VoidCallback? onFilter;

  const CustomerItemsSheetBody({
    super.key,
    required this.customerCode,
    required this.items,
    this.itemLabel = 'Item',
    this.balanceLabel = 'Balance Qty',
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
                _columnHeader(context, [itemLabel, balanceLabel]),
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
                                    ? (cs.brightness == Brightness.dark
                                        ? AppColors.red300
                                        : AppColors.red700)
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
  required Future<StockLedgerReportResult> Function() load,
  bool Function()? ownerIsCurrent,
}) {
  return _present(
    context,
    StockLedgerSheetBody(
      itemCode: itemCode,
      itemName: itemName,
      warehouse: warehouse,
      load: load,
      ownerIsCurrent: ownerIsCurrent,
    ),
    useSafeArea: true,
  );
}

Future<void> showReservationsSheet(
  BuildContext context, {
  required String itemCode,
  required String itemName,
  required double reserved,
  String reservedLabel = 'Reserved Stock',
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
          reservedLabel: reservedLabel,
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
  String itemLabel = 'Item',
  String balanceLabel = 'Balance Qty',
  VoidCallback? onFilter,
}) {
  return _present(
    context,
    CustomerItemsSheetBody(
      customerCode: customerCode,
      items: items,
      itemLabel: itemLabel,
      balanceLabel: balanceLabel,
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
