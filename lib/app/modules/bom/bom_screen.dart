import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/bom_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/bom/bom_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';

class BomScreen extends GetView<BomController> {
  const BomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar(
        title: 'Bill of Materials',
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => _showSearch(context),
          ),
        ],
      ),
      drawer: const AppNavDrawer(),
      body: Obx(() {
        if (controller.isLoading.value && controller.boms.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            _HeaderSummary(controller: controller),
            Expanded(child: _BomList(controller: controller)),
          ],
        );
      }),
    );
  }

  void _showSearch(BuildContext context) {
    showSearch(
      context: context,
      delegate: _BomSearchDelegate(controller),
    );
  }
}

// ── Search delegate ──────────────────────────────────────────────────────────────────

class _BomSearchDelegate extends SearchDelegate<String> {
  final BomController _ctrl;
  _BomSearchDelegate(this._ctrl);

  @override
  String get searchFieldLabel => 'Search BOMs…';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              query = '';
              _ctrl.onSearchChanged('');
            },
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => BackButton(
        onPressed: () {
          close(context, '');
          _ctrl.clearFilters();
        },
      );

  @override
  Widget buildSuggestions(BuildContext context) {
    _ctrl.onSearchChanged(query);
    return _buildResults(context);
  }

  @override
  Widget buildResults(BuildContext context) {
    _ctrl.onSearchChanged(query);
    return _buildResults(context);
  }

  Widget _buildResults(BuildContext context) => Obx(
        () => _BomList(controller: _ctrl, shrinkWrap: true),
      );
}

// ── Header KPI strip ────────────────────────────────────────────────────────────────────

class _HeaderSummary extends StatelessWidget {
  final BomController controller;
  const _HeaderSummary({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Obx(() => Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Kpi(
                label: 'Total BOMs',
                value: '${controller.totalBoms}',
                color: cs.primary,
              ),
              _Kpi(
                label: 'Active',
                value: '${(controller.activeRate * 100).toInt()}%',
                color: cs.tertiary,
              ),
              _Kpi(
                label: 'Avg Cost',
                value: NumberFormat.compactSimpleCurrency()
                    .format(controller.averageCost),
                color: cs.secondary,
              ),
            ],
          ),
        ));
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Kpi(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w800, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── BOM list ──────────────────────────────────────────────────────────────────────────

class _BomList extends StatelessWidget {
  final BomController controller;
  final bool shrinkWrap;
  const _BomList({required this.controller, this.shrinkWrap = false});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final boms = controller.boms;
      if (boms.isEmpty) {
        return const Center(child: Text('No BOMs found'));
      }
      return ListView.separated(
        shrinkWrap: shrinkWrap,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: boms.length + (controller.hasMore.value ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == boms.length) {
            controller.fetchBOMs(isLoadMore: true);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: controller.isFetchingMore.value
                  ? const Center(child: CircularProgressIndicator())
                  : const SizedBox.shrink(),
            );
          }
          return _BomCard(
            bom: boms[index],
            onTap: () => Get.toNamed(
              AppRoutes.BOM_FORM,
              arguments: {'name': boms[index].name},
            ),
            onCreateWo: () => Get.toNamed(
              AppRoutes.WORK_ORDER_FORM,
              arguments: {
                'mode': 'new',
                'name': '',
                'prefill': {
                  'production_item': boms[index].item,
                  'item_name':       boms[index].itemName ?? '',
                  'bom_no':          boms[index].name,
                  'qty':             boms[index].quantity,
                },
              },
            ),
          );
        },
      );
    });
  }
}

// ── BOM card ───────────────────────────────────────────────────────────────────────────

class _BomCard extends StatelessWidget {
  final BOM bom;
  final VoidCallback onTap;
  final VoidCallback onCreateWo;
  const _BomCard({
    required this.bom,
    required this.onTap,
    required this.onCreateWo,
  });

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final isActive = bom.isActive == 1;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? cs.primary.withValues(alpha: 0.25)
              : cs.outlineVariant,
        ),
        boxShadow: [
          if (isActive)
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  backgroundColor: isActive
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest,
                  child: Icon(
                    Icons.layers,
                    color: isActive
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),

                // Title + subtitle
                // itemName is String? — guard with ?? fallback to item code
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
                      Text(
                        bom.name,
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),

                // Trailing: cost + status badge + WO button
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // currency is String? — null-coalesce before passing
                    Text(
                      '${FormattingHelper.getCurrencySymbol(bom.currency ?? '')} '
                      '${NumberFormat("#,##0").format(bom.totalCost)}',
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
      ),
    );
  }
}
