import 'package:flutter/material.dart';
import 'package:multimax/app/data/models/bom_model.dart';
import 'package:multimax/app/modules/global_widgets/info_block.dart';

/// Read-only costing summary tab.
/// Mirrors the fields visible in ERPNext’s BOM → Costing section:
/// raw material cost, operating cost, scrap material cost,
/// total cost, and process-loss percentage.
class BomCostingTab extends StatelessWidget {
  final BOM bom;
  const BomCostingTab({super.key, required this.bom});

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final currency = bom.currency.isNotEmpty ? bom.currency : 'AED';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        // ── Cost breakdown card ─────────────────────────────────────────────────
        _SectionHeader(label: 'Cost Breakdown', colorScheme: cs, textTheme: text),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: InfoBlock(
                label: 'Raw Material Cost',
                value: _fmt(bom.rawMaterialCost, currency),
                icon: Icons.inventory_2_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InfoBlock(
                label: 'Operating Cost',
                value: _fmt(bom.operatingCost, currency),
                icon: Icons.precision_manufacturing_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InfoBlock(
                label: 'Scrap Material Cost',
                value: _fmt(bom.scrapMaterialCost, currency),
                icon: Icons.delete_outline,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InfoBlock(
                label: 'Process Loss',
                value: bom.processLossPercentage > 0
                    ? '${bom.processLossPercentage.toStringAsFixed(2)} %'
                    : '-',
                icon: Icons.trending_down_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Total cost highlight card ─────────────────────────────────────────────
        _SectionHeader(label: 'Total Cost', colorScheme: cs, textTheme: text),
        const SizedBox(height: 10),
        _TotalCostCard(
          totalCost: bom.totalCost,
          currency: currency,
          colorScheme: cs,
          textTheme: text,
        ),
        const SizedBox(height: 16),

        // ── Production details ─────────────────────────────────────────────────
        _SectionHeader(
            label: 'Production Details', colorScheme: cs, textTheme: text),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: InfoBlock(
                label: 'Quantity',
                value: '${_fmtQty(bom.quantity)} ${bom.uom}',
                icon: Icons.numbers_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InfoBlock(
                label: 'Company',
                value: bom.company.isNotEmpty ? bom.company : '-',
                icon: Icons.business_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InfoBlock(
                label: 'WIP Warehouse',
                value: (bom.wipWarehouse ?? '').isNotEmpty
                    ? bom.wipWarehouse
                    : '-',
                icon: Icons.warehouse_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InfoBlock(
                label: 'FG Warehouse',
                value: (bom.fgWarehouse ?? '').isNotEmpty
                    ? bom.fgWarehouse
                    : '-',
                icon: Icons.store_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _fmt(double v, String currency) =>
      '$currency ${v.toStringAsFixed(2)}';

  static String _fmtQty(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(3);
}

// ── Section header ───────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  const _SectionHeader({
    required this.label,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

// ── Total cost highlight ─────────────────────────────────────────────────────────────────

class _TotalCostCard extends StatelessWidget {
  final double totalCost;
  final String currency;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  const _TotalCostCard({
    required this.totalCost,
    required this.currency,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.primaryContainer.withValues(alpha: 0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.account_balance_wallet_outlined,
              color: colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total Cost',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$currency ${totalCost.toStringAsFixed(2)}',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
