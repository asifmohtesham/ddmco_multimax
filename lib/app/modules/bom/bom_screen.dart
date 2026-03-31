import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/bom_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/bom/bom_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';

class BomScreen extends StatefulWidget {
  const BomScreen({super.key});

  @override
  State<BomScreen> createState() => _BomScreenState();
}

class _BomScreenState extends State<BomScreen> {
  final BomController controller = Get.find();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.offset >=
        _scrollController.position.maxScrollExtent * 0.9;
    if (atBottom &&
        controller.hasMore.value &&
        !controller.isFetchingMore.value) {
      controller.fetchBOMs(isLoadMore: true);
    }
  }

  List<Widget> _buildFilterChips(BuildContext context) {
    final chips = <Widget>[];
    final cs = Theme.of(context).colorScheme;

    Widget chip({
      required IconData icon,
      required String label,
      required VoidCallback onDeleted,
    }) =>
        Chip(
          avatar: Icon(icon, size: 16, color: cs.onSecondaryContainer),
          label: Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w600)),
          backgroundColor: cs.secondaryContainer,
          deleteIconColor: cs.onSecondaryContainer,
          onDeleted: onDeleted,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        );

    if (controller.searchQuery.value.isNotEmpty) {
      chips.add(chip(
        icon: Icons.search,
        label: 'Search: ${controller.searchQuery.value}',
        onDeleted: () {
          controller.searchQuery.value = '';
          controller.fetchBOMs(clear: true);
        },
      ));
    }
    // "Active only" chip — shown when pre-seeded from dashboard OR set manually
    if (controller.activeFilters.containsKey('is_active')) {
      chips.add(chip(
        icon: Icons.check_circle_outline,
        label: 'Active only',
        onDeleted: () => controller.removeFilter('is_active'),
      ));
    }
    // "Submitted" chip — shown when docstatus filter is active
    if (controller.activeFilters.containsKey('docstatus')) {
      chips.add(chip(
        icon: Icons.verified_outlined,
        label: 'Submitted',
        onDeleted: () => controller.removeFilter('docstatus'),
      ));
    }
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Use injected page title (from dashboard args) or fall back to default
    final screenTitle = controller.pageTitle ?? 'Bill of Materials';

    return AppShellScaffold(
      // ── FAB: New BOM ───────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Get.toNamed(
          AppRoutes.BOM_FORM,
          arguments: {'name': '', 'mode': 'new'},
        ),
        label: const Text('New BOM'),
        icon: const Icon(Icons.account_tree_outlined),
        tooltip: 'Create new Bill of Materials',
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchBOMs(clear: true),
        color: cs.primary,
        backgroundColor: cs.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Unified header ─────────────────────────────────────────
            DocTypeListHeader(
              title: screenTitle,
              searchDoctype:      'BOM',
              searchQuery:        controller.searchQuery,
              onSearchChanged:    controller.onSearchChanged,
              onSearchClear:      controller.clearFilters,
              activeFilters:      controller.activeFilters,
              filterChipsBuilder: _buildFilterChips,
              onClearAllFilters:  controller.clearFilters,
            ),

            // ── KPI strip + list — single Obx owns all Rx reads ────────
            Obx(() {
              if (controller.isLoading.value && controller.boms.isEmpty) {
                return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()));
              }

              if (controller.boms.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.account_tree_outlined,
                              size: 64, color: cs.outlineVariant),
                          const SizedBox(height: 16),
                          Text('No BOMs Found',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(
                            controller.activeFilters.isNotEmpty
                                ? 'Try clearing the active filter to see all BOMs.'
                                : 'Tap "+ New BOM" to create your first Bill of Materials.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                          ),
                          const SizedBox(height: 24),
                          if (controller.activeFilters.isNotEmpty)
                            FilledButton.tonalIcon(
                              onPressed: controller.clearFilters,
                              icon: const Icon(Icons.filter_alt_off),
                              label: const Text('Clear Filter'),
                            )
                          else
                            FilledButton.tonalIcon(
                              onPressed: () => controller.fetchBOMs(clear: true),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reload'),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final boms = controller.boms;
              return SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: _BomKpiStrip(controller: controller),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index >= boms.length) {
                            return controller.hasMore.value
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: CircularProgressIndicator()))
                                : const SizedBox(height: 80);
                          }
                          final bom = boms[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _BomCard(
                              bom: bom,
                              onTap: () => Get.toNamed(
                                AppRoutes.BOM_FORM,
                                arguments: {'name': bom.name},
                              ),
                              onCreateWo: () => Get.toNamed(
                                AppRoutes.WORK_ORDER_FORM,
                                arguments: {
                                  'mode': 'new',
                                  'name': '',
                                  'prefill': {
                                    'production_item': bom.item,
                                    'item_name':       bom.itemName ?? '',
                                    'bom_no':          bom.name,
                                    'qty':             bom.quantity,
                                  },
                                },
                              ),
                            ),
                          );
                        },
                        childCount: boms.length + 1,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── KPI strip ──────────────────────────────────────────────────────────────────

class _BomKpiStrip extends StatelessWidget {
  final BomController controller;
  const _BomKpiStrip({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _Kpi('Total', '${controller.totalBoms}', cs.primary),
          const SizedBox(width: 8),
          _Kpi('Active',
              '${(controller.activeRate * 100).toInt()}%', cs.tertiary),
          const SizedBox(width: 8),
          _Kpi(
              'Avg Cost',
              NumberFormat.compactSimpleCurrency()
                  .format(controller.averageCost),
              cs.secondary),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Kpi(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── BOM card ───────────────────────────────────────────────────────────────────

class _BomCard extends StatelessWidget {
  final BOM bom;
  final VoidCallback onTap;
  final VoidCallback onCreateWo;
  const _BomCard(
      {required this.bom, required this.onTap, required this.onCreateWo});

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final isActive = bom.isActive == 1;

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
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: isActive
                    ? cs.primaryContainer
                    : cs.surfaceContainerHighest,
                child: Icon(Icons.layers,
                    color: isActive
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (bom.itemName?.isNotEmpty ?? false)
                          ? bom.itemName!
                          : bom.item,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(bom.name,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${FormattingHelper.getCurrencySymbol(bom.currency ?? '')} '
                    '${NumberFormat('#,##0').format(bom.totalCost)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isActive
                              ? cs.tertiaryContainer
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontSize: 10,
                            color: isActive
                                ? cs.onTertiaryContainer
                                : cs.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: onCreateWo,
                        child: Tooltip(
                          message: 'Create Work Order',
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.precision_manufacturing_outlined,
                              size: 14,
                              color: cs.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
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
