import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/bom/bom_controller.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';

class BomScreen extends GetView<BomController> {
  const BomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppNavDrawer(),
      body: Obx(() {
        if (controller.isLoading.value) {
          return CustomScrollView(
            slivers: [
              const DocTypeListHeader(title: 'Bill of Materials'),
              const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator())),
            ],
          );
        }

        return CustomScrollView(
          slivers: [
            const DocTypeListHeader(title: 'Bill of Materials'),
            SliverToBoxAdapter(child: _buildHeaderSummary(context)),
            _buildList(context),
          ],
        );
      }),
    );
  }

  Widget _buildHeaderSummary(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _kpi(context, 'Total BOMs', '\${controller.totalBoms}',
              colorScheme.primary),
          _kpi(context, 'Active',
              '\${(controller.activeRate * 100).toInt()}%', Colors.green),
          _kpi(
              context,
              'Avg Cost',
              NumberFormat.compactSimpleCurrency()
                  .format(controller.averageCost),
              Colors.orange),
        ],
      ),
    );
  }

  Widget _kpi(BuildContext context, String label, String value, Color color) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 4),
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildList(BuildContext context) {
    if (controller.boms.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text('No BOMs found',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final bom = controller.boms[index];
            final bool isActive = bom.isActive == 1;
            final colorScheme = Theme.of(context).colorScheme;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                elevation: isActive ? 0 : 0,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {},
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isActive
                            ? colorScheme.primary.withValues(alpha: 0.25)
                            : colorScheme.outlineVariant,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: isActive
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.layers,
                            color: isActive
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurfaceVariant),
                      ),
                      title: Text(bom.itemName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      subtitle: Text(bom.name,
                          style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\${FormattingHelper.getCurrencySymbol(bom.currency)} \${NumberFormat("#,##0").format(bom.totalCost)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? colorScheme.primaryContainer
                                      .withValues(alpha: 0.5)
                                  : colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: isActive
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          childCount: controller.boms.length,
        ),
      ),
    );
  }
}
