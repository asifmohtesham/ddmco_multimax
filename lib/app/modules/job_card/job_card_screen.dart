import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/job_card/job_card_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';

class JobCardScreen extends GetView<JobCardController> {
  const JobCardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppNavDrawer(),
      body: Obx(() {
        if (controller.isLoading.value) {
          return CustomScrollView(
            slivers: [
              const DocTypeListHeader(title: 'Job Cards'),
              const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator())),
            ],
          );
        }

        return CustomScrollView(
          slivers: [
            const DocTypeListHeader(title: 'Job Cards'),
            SliverToBoxAdapter(child: _buildShopFloorStats(context)),
            _buildTaskList(context),
          ],
        );
      }),
    );
  }

  Widget _buildShopFloorStats(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem(context, 'Pending', '\${controller.openCards}',
              Colors.orange),
          _statItem(context, 'Completed', '\${controller.completedCards}',
              Colors.green),
          _statItem(context, 'Total', '\${controller.totalCards}',
              colorScheme.primary),
        ],
      ),
    );
  }

  Widget _statItem(
      BuildContext context, String label, String val, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(val,
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style:
                  theme.textTheme.labelSmall?.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _buildTaskList(BuildContext context) {
    if (controller.jobCards.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text('No job cards found',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final jc = controller.jobCards[index];
            final bool isOpen =
                jc.status == 'Open' || jc.status == 'Work In Progress';
            final color = _statusColor(jc.status, colorScheme);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: colorScheme.surfaceContainerLowest,
                elevation: isOpen ? 1 : 0,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () {},
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          height: 50,
                          width: 50,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child:
                              Icon(Icons.build, color: color),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(jc.operation,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              const SizedBox(height: 4),
                              Text(
                                '\${jc.workstation ?? "Unassigned"} • \${jc.totalCompletedQty.toInt()}/\${jc.forQuantity.toInt()} units',
                                style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        if (isOpen)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('START',
                                style: TextStyle(
                                    color: colorScheme.onPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
          childCount: controller.jobCards.length,
        ),
      ),
    );
  }

  Color _statusColor(String status, ColorScheme colorScheme) {
    switch (status) {
      case 'Open':
        return Colors.orange;
      case 'Work In Progress':
        return colorScheme.primary;
      case 'Completed':
        return Colors.green;
      default:
        return colorScheme.onSurfaceVariant;
    }
  }
}
