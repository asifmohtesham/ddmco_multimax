import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/bom_search_result.dart';
import 'package:multimax/app/modules/bom/reports/bom_search/bom_search_controller.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';

// Filter sheet import is intentionally a forward reference — the sheet file
// is created in C4. The import resolves once C4 lands.
import 'bom_search_filter_sheet.dart';

class BomSearchScreen extends GetView<BomSearchController> {
  const BomSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      // ── AppBar with filter icon ───────────────────────────────────────
      appBar: MainAppBar(
        title: 'BOM Search',
        actions: [
          Obx(() {
            final count    = controller.activeCount.value;
            final isActive = count > 0;
            final tooltip  = isActive
                ? '$count item code${count > 1 ? 's' : ''} active — tap to edit filters'
                : 'Sub-Assembly Filters';
            final button = isActive
                ? IconButton.filled(
                    icon:      const Icon(Icons.filter_alt),
                    tooltip:   tooltip,
                    onPressed: BomSearchFilterSheet.show,
                  )
                : IconButton(
                    icon:      const Icon(Icons.filter_list),
                    tooltip:   tooltip,
                    onPressed: BomSearchFilterSheet.show,
                  );
            return isActive
                ? Badge(label: Text('$count'), child: button)
                : button;
          }),
        ],
      ),

      // ── Run Report FAB ────────────────────────────────────────
      floatingActionButton: Obx(() {
        final enabled =
            controller.canRun.value && !controller.isLoading.value;
        return FloatingActionButton.extended(
          onPressed: enabled ? controller.runReport : null,
          backgroundColor:
              enabled ? cs.primary : cs.onSurface.withValues(alpha: 0.12),
          foregroundColor:
              enabled ? cs.onPrimary : cs.onSurface.withValues(alpha: 0.38),
          icon: controller.isLoading.value
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: cs.onPrimary,
                  ),
                )
              : const Icon(Icons.search),
          label: Text(
            controller.isLoading.value ? 'Searching…' : 'Run Report',
          ),
          tooltip: enabled
              ? 'Run BOM Search'
              : 'Set Item Code 1 in filters first',
        );
      }),

      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Active filter chip strip ──────────────────────────────
          Obx(() {
            if (controller.activeCount.value == 0) {
              return const SizedBox.shrink();
            }
            return Material(
              color: cs.surfaceContainerLow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        for (int i = 0;
                            i < controller.subAssemblyControllers.length;
                            i++) ...[
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable:
                                controller.subAssemblyControllers[i],
                            builder: (_, val, __) {
                              final text = val.text.trim();
                              if (text.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Chip(
                                  avatar: CircleAvatar(
                                    backgroundColor: i == 0
                                        ? cs.primary
                                        : cs.secondaryContainer,
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: i == 0
                                            ? cs.onPrimary
                                            : cs.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                  label: Text(
                                    text,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: cs.onSecondaryContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  backgroundColor: cs.secondaryContainer,
                                  deleteIconColor: cs.onSecondaryContainer,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  side: BorderSide.none,
                                  onDeleted: () {
                                    controller.subAssemblyControllers[i]
                                        .clear();
                                    if (controller.canRun.value) {
                                      controller.runReport();
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                        ],
                        if (controller.activeCount.value > 1)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: cs.error,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                            ),
                            onPressed: () {
                              controller.clearAll();
                            },
                            icon: const Icon(Icons.clear_all, size: 16),
                            label: const Text('Clear all'),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                ],
              ),
            );
          }),

          // ── Results ────────────────────────────────────────────
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }

              if (controller.results.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
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
                          'Set Item Code 1 in filters and tap Run Report',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: BomSearchFilterSheet.show,
                          icon: const Icon(Icons.filter_list),
                          label: const Text('Open Filters'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: controller.results.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _BomSearchResultCard(
                  result: controller.results[index],
                  // Delegate navigation to controller — keeps screen logic-free
                  onTap: () => controller.navigateToBom(
                      controller.results[index].bom),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ── Result card ──────────────────────────────────────────────────

class _BomSearchResultCard extends StatelessWidget {
  final BomSearchResult result;
  final VoidCallback    onTap;
  const _BomSearchResultCard({required this.result, required this.onTap});

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
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row: BOM name + badges ────────────────────
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
                  _Badge(
                    label:      isActive ? 'Active' : 'Inactive',
                    color:      isActive ? cs.tertiary : cs.outline,
                    background: isActive
                        ? cs.tertiaryContainer
                        : cs.surfaceContainerHighest,
                  ),
                  if (isDefault) ...[
                    const SizedBox(width: 6),
                    _Badge(
                      label:      'Default',
                      color:      cs.primary,
                      background: cs.primaryContainer,
                    ),
                  ],
                  // Chevron hint — communicates the card is tappable
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
              const Divider(height: 20),
              // ── Item row ──────────────────────────────────────────
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
              // ── Qty + UOM row ───────────────────────────────────
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
              // ── Footer action row ───────────────────────────────────
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onTap,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open BOM'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _Field ──────────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final String label;
  final String value;
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

// ── _Badge ──────────────────────────────────────────────────────────────────

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
