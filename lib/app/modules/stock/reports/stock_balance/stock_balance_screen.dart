import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/global_widgets/selectable_filter_chip.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_controller.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_sheets.dart';

class StockBalanceScreen extends GetView<StockBalanceController> {
  const StockBalanceScreen({super.key});

  // ── Standard fields that never render as attribute chips ───────────────────
  //
  // Every column the tile renders explicitly is listed here so it can't also
  // leak into the residual-chip Wrap. ERPNext's Stock Balance report emits the
  // balance/valuation columns as `bal_qty` / `bal_val` / `val_rate`; the older
  // `balance_qty` / `valuation_rate` spellings are kept too so neither
  // convention slips through (this is what previously left the hero badge — which
  // read a non-existent `balance_qty` — disagreeing with a leaked "Balance Qty"
  // chip). The rack / inventory-dimension column is deliberately NOT skipped: the
  // tile detects it by name and consumes it in the location line, then drops it
  // from the chip row itself.
  static const _skipFields = {
    // identity + grouping (head + location line)
    'item_code', 'item_name', 'item_group', 'brand', 'description',
    'warehouse', 'stock_uom',
    // movement ledger
    'opening_qty', 'opening_val',
    'in_qty', 'in_val',
    'out_qty', 'out_val',
    // balance + valuation (ERPNext names + legacy/alt spellings)
    'bal_qty', 'bal_val', 'val_rate',
    'balance_qty', 'balance_val', 'balance_value', 'valuation_rate',
    // commitment + customer (availability bar / footer)
    'reserved_stock', 'reserved_qty',
    'customer_code',
    // dropped from the tile entirely
    'company',
  };

  // ── Filter chip builder ───────────────────────────────────────────────────
  //
  // Returns List<Widget> — one InputChip per active filter.
  // DocTypeListHeader wraps them in a horizontal SingleChildScrollView
  // internally, so this builder only needs to produce the chip widgets.

  List<Widget> _buildFilterChips(BuildContext context) {
    // Routes through the shared FilterChipWidget so chip styling stays uniform
    // across every list and report screen.
    final chips = <Widget>[];
    // Relies on being called synchronously inside the parent Obx() rebuild.
    controller.activeFilters.forEach((key, label) {
      chips.add(FilterChipWidget(
        icon: Icons.filter_alt_outlined,
        label: label,
        onDeleted: () => controller.clearFilter(key),
      ));
    });
    return chips;
  }

  // ── Filter sheet helper ───────────────────────────────────────────────────

  void _openFilters(BuildContext context) => showReportFilterSheet(
        context: context,
        title: 'Stock Balance Filters',
        fields: controller.filterFields,
        controllers: controller.filterControllers,
        chipGroups: controller.chipGroups,
        onRun: controller.runReport,
        onClear: controller.clearFilters,
      );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppShellScaffold(
      // Sticky totals bar — reflects the rows currently shown (after quick
      // filters), only while a non-empty report is on screen.
      bottomNavigationBar: Obx(() {
        if (controller.isLoading.value || controller.reportData.isEmpty) {
          return const SizedBox.shrink();
        }
        final visible = controller.visibleRows;
        if (visible.isEmpty) return const SizedBox.shrink();
        return _TotalBar(totals: computeStockBalanceTotals(visible));
      }),
      body: Obx(() {
        final loading = controller.isLoading.value;
        final hasData = !loading && controller.reportData.isNotEmpty;
        // Standard columns are rendered explicitly by the tile; only the
        // remainder (variant attributes, unmapped dimensions) become chips.
        final attrCols = controller.reportColumns
            .where(
                (c) => !_skipFields.contains(c['fieldname'] as String? ?? ''))
            .toList();
        final visible = hasData ? controller.visibleRows : const [];
        final showImages = controller.showImages.value;

        return RefreshIndicator(
          onRefresh: controller.runReport,
          color: cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Unified header ──────────────────────────────────────
              DocTypeListHeader(
                title: 'Stock Balance',
                automaticallyImplyLeading: false,
                activeFilters: controller.activeFilters,
                onFilterTap: () => _openFilters(context),
                filterChipsBuilder: _buildFilterChips,
                onClearAllFilters: controller.clearFilters,
              ),

              // ── Warehouse pills + state filter ──────────────────────
              if (hasData)
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border:
                          Border(bottom: BorderSide(color: cs.outlineVariant)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Single-tap warehouse facet — only worth showing when
                        // the result set spans more than one warehouse.
                        if (controller.distinctWarehouses.length > 1) ...[
                          _WarehouseChips(
                            warehouses: controller.distinctWarehouses,
                            selected: controller.quickWarehouse.value,
                            onSelected: controller.setQuickWarehouse,
                          ),
                          const SizedBox(height: 10),
                        ],
                        _SegmentedStateFilter(
                          state: controller.quickState.value,
                          onState: controller.setQuickState,
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Results ────────────────────────────────────────────
              if (loading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (controller.reportData.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: 'Set filters and run the report',
                    actionLabel: 'Set Filters',
                    actionIcon: Icons.filter_alt_outlined,
                    onAction: () => _openFilters(context),
                  ),
                )
              else if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    icon: Icons.search_off_outlined,
                    message: 'No items match these filters',
                    actionLabel: 'Clear quick filters',
                    actionIcon: Icons.filter_alt_off_outlined,
                    onAction: controller.clearQuickFilters,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final row = visible[index];
                        final itemCode = (row['item_code'] ?? '').toString();
                        final itemName = (row['item_name'] ?? '').toString();
                        final warehouse = (row['warehouse'] ?? '').toString();
                        final reserved = _readNum(
                            row, const ['reserved_stock', 'reserved_qty']);
                        final customer =
                            (row['customer_code'] ?? '').toString();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _BalanceTile(
                            row: row,
                            attrCols: attrCols,
                            showImage: showImages,
                            onWarehouseTap: () =>
                                controller.setQuickWarehouse(warehouse),
                            onLedgerTap: itemCode.isEmpty
                                ? null
                                : () => showStockLedgerSheet(
                                      context,
                                      itemCode: itemCode,
                                      itemName: itemName,
                                      warehouse: warehouse,
                                      entries: controller.fetchStockLedger(
                                          itemCode, warehouse),
                                    ),
                            onReservedTap: reserved > 0
                                ? () => showReservationsSheet(
                                      context,
                                      itemCode: itemCode,
                                      itemName: itemName,
                                      reserved: reserved,
                                      reservations: controller.fetchReservations(
                                          itemCode, warehouse),
                                    )
                                : null,
                            onCustomerTap: customer.isEmpty
                                ? null
                                : () => showCustomerItemsSheet(
                                      context,
                                      customerCode: customer,
                                      items:
                                          controller.itemsForCustomer(customer),
                                      onFilter: () => controller
                                          .applyCustomerFilter(customer),
                                    ),
                          ),
                        );
                      },
                      childCount: visible.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

// ── Empty / no-match state ──────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String   message;
  final String   actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: Icon(actionIcon),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Aggregate totals ───────────────────────────────────────────────────────────
//
// The summary strip and the sticky total bar both summarise the whole result
// set. Computed once per report from the already-loaded rows (no controller or
// API change). Quantities are summed for the ledger total even though rows can
// mix UOMs; the stock *value* total is the unambiguous figure and is given the
// hero treatment in the bar.

class StockBalanceTotals {
  final int itemCount;      // distinct item codes
  final int warehouseCount; // distinct warehouses
  final int negativeCount;  // rows whose balance is below zero
  final double opening;
  final double inQty;
  final double outQty;      // summed as magnitude (rendered with a − prefix)
  final double balance;
  final double value;       // total stock value

  const StockBalanceTotals({
    required this.itemCount,
    required this.warehouseCount,
    required this.negativeCount,
    required this.opening,
    required this.inQty,
    required this.outQty,
    required this.balance,
    required this.value,
  });
}

double _readNum(Map<String, dynamic> row, List<String> keys) {
  for (final k in keys) {
    final v = row[k];
    if (v == null) continue;
    if (v is num) return v.toDouble();
    final parsed = double.tryParse(v.toString().trim());
    if (parsed != null) return parsed;
  }
  return 0.0;
}

StockBalanceTotals computeStockBalanceTotals(List<Map<String, dynamic>> rows) {
  final items = <String>{};
  final warehouses = <String>{};
  var negatives = 0;
  var opening = 0.0, inQty = 0.0, outQty = 0.0, balance = 0.0, value = 0.0;

  for (final r in rows) {
    final code = (r['item_code'] ?? '').toString().trim();
    if (code.isNotEmpty) items.add(code);
    final wh = (r['warehouse'] ?? '').toString().trim();
    if (wh.isNotEmpty) warehouses.add(wh);

    final bal = _readNum(r, ['bal_qty', 'balance_qty']);
    if (bal < 0) negatives++;

    opening += _readNum(r, ['opening_qty']);
    inQty   += _readNum(r, ['in_qty']);
    outQty  += _readNum(r, ['out_qty']).abs();
    balance += bal;
    value   += _readNum(r, ['bal_val', 'balance_value', 'balance_val']);
  }

  return StockBalanceTotals(
    itemCount: items.length,
    warehouseCount: warehouses.length,
    negativeCount: negatives,
    opening: opening,
    inQty: inQty,
    outQty: outQty,
    balance: balance,
    value: value,
  );
}

String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

// All / In stock / Negative / Empty — segmented client-side state filter.
class _SegmentedStateFilter extends StatelessWidget {
  final String state;
  final ValueChanged<String> onState;
  const _SegmentedStateFilter({required this.state, required this.onState});

  static const _segments = [
    ('ALL', 'All'),
    ('instock', 'In stock'),
    ('neg', 'Negative'),
    ('empty', 'Empty'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          for (final (value, label) in _segments)
            Expanded(
              child: InkWell(
                onTap: () => onState(value),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: state == value ? cs.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: state == value
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: state == value ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Warehouse pills ──────────────────────────────────────────────────────────────
//
// A single-tap warehouse facet over the loaded rows. 'All' plus one chip per
// distinct warehouse, in a horizontal scroller so long warehouse names never
// wrap or crowd the row. Tapping a chip sets the warehouse quick filter; tapping
// the already-selected chip is a harmless re-select.
class _WarehouseChips extends StatelessWidget {
  final List<String> warehouses;
  final String selected;
  final ValueChanged<String> onSelected;

  const _WarehouseChips({
    required this.warehouses,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final items = <String>['ALL', ...warehouses];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final w = items[i];
          final isAll = w == 'ALL';
          return Align(
            alignment: Alignment.center,
            child: SelectableFilterChip(
              label: isAll ? 'All' : w,
              selected: isAll ? selected == 'ALL' : selected == w,
              onSelected: (_) => onSelected(w),
            ),
          );
        },
      ),
    );
  }
}

// ── Sticky total bar ─────────────────────────────────────────────────────────────

class _TotalBar extends StatelessWidget {
  final StockBalanceTotals totals;
  const _TotalBar({required this.totals});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted  = cs.onSurfaceVariant;
    final subtle = cs.onSurfaceVariant.withValues(alpha: 0.7);

    // The total balance carries the same red/green/neutral signal as a row.
    final isDark = cs.brightness == Brightness.dark;
    final balColor = totals.balance < 0
        ? (isDark ? AppColors.red300 : AppColors.red700)
        : totals.balance > 0
            ? (isDark ? AppColors.green300 : AppColors.green700)
            : cs.onSurface;
    final ledgerAccent =
        totals.balance < 0 ? cs.error : AppColors.green500;

    return Material(
      color: cs.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 12, color: muted),
                        children: [
                          TextSpan(
                            text: 'TOTAL  ',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: cs.onSurface,
                            ),
                          ),
                          TextSpan(text: _plural(totals.itemCount, 'item')),
                          TextSpan(
                              text: '  ·  ', style: TextStyle(color: cs.outline)),
                          TextSpan(
                              text:
                                  _plural(totals.warehouseCount, 'warehouse')),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'TOTAL VALUE',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                          color: subtle,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        FormattingHelper.formatAmount(totals.value),
                        style: TextStyle(
                          fontSize: 18,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 9),
              _Ledger(
                opening: FormattingHelper.formatQtyGrouped(totals.opening),
                inText: totals.inQty == 0
                    ? FormattingHelper.formatQtyGrouped(0)
                    : '+${FormattingHelper.formatQtyGrouped(totals.inQty)}',
                outText: totals.outQty == 0
                    ? FormattingHelper.formatQtyGrouped(0)
                    : '−${FormattingHelper.formatQtyGrouped(totals.outQty)}',
                balance: FormattingHelper.formatQtyGrouped(totals.balance),
                inZero: totals.inQty == 0,
                outZero: totals.outQty == 0,
                accent: ledgerAccent,
                balanceFg: balColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Stock-balance state ────────────────────────────────────────────────────────
//
// One health state per row, derived from the on-hand balance and how much of it
// is already reserved. Exposed (with [stockBalanceStateFor]) as top-level API so
// the classification can be unit-tested without pumping a widget.

enum StockBalanceState { ok, watch, negative, empty }

/// Classifies a row by its [balance] and [reserved] quantity.
///
/// - negative → balance below zero (issued beyond on-hand)
/// - empty    → exactly zero (out of stock / no movement)
/// - watch    → ≥ 80% of the balance is reserved (little free stock left)
/// - ok       → healthy with free stock available
StockBalanceState stockBalanceStateFor(double balance, double reserved) {
  if (balance < 0) return StockBalanceState.negative;
  if (balance == 0) return StockBalanceState.empty;
  if (reserved >= balance * 0.8) return StockBalanceState.watch;
  return StockBalanceState.ok;
}

/// Splits [balance] into available vs. reserved, clamped to `[0, balance]` so a
/// stray over-reservation can't paint a negative-width availability bar.
({double available, double reserved}) availabilitySplit(
  double balance,
  double reserved,
) {
  final r = reserved.clamp(0.0, balance < 0 ? 0.0 : balance);
  return (available: balance - r, reserved: r);
}

/// Builds a single Stock Balance result tile in isolation. Exposed only so the
/// widget test can render each health state without standing up the full screen
/// (and its GetX controller / API provider); production code uses [_BalanceTile]
/// directly inside the list.
@visibleForTesting
Widget buildStockBalanceTileForTest({
  required Map<String, dynamic> row,
  required List<Map<String, dynamic>> attrCols,
  bool showImage = false,
  VoidCallback? onWarehouseTap,
  VoidCallback? onLedgerTap,
  VoidCallback? onReservedTap,
  VoidCallback? onCustomerTap,
}) =>
    _BalanceTile(
      row: row,
      attrCols: attrCols,
      showImage: showImage,
      onWarehouseTap: onWarehouseTap,
      onLedgerTap: onLedgerTap,
      onReservedTap: onReservedTap,
      onCustomerTap: onCustomerTap,
    );

/// Renders the sticky total bar in isolation for widget tests.
@visibleForTesting
Widget buildStockBalanceTotalBarForTest(StockBalanceTotals totals) =>
    _TotalBar(totals: totals);

/// Renders the segmented state filter in isolation for widget tests.
@visibleForTesting
Widget buildStockBalanceStateFilterForTest({
  String state = 'ALL',
  ValueChanged<String>? onState,
}) =>
    _SegmentedStateFilter(state: state, onState: onState ?? (_) {});

/// Renders the single-tap warehouse pills in isolation for widget tests.
@visibleForTesting
Widget buildStockBalanceWarehouseChipsForTest({
  List<String> warehouses = const [],
  String selected = 'ALL',
  ValueChanged<String>? onSelected,
}) =>
    _WarehouseChips(
      warehouses: warehouses,
      selected: selected,
      onSelected: onSelected ?? (_) {},
    );

// ── Result tile ──────────────────────────────────────────────────────────────

class _BalanceTile extends StatelessWidget {
  final Map<String, dynamic>       row;
  final List<Map<String, dynamic>> attrCols;
  final bool showImage;
  final VoidCallback? onWarehouseTap;

  final VoidCallback? onLedgerTap;
  final VoidCallback? onReservedTap;
  final VoidCallback? onCustomerTap;

  const _BalanceTile({
    required this.row,
    required this.attrCols,
    this.showImage = false,
    this.onWarehouseTap,
    this.onLedgerTap,
    this.onReservedTap,
    this.onCustomerTap,
  });

  static const _mono = 'monospace';

  // Reads the first present (non-blank) value among [keys].
  dynamic _pick(List<String> keys) {
    for (final k in keys) {
      final v = row[k];
      if (v != null && v.toString().trim().isNotEmpty) return v;
    }
    return null;
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString().trim() ?? '') ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final itemCode = row['item_code']?.toString() ?? '—';
    final itemName = row['item_name']?.toString() ?? '';
    final uom      = _pick(['stock_uom'])?.toString() ?? '';
    final warehouse = row['warehouse']?.toString().trim() ?? '';

    final balance  = _toDouble(_pick(['bal_qty', 'balance_qty']));
    final opening  = _toDouble(_pick(['opening_qty']));
    final inQty    = _toDouble(_pick(['in_qty']));
    final outQty   = _toDouble(_pick(['out_qty']));
    final reserved = _toDouble(_pick(['reserved_stock', 'reserved_qty']));
    final rate     = _toDouble(_pick(['val_rate', 'valuation_rate']));
    final value    = _toDouble(_pick(['bal_val', 'balance_value', 'balance_val']));
    final customer = _pick(['customer_code'])?.toString();

    // The rack / inventory-dimension column has an instance-defined fieldname;
    // find it by name so dimension-wise mode surfaces the rack on the location
    // line, and exclude it from the residual chips below.
    Map<String, dynamic>? rackCol;
    for (final c in attrCols) {
      final fn = (c['fieldname']?.toString() ?? '').toLowerCase();
      final lb = (c['label']?.toString() ?? '').toLowerCase();
      if (fn.contains('rack') || lb.contains('rack')) {
        rackCol = c;
        break;
      }
    }
    final rackName = rackCol == null
        ? null
        : _pick([rackCol['fieldname']?.toString() ?? ''])?.toString();

    final extraCols = attrCols.where((c) => c != rackCol).toList();

    final state  = stockBalanceStateFor(balance, reserved);
    final style  = _stateStyle(state, cs);
    final accent = style.accent;
    final fg     = style.fg;
    final tintBg = Color.alphaBlend(accent.withValues(alpha: 0.13), cs.surface);
    final tintBd = accent.withValues(alpha: 0.30);

    final stack = Stack(
      children: [
        // 3px state accent bar down the leading edge.
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 3,
          child: ColoredBox(color: accent),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(17, 13, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                // 1 ── Head: thumbnail + identity + hero balance ───────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showImage) ...[
                      _ItemThumb(
                        imageUrl: _pick(['item_image'])?.toString(),
                        itemCode: itemCode,
                        itemName: itemName,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            itemCode,
                            style: TextStyle(
                              fontFamily: _mono,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          if (itemName.isNotEmpty && itemName != itemCode) ...[
                            const SizedBox(height: 1),
                            Text(
                              itemName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _BalanceBox(
                      qty: FormattingHelper.formatQty(balance),
                      uom: uom,
                      fg: fg,
                      bg: tintBg,
                      border: tintBd,
                    ),
                  ],
                ),

                // 2 ── Location line ───────────────────────────────────
                const SizedBox(height: 9),
                _LocationLine(
                  warehouse: warehouse,
                  rack: rackName,
                  onWarehouseTap: onWarehouseTap,
                ),

                // 3 ── Ledger strip ────────────────────────────────────
                const SizedBox(height: 11),
                _Ledger(
                  opening: FormattingHelper.formatQty(opening),
                  inText: inQty == 0
                      ? FormattingHelper.formatQty(0)
                      : '+${FormattingHelper.formatQty(inQty.abs())}',
                  outText: outQty == 0
                      ? FormattingHelper.formatQty(0)
                      : '−${FormattingHelper.formatQty(outQty.abs())}',
                  balance: FormattingHelper.formatQty(balance),
                  inZero: inQty == 0,
                  outZero: outQty == 0,
                  accent: accent,
                  balanceFg: fg,
                ),

                // 4 ── Commitment: availability bar OR status note ─────
                const SizedBox(height: 11),
                if (balance > 0)
                  _AvailabilityBar(
                    available: availabilitySplit(balance, reserved).available,
                    reserved: availabilitySplit(balance, reserved).reserved,
                    onReservedTap: onReservedTap,
                  )
                else if (balance < 0)
                  _StatusNote(
                    icon: Icons.warning_amber_rounded,
                    text: 'Negative stock — issued beyond on-hand qty',
                    fg: fg,
                    bg: Color.alphaBlend(
                        accent.withValues(alpha: 0.11), cs.surface),
                    border: accent.withValues(alpha: 0.24),
                  )
                else
                  _StatusNote(
                    icon: Icons.inventory_2_outlined,
                    text: 'Out of stock — no movement in period',
                    fg: cs.onSurfaceVariant,
                    bg: cs.surfaceContainerHighest,
                    border: cs.outlineVariant,
                  ),

                // 5 ── Residual chips (variant attrs / unmapped columns) ─
                ..._buildResidualChips(extraCols),

                // 6 ── Meta footer: rate / value / customer ────────────
                const SizedBox(height: 11),
                _DashedDivider(color: cs.outlineVariant),
                const SizedBox(height: 10),
                _MetaFooter(
                  rate: rate,
                  value: value,
                  customerCode: customer,
                  onCustomerTap: onCustomerTap,
                ),
              ],
            ),
          ),
        ],
      );

    return Material(
      color: cs.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      // Card-level tap opens the Stock Ledger; the inner warehouse / reserved /
      // customer InkWells take precedence within their own hit areas.
      child: onLedgerTap == null
          ? stack
          : InkWell(onTap: onLedgerTap, child: stack),
    );
  }

  List<Widget> _buildResidualChips(List<Map<String, dynamic>> cols) {
    final chips = <Widget>[];
    for (final col in cols) {
      final fieldname = col['fieldname']?.toString() ?? '';
      final label     = col['label']?.toString() ?? fieldname;
      final val       = row[fieldname];
      if (val == null || val.toString().trim().isEmpty) continue;
      chips.add(_AttrChip(label: label, value: val.toString()));
    }
    if (chips.isEmpty) return const [];
    return [
      const SizedBox(height: 11),
      Wrap(spacing: 6, runSpacing: 6, children: chips),
    ];
  }
}

// ── State palette ──────────────────────────────────────────────────────────────

class _StateStyle {
  final Color accent; // left bar, swatches, balance-cell tint
  final Color fg;     // text on tint (the darker shade)
  const _StateStyle(this.accent, this.fg);
}

_StateStyle _stateStyle(StockBalanceState state, ColorScheme cs) {
  // fg follows the status ramp — x700 on light surfaces, x300 on dark —
  // so the hero/ledger/status text stays ≥4.5:1 in both themes.
  final isDark = cs.brightness == Brightness.dark;
  switch (state) {
    case StockBalanceState.ok:
      return _StateStyle(AppColors.green500,
          isDark ? AppColors.green300 : AppColors.green700);
    case StockBalanceState.watch:
      return _StateStyle(AppColors.orange500,
          isDark ? AppColors.orange300 : AppColors.orange700);
    case StockBalanceState.negative:
      return _StateStyle(
          cs.error, isDark ? AppColors.red300 : AppColors.red700);
    case StockBalanceState.empty:
      return _StateStyle(cs.outline, cs.onSurfaceVariant);
  }
}

// ── Hero balance box ───────────────────────────────────────────────────────────

class _BalanceBox extends StatelessWidget {
  final String qty;
  final String uom;
  final Color fg;
  final Color bg;
  final Color border;

  const _BalanceBox({
    required this.qty,
    required this.uom,
    required this.fg,
    required this.bg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 62),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            qty,
            style: TextStyle(
              fontSize: 24,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: fg,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (uom.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              uom.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: Color.lerp(cs.onSurfaceVariant, fg, 0.45),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Location line ──────────────────────────────────────────────────────────────

class _LocationLine extends StatelessWidget {
  final String warehouse;
  final String? rack;
  final VoidCallback? onWarehouseTap;

  const _LocationLine({
    required this.warehouse,
    this.rack,
    this.onWarehouseTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted   = cs.onSurfaceVariant;
    final subtle  = cs.onSurfaceVariant.withValues(alpha: 0.7);
    final base    = TextStyle(fontSize: 12.5, color: muted, height: 1.2);
    final strong  = base.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600);
    final hasRack = rack != null && rack!.trim().isNotEmpty;

    // Warehouse — tappable when a handler is given (sets the warehouse quick
    // filter). Allowed to ellipsize; the rack below never does.
    Widget warehouseText = Text(
      warehouse.isEmpty ? '—' : warehouse,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: strong,
    );
    if (onWarehouseTap != null) {
      warehouseText = InkWell(
        onTap: onWarehouseTap,
        borderRadius: BorderRadius.circular(4),
        child: warehouseText,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Warehouse line.
        Row(
          children: [
            Icon(Icons.place, size: 14, color: subtle),
            const SizedBox(width: 7),
            Flexible(child: warehouseText),
          ],
        ),
        const SizedBox(height: 3),
        // Rack line — the critical pick location. Full width and never
        // truncated: a long rack (e.g. "KA-WH-DXB3-BLOCK 1") wraps instead of
        // ellipsising so the operator can always read where the stock is.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shelves, size: 14, color: subtle),
            const SizedBox(width: 7),
            Expanded(
              child: hasRack
                  ? Text.rich(
                      TextSpan(
                        style: base,
                        children: [
                          const TextSpan(text: 'Rack '),
                          TextSpan(text: rack!.trim(), style: strong),
                        ],
                      ),
                      softWrap: true,
                    )
                  : Text(
                      'No rack assigned',
                      style: base.copyWith(
                          color: subtle, fontStyle: FontStyle.italic),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Item thumbnail ─────────────────────────────────────────────────────────────

class _ItemThumb extends StatelessWidget {
  final String? imageUrl;
  final String itemCode;
  final String itemName;

  const _ItemThumb({
    required this.imageUrl,
    required this.itemCode,
    required this.itemName,
  });

  static const double _size = 46;

  String get _initials {
    final source = itemName.trim().isNotEmpty ? itemName : itemCode;
    final words = source
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '·';
    final letters = words.take(2).map((w) => w[0]).join();
    return letters.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget fallback() => Container(
          width: _size,
          height: _size,
          alignment: Alignment.center,
          color: cs.secondaryContainer,
          child: Text(
            _initials,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSecondaryContainer,
            ),
          ),
        );

    final url = imageUrl?.trim() ?? '';
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _size,
        height: _size,
        child: url.isEmpty
            ? fallback()
            : CachedNetworkImage(
                imageUrl: url,
                width: _size,
                height: _size,
                fit: BoxFit.cover,
                placeholder: (_, __) => fallback(),
                errorWidget: (_, __, ___) => fallback(),
              ),
      ),
    );

    // Tap to enlarge (only when there's an actual image to show), without
    // leaving the report.
    if (url.isEmpty) return thumb;
    return GestureDetector(
      onTap: () => showItemImagePreview(context, url, itemCode, itemName),
      child: thumb,
    );
  }
}

/// Shows the item image enlarged in an in-screen, dismissible dialog with
/// pinch/drag zoom. Stays on the report — no navigation.
void showItemImagePreview(
  BuildContext context,
  String url,
  String itemCode,
  String itemName,
) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    useSafeArea: false, // let the preview fill the whole screen
    builder: (ctx) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      clipBehavior: Clip.hardEdge,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SizedBox.expand(
        child: Stack(
          children: [
            // Full-bleed, zoomable image filling the screen.
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    ),
                    errorWidget: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
            // Caption (item code + name).
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    itemName.isNotEmpty ? '$itemCode · $itemName' : itemCode,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Ledger strip ───────────────────────────────────────────────────────────────

class _Ledger extends StatelessWidget {
  final String opening;
  final String inText;
  final String outText;
  final String balance;
  final bool   inZero;
  final bool   outZero;
  final Color  accent;
  final Color  balanceFg;

  const _Ledger({
    required this.opening,
    required this.inText,
    required this.outText,
    required this.balance,
    required this.inZero,
    required this.outZero,
    required this.accent,
    required this.balanceFg,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtle = cs.onSurfaceVariant.withValues(alpha: 0.8);

    Widget cell(String k, String v, Color vColor, {Color? bg}) {
      return Container(
        color: bg,
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              k.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: subtle,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              v,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1,
                fontWeight: FontWeight.w700,
                color: vColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    Widget divider() => Container(
          width: 1,
          margin: const EdgeInsets.symmetric(vertical: 7),
          color: cs.outlineVariant,
        );

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cell('Opening', opening, cs.onSurface)),
              divider(),
              Expanded(
                child: cell(
                    'In',
                    inText,
                    inZero
                        ? subtle
                        : (cs.brightness == Brightness.dark
                            ? AppColors.green300
                            : AppColors.green700)),
              ),
              divider(),
              Expanded(
                child: cell(
                    'Out',
                    outText,
                    outZero
                        ? subtle
                        : (cs.brightness == Brightness.dark
                            ? AppColors.red300
                            : AppColors.red700)),
              ),
              divider(),
              Expanded(
                child: cell(
                  'Balance',
                  balance,
                  balanceFg,
                  bg: Color.alphaBlend(
                      accent.withValues(alpha: 0.09), cs.surfaceContainerHighest),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Availability bar ───────────────────────────────────────────────────────────

class _AvailabilityBar extends StatelessWidget {
  final double available;
  final double reserved;
  final VoidCallback? onReservedTap;

  const _AvailabilityBar({
    required this.available,
    required this.reserved,
    this.onReservedTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final green  = Colors.green.shade500;
    final orange = Colors.orange.shade600;

    // Integer flex weights, never zero for a non-zero segment (so a tiny sliver
    // is still visible). A whole-number-of-thousandths keeps the math tidy.
    final total = available + reserved;
    final freeFlex = available <= 0
        ? 0
        : math.max(1, (available / total * 1000).round());
    final resvFlex = reserved <= 0
        ? 0
        : math.max(1, (reserved / total * 1000).round());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 7,
            child: Row(
              children: [
                if (freeFlex > 0)
                  Expanded(flex: freeFlex, child: ColoredBox(color: green)),
                if (resvFlex > 0)
                  Expanded(flex: resvFlex, child: ColoredBox(color: orange)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _swatch(green, 'Available', available, cs),
            // Reserved drills into the Sales Orders behind the figure.
            _swatch(orange, 'Reserved', reserved, cs, onTap: onReservedTap),
          ],
        ),
      ],
    );
  }

  Widget _swatch(Color c, String label, double qty, ColorScheme cs,
      {VoidCallback? onTap}) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text.rich(
          TextSpan(
            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            children: [
              TextSpan(text: '$label '),
              TextSpan(
                text: FormattingHelper.formatQty(qty),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        if (onTap != null)
          Icon(Icons.chevron_right, size: 15, color: cs.onSurfaceVariant),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: content,
      ),
    );
  }
}

// ── Status note (negative / out-of-stock) ──────────────────────────────────────

class _StatusNote extends StatelessWidget {
  final IconData icon;
  final String   text;
  final Color    fg;
  final Color    bg;
  final Color    border;

  const _StatusNote({
    required this.icon,
    required this.text,
    required this.fg,
    required this.bg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Meta footer ────────────────────────────────────────────────────────────────

class _MetaFooter extends StatelessWidget {
  final double  rate;
  final double  value;
  final String? customerCode;
  final VoidCallback? onCustomerTap;

  const _MetaFooter({
    required this.rate,
    required this.value,
    this.customerCode,
    this.onCustomerTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtle = cs.onSurfaceVariant.withValues(alpha: 0.7);
    final hasCust = customerCode != null && customerCode!.trim().isNotEmpty;

    Widget custTag = Container(
      padding: EdgeInsets.fromLTRB(8, 3, onCustomerTap != null ? 4 : 8, 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person, size: 12, color: subtle),
          const SizedBox(width: 5),
          Text(
            customerCode?.trim() ?? '',
            style: TextStyle(
              fontFamily: _BalanceTile._mono,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (onCustomerTap != null)
            Icon(Icons.chevron_right, size: 14, color: subtle),
        ],
      ),
    );
    if (onCustomerTap != null) {
      custTag = InkWell(
        onTap: onCustomerTap,
        borderRadius: BorderRadius.circular(6),
        child: custTag,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _metaItem('Rate', rate, subtle, cs),
              _metaItem('Value', value, subtle, cs),
            ],
          ),
        ),
        if (hasCust) ...[
          const SizedBox(width: 8),
          custTag,
        ],
      ],
    );
  }

  Widget _metaItem(String label, double amount, Color subtle, ColorScheme cs) {
    final isZero = amount == 0;
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 11.5, color: subtle),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: FormattingHelper.formatAmount(amount),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isZero ? subtle : cs.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dashed divider ─────────────────────────────────────────────────────────────

class _DashedDivider extends StatelessWidget {
  final Color color;
  const _DashedDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashPainter(color)),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 4.0, gap = 3.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0.5), Offset(x + dash, 0.5), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

// ── Attribute chip (residual / variant-attribute columns) ───────────────────────

class _AttrChip extends StatelessWidget {
  final String label;
  final String value;
  const _AttrChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text.rich(
        TextSpan(
          style: text.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
          children: [
            TextSpan(text: '$label '),
            TextSpan(
              text: value,
              style: TextStyle(color: cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
