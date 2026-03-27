import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/bom_search_result.dart';
import 'package:multimax/app/modules/bom/reports/bom_search/bom_search_controller.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';

class BomSearchScreen extends GetView<BomSearchController> {
  const BomSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const MainAppBar(title: 'BOM Search'),
      body: Column(
        children: [
          // ── Filter section ───────────────────────────────────────────────
          ExpansionTile(
            title: const Text(
              'Filters',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            initiallyExpanded: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Item Code — required
                    TextFormField(
                      controller: controller.itemCodeController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Item Code *',
                        hintText:  'e.g. RM-001',
                        prefixIcon: Icon(Icons.category_outlined),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // BOM Name — optional
                    TextFormField(
                      controller: controller.bomNameController,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (controller.canRun.value) controller.runReport();
                      },
                      decoration: const InputDecoration(
                        labelText: 'BOM Name (Optional)',
                        hintText:  'e.g. BOM-RM-001-001',
                        prefixIcon: Icon(Icons.account_tree_outlined),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Action row: Run + Clear
                    Obx(() {
                      final enabled =
                          controller.canRun.value && !controller.isLoading.value;
                      return Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: enabled ? controller.runReport : null,
                              icon: controller.isLoading.value
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.search),
                              label: Text(
                                controller.isLoading.value
                                    ? 'Searching…'
                                    : 'Run Report',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: controller.clearAll,
                            icon: const Icon(Icons.clear_all),
                            label: const Text('Clear'),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 1),

          // ── Results section ────────────────────────────────────────────
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }

              if (controller.results.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.account_tree_outlined,
                        size: 64,
                        color: cs.outlineVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Enter an Item Code and run the report',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: controller.results.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) =>
                    _BomSearchResultCard(
                      result: controller.results[index],
                    ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ── Result card ────────────────────────────────────────────────────────────────

class _BomSearchResultCard extends StatelessWidget {
  final BomSearchResult result;
  const _BomSearchResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final isActive  = result.isActive;
    final isDefault = result.isDefault;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isActive
              ? cs.primary.withValues(alpha: 0.25)
              : cs.outlineVariant,
        ),
      ),
      color: cs.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row: BOM name + badges ──────────────────────
            Row(
              children: [
                Icon(
                  Icons.account_tree_rounded,
                  size: 16,
                  color: isActive ? cs.primary : cs.outlineVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    result.bom.isNotEmpty ? result.bom : '—',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Active badge
                _Badge(
                  label: isActive ? 'Active' : 'Inactive',
                  color: isActive ? cs.tertiary : cs.outline,
                  background: isActive
                      ? cs.tertiaryContainer
                      : cs.surfaceContainerHighest,
                ),
                if (isDefault) ...[
                  const SizedBox(width: 6),
                  _Badge(
                    label: 'Default',
                    color: cs.primary,
                    background: cs.primaryContainer,
                  ),
                ],
              ],
            ),
            const Divider(height: 20),
            // ── Item row ───────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Field(
                    label: 'Item Code',
                    value: result.item.isNotEmpty ? result.item : '—',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    label: 'Item Name',
                    value: result.itemName.isNotEmpty ? result.itemName : '—',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Qty + UOM row ─────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _Field(
                    label: 'Qty',
                    value: result.qty % 1 == 0
                        ? result.qty.toInt().toString()
                        : result.qty.toStringAsFixed(3),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    label: 'UOM',
                    value: result.uom.isNotEmpty ? result.uom : '—',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── _Field ───────────────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final String  label;
  final String  value;
  const _Field({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ── _Badge ──────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color  color;
  final Color  background;
  const _Badge({
    required this.label,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
