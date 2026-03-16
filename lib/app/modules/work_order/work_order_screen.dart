import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/work_order/work_order_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

class WorkOrderScreen extends GetView<WorkOrderController> {
  const WorkOrderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppNavDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        label: const Text('New Order'),
        icon: const Icon(Icons.add),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return CustomScrollView(
            slivers: [
              const DocTypeListHeader(title: 'Work Orders'),
              const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator())),
            ],
          );
        }

        if (controller.workOrders.isEmpty) {
          return CustomScrollView(
            slivers: [
              const DocTypeListHeader(title: 'Work Orders'),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.precision_manufacturing_outlined,
                          size: 64, color: colorScheme.outlineVariant),
                      const SizedBox(height: 16),
                      Text('No Active Orders',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        return CustomScrollView(
          slivers: [
            const DocTypeListHeader(title: 'Work Orders'),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final wo = controller.workOrders[index];
                    final double percent = (wo.qty > 0)
                        ? (wo.producedQty / wo.qty).clamp(0.0, 1.0)
                        : 0.0;
                    final bool isCompleted = wo.status == 'Completed';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                              color: colorScheme.outlineVariant),
                        ),
                        color: colorScheme.surfaceContainerLowest,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  StatusPill(status: wo.status),
                                  Text(wo.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                              color: colorScheme
                                                  .onSurfaceVariant)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                wo.itemName,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Produced',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                    color: colorScheme
                                                        .onSurfaceVariant)),
                                        const SizedBox(height: 4),
                                        RichText(
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text:
                                                    '\${wo.producedQty.toInt()}',
                                                style: TextStyle(
                                                    color:
                                                        colorScheme.primary,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 16),
                                              ),
                                              TextSpan(
                                                text:
                                                    ' / \${wo.qty.toInt()}',
                                                style: TextStyle(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                    fontSize: 14),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!isCompleted)
                                    CircularProgressIndicator(
                                      value: percent,
                                      backgroundColor:
                                          colorScheme.surfaceContainerHighest,
                                      color: colorScheme.primary,
                                      strokeWidth: 4,
                                    ),
                                  if (isCompleted)
                                    Icon(Icons.check_circle,
                                        color: Colors.green, size: 32),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: percent,
                                  minHeight: 6,
                                  backgroundColor:
                                      colorScheme.surfaceContainerHighest,
                                  color: isCompleted
                                      ? Colors.green
                                      : colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: controller.workOrders.length,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
