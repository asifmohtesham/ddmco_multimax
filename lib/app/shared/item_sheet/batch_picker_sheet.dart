import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/batch_wise_balance_row.dart';
import 'package:multimax/app/modules/global_widgets/balance_chip.dart';
import 'batch_picker_controller.dart';

/// A draggable bottom sheet that lists all available batches for an item
/// in a given warehouse, sourced from Batch-Wise Balance History.
///
/// ## Usage
/// ```dart
/// final batchNo = await showBatchPickerSheet(
///   context,
///   itemCode:  'ITEM-001',
///   warehouse: 'Stores - MM',
///   accentColor: Colors.purple,
/// );
/// if (batchNo != null) { /* apply selection */ }
/// ```
Future<String?> showBatchPickerSheet(
  BuildContext context, {
  required String itemCode,
  String? warehouse,
  Color accentColor = Colors.teal,
}) async {
  final tag = '${itemCode}_${warehouse ?? 'any'}';

  // Register a fresh controller for this sheet; delete it on close.
  if (!Get.isRegistered<BatchPickerController>(tag: tag)) {
    Get.put(
      BatchPickerController(itemCode: itemCode, warehouse: warehouse),
      tag: tag,
      permanent: false,
    );
  }

  final result = await showModalBottomSheet<String>(
    context:          context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BatchPickerSheet(
      tag:         tag,
      itemCode:    itemCode,
      warehouse:   warehouse,
      accentColor: accentColor,
    ),
  );

  // Always clean up — even if dismissed without selecting.
  if (Get.isRegistered<BatchPickerController>(tag: tag)) {
    Get.delete<BatchPickerController>(tag: tag, force: true);
  }

  return result;
}

/// The actual sheet widget. Prefer calling [showBatchPickerSheet] instead
/// of instantiating this directly.
class BatchPickerSheet extends StatelessWidget {
  final String  tag;
  final String  itemCode;
  final String? warehouse;
  final Color   accentColor;

  const BatchPickerSheet({
    super.key,
    required this.tag,
    required this.itemCode,
    this.warehouse,
    this.accentColor = Colors.teal,
  });

  @override
  Widget build(BuildContext context) {
    final c     = Get.find<BatchPickerController>(tag: tag);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize:     0.4,
      maxChildSize:     0.92,
      expand:           false,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color:        theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color:      Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset:     const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              _Handle(),
              _Header(itemCode: itemCode, warehouse: warehouse, accentColor: accentColor),
              _SearchBar(c: c, accentColor: accentColor),
              const Divider(height: 1),
              Expanded(
                child: Obx(() {
                  if (c.isLoading.value)   return _Skeleton();
                  if (c.errorMessage.value != null) {
                    return _ErrorState(
                      message: c.errorMessage.value!,
                      onRetry: c.retry,
                      accentColor: accentColor,
                    );
                  }
                  final rows = c.filtered;
                  if (rows.isEmpty) {
                    return _EmptyState(
                      hasSearch:  c.searchQuery.value.isNotEmpty,
                      accentColor: accentColor,
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding:    const EdgeInsets.symmetric(vertical: 8),
                    itemCount:  rows.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (_, i) => _BatchRow(
                      row:         rows[i],
                      accentColor: accentColor,
                      onTap:       () => Get.back(result: rows[i].batchNo),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Handle ────────────────────────────────────────────────────────────────────
class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        width:  40, height: 4,
        decoration: BoxDecoration(
          color:        Colors.grey.shade300,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String  itemCode;
  final String? warehouse;
  final Color   accentColor;

  const _Header({
    required this.itemCode,
    required this.warehouse,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, color: accentColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Batch',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (warehouse != null && warehouse!.isNotEmpty)
                  Text(
                    warehouse!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Get.back(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

// ── Search Bar ────────────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  final BatchPickerController c;
  final Color accentColor;

  const _SearchBar({required this.c, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: TextField(
        onChanged: (v) => c.searchQuery.value = v,
        decoration: InputDecoration(
          hintText:    'Search batch number…',
          prefixIcon:  Icon(Icons.search, color: accentColor, size: 20),
          suffixIcon: Obx(() => c.searchQuery.value.isNotEmpty
              ? IconButton(
                  icon:      const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    c.searchQuery.value = '';
                  },
                )
              : const SizedBox.shrink()),
          filled:    true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:   BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}

// ── Batch Row ─────────────────────────────────────────────────────────────────
class _BatchRow extends StatelessWidget {
  final BatchWiseBalanceRow row;
  final Color               accentColor;
  final VoidCallback        onTap;

  const _BatchRow({
    required this.row,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme         = Theme.of(context);
    final expiringSoon  = row.expiresWithin(30) && !row.isExpired;
    final expired       = row.isExpired;

    return InkWell(
      onTap:    onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Batch number + expiry
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.batchNo,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily:  'ShureTechMono',
                      fontWeight:  FontWeight.w600,
                      color:       expired ? Colors.red.shade400 : null,
                    ),
                  ),
                  if (row.expiryDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: _ExpiryBadge(
                        date:          row.expiryDate!,
                        expiringSoon:  expiringSoon,
                        expired:       expired,
                      ),
                    ),
                ],
              ),
            ),

            // Balance chip
            BalanceChip(
              balance:   row.balanceQty,
              isLoading: false,
              color:     expired ? Colors.grey : accentColor,
              prefix:    '',
            ),

            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                color: Colors.grey.shade400, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Expiry Badge ──────────────────────────────────────────────────────────────
class _ExpiryBadge extends StatelessWidget {
  final DateTime date;
  final bool     expiringSoon;
  final bool     expired;

  const _ExpiryBadge({
    required this.date,
    required this.expiringSoon,
    required this.expired,
  });

  @override
  Widget build(BuildContext context) {
    final label = 'Exp: ${_fmt(date)}';
    final color = expired
        ? Colors.red
        : expiringSoon
            ? Colors.amber.shade700
            : Colors.grey.shade500;
    final icon  = expired
        ? Icons.warning_rounded
        : expiringSoon
            ? Icons.schedule_rounded
            : Icons.calendar_today_outlined;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize:   10,
            color:      color,
            fontWeight: (expired || expiringSoon)
                ? FontWeight.w700
                : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ── Shimmer Skeleton ──────────────────────────────────────────────────────────
class _Skeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding:     const EdgeInsets.symmetric(vertical: 8),
      itemCount:   6,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonBar(width: 140, height: 14),
                  const SizedBox(height: 6),
                  _SkeletonBar(width: 80, height: 10),
                ],
              ),
            ),
            _SkeletonBar(width: 60, height: 22, radius: 20),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBar({
    required this.width,
    required this.height,
    this.radius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  width,
      height: height,
      decoration: BoxDecoration(
        color:        Colors.grey.shade200,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool hasSearch;
  final Color accentColor;

  const _EmptyState({required this.hasSearch, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasSearch ? Icons.search_off : Icons.inbox_outlined,
              size:  48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              hasSearch
                  ? 'No batches match your search'
                  : 'No batches with available stock',
              style: TextStyle(
                color:      Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error State ───────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final String       message;
  final VoidCallback onRetry;
  final Color        accentColor;

  const _ErrorState({
    required this.message,
    required this.onRetry,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              message,
              style:     TextStyle(color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon:  const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: accentColor,
                side: BorderSide(color: accentColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
