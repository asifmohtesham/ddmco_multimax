import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'rack_picker_controller.dart';

// ────────────────────────────────────────────────────────────────────────────
// _StatusColor
// ────────────────────────────────────────────────────────────────────────────

Color _statusColor(SufficiencyStatus status) {
  switch (status) {
    case SufficiencyStatus.sufficient:
      return Colors.green.shade600;
    case SufficiencyStatus.low:
      return Colors.orange.shade700;
    case SufficiencyStatus.empty:
      return Colors.red.shade600;
    case SufficiencyStatus.unknown:
      return Colors.grey.shade500;
  }
}

// ────────────────────────────────────────────────────────────────────────────
// _SufficiencyDot
// ────────────────────────────────────────────────────────────────────────────

class _SufficiencyDot extends StatelessWidget {
  final SufficiencyStatus status;
  const _SufficiencyDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// _SufficiencyBar
// ────────────────────────────────────────────────────────────────────────────

class _SufficiencyBar extends StatelessWidget {
  final double availableQty;
  final double requestedQty;
  final SufficiencyStatus status;

  const _SufficiencyBar({
    required this.availableQty,
    required this.requestedQty,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final color    = _statusColor(status);
    final fraction = requestedQty > 0
        ? (availableQty / requestedQty).clamp(0.0, 1.0)
        : (availableQty > 0 ? 1.0 : 0.0);

    return SizedBox(
      width: 56,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            availableQty % 1 == 0
                ? availableQty.toInt().toString()
                : availableQty.toStringAsFixed(1),
            style: TextStyle(
              fontFamily: 'ShureTechMono',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  Container(
                    color: color.withOpacity(0.15),
                    width: double.infinity,
                  ),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(color: color),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// _RackPickerTile
// ────────────────────────────────────────────────────────────────────────────

class _RackPickerTile extends StatelessWidget {
  final RackPickerEntry entry;
  final bool isSelected;
  final VoidCallback onTap;

  const _RackPickerTile({
    required this.entry,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final cs          = theme.colorScheme;
    final statusColor = _statusColor(entry.status);
    final isDisabled  = entry.status == SufficiencyStatus.empty;

    final bgColor = isSelected
        ? cs.primary.withOpacity(0.08)
        : isDisabled
            ? cs.surfaceContainerHighest.withOpacity(0.5)
            : cs.surface;

    final borderColor = isSelected
        ? cs.primary.withOpacity(0.5)
        : cs.outlineVariant.withOpacity(0.5);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isDisabled ? null : onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _SufficiencyDot(status: entry.status),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.rackName,
                        style: TextStyle(
                          fontFamily: 'ShureTechMono',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDisabled
                              ? cs.onSurface.withOpacity(0.4)
                              : cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (entry.displayLabel != entry.rackName) ...[
                        Text(
                          entry.displayLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDisabled
                                ? cs.onSurfaceVariant.withOpacity(0.4)
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (entry.warehouseName.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: statusColor.withOpacity(0.2)),
                          ),
                          child: Text(
                            entry.warehouseName,
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'ShureTechMono',
                              color: isDisabled
                                  ? statusColor.withOpacity(0.4)
                                  : statusColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _SufficiencyBar(
                  availableQty: entry.availableQty,
                  requestedQty: entry.requestedQty,
                  status: entry.status,
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle, color: cs.primary, size: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// RackPickerSheet
// ────────────────────────────────────────────────────────────────────────────

/// Bottom sheet that displays a sorted list of racks with per-rack
/// availability for the active item + batch.
///
/// A warehouse-filter toggle (default On) restricts the visible list to
/// racks whose warehouse matches the document-level warehouse. The toggle
/// is disabled when no warehouse context is available.
class RackPickerSheet extends StatelessWidget {
  final String pickerTag;
  final void Function(String rack) onSelected;

  const RackPickerSheet({
    super.key,
    required this.pickerTag,
    required this.onSelected,
  });

  static Widget _sectionLabel(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  static Widget _contextChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'ShureTechMono',
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;
    final mq    = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.75),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28.0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [

          // ── Drag handle ────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
            alignment: Alignment.center,
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Rack',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Builder (not Obx) — itemCode/batchNo/warehouse are
                      // plain String getters set once at construction.
                      Builder(builder: (_) {
                        final ctrl =
                            Get.find<RackPickerController>(tag: pickerTag);
                        return Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (ctrl.itemCode.isNotEmpty)
                              _contextChip(ctrl.itemCode, cs.primary),
                            if (ctrl.batchNo.isNotEmpty)
                              _contextChip(
                                  ctrl.batchNo, Colors.purple.shade400),
                            if (ctrl.warehouse.isNotEmpty)
                              _contextChip(
                                  ctrl.warehouse, Colors.teal.shade600),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    backgroundColor: cs.surfaceContainerHigh,
                    foregroundColor: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Scrollable body ────────────────────────────────────────────────
          // selectedRack.value and filterByWarehouse.value are both read
          // inside this single Obx so the entire body rebuilds on either
          // change — no additional Obx wrappers needed.
          Expanded(
            child: Obx(() {
              final ctrl =
                  Get.find<RackPickerController>(tag: pickerTag);

              // ── Loading ──────────────────────────────────────────────────
              if (ctrl.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }

              // ── Globally empty (no stock at all) ─────────────────────────
              if (ctrl.entries.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 48,
                          color: cs.onSurfaceVariant.withOpacity(0.4)),
                      const SizedBox(height: 12),
                      Text(
                        'No racks found with stock',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // ── Resolved display values ───────────────────────────────────
              final visible      = ctrl.visibleEntries;
              final selectedRack = ctrl.selectedRack.value;
              final filterOn     = ctrl.filterByWarehouse.value;
              final hasWarehouse = ctrl.warehouse.isNotEmpty;
              final suf          = ctrl.visibleSufficientCount;
              final tot          = visible.length;

              // ── Filtered-empty state ──────────────────────────────────────
              // The full list has racks but the warehouse filter hides them
              // all. Show a helpful nudge with a one-tap escape hatch.
              if (visible.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warehouse_outlined,
                          size: 48,
                          color: cs.onSurfaceVariant.withOpacity(0.4)),
                      const SizedBox(height: 12),
                      Text(
                        'No racks found in',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _contextChip(
                          ctrl.warehouse, Colors.teal.shade600),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: () =>
                            ctrl.filterByWarehouse.value = false,
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('Show all warehouses'),
                      ),
                    ],
                  ),
                );
              }

              // ── Loaded: banner + summary row + tiles ──────────────────────
              return CustomScrollView(
                slivers: [

                  // Fallback banner
                  if (ctrl.usedFallback.value)
                    SliverToBoxAdapter(
                      child: Container(
                        width: double.infinity,
                        color: Colors.orange.shade50,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 14,
                                color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Showing item stock'
                                ' (batch data unavailable)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Summary row + warehouse-filter toggle
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(20, 10, 12, 4),
                      child: Row(
                        children: [
                          _sectionLabel(
                              'AVAILABLE RACKS', cs.onSurfaceVariant),
                          const Spacer(),
                          // Sufficient badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: suf > 0
                                  ? Colors.green.shade600
                                      .withOpacity(0.1)
                                  : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$suf\u202f/\u202f$tot sufficient',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: suf > 0
                                    ? Colors.green.shade700
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Warehouse-filter toggle
                          // Disabled (greyed) when no warehouse context.
                          Tooltip(
                            message: hasWarehouse
                                ? (filterOn
                                    ? 'Filtering by warehouse — tap to show all'
                                    : 'Showing all warehouses — tap to filter')
                                : 'No warehouse context',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.warehouse_outlined,
                                  size: 14,
                                  color: hasWarehouse
                                      ? (filterOn
                                          ? cs.primary
                                          : cs.onSurfaceVariant
                                              .withOpacity(0.5))
                                      : cs.onSurfaceVariant
                                          .withOpacity(0.3),
                                ),
                                Transform.scale(
                                  scale: 0.75,
                                  child: Switch(
                                    value: filterOn,
                                    onChanged: hasWarehouse
                                        ? (v) => ctrl
                                            .filterByWarehouse
                                            .value = v
                                        : null,
                                    activeColor: cs.primary,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize
                                            .shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Tile list — uses visibleEntries (filtered or full)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                        16, 4, 16, mq.viewPadding.bottom + 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final entry = visible[i];
                          final isSelected =
                              selectedRack == entry.rackName;
                          return _RackPickerTile(
                            entry:      entry,
                            isSelected: isSelected,
                            onTap: () {
                              ctrl.selectRack(entry.rackName);
                              onSelected(entry.rackName);
                              Navigator.of(context).pop();
                            },
                          );
                        },
                        childCount: visible.length,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}
