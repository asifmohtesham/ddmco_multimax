import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/manufacturing/work_order/work_order_controller.dart';
import 'package:multimax/app/modules/manufacturing/models/work_order_model.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

class WorkOrderScreen extends GetView<WorkOrderController> {
  const WorkOrderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: MainAppBar(
        title: 'Work Orders',
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, size: 26),
            onPressed: () => _showFilterSheet(context),
            tooltip: 'Filter',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 26),
            onPressed: controller.fetchWorkOrders,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.workOrders.isEmpty) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 6));
        }

        if (controller.workOrders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.factory_outlined, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 24),
                Text(
                  'No Work Orders',
                  style: TextStyle(
                    fontSize: 24,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: controller.fetchWorkOrders,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: controller.workOrders.length,
            itemBuilder: (context, index) {
              final wo = controller.workOrders[index];
              return _WorkOrderCard(workOrder: wo, controller: controller);
            },
          ),
        );
      }),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Filter Work Orders',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ...[('All', null), ('In Process', 'In Process'), ('Not Started', 'Not Started'), ('Completed', 'Completed')]
                .map((filter) => ListTile(
                      title: Text(
                        filter.$1,
                        style: const TextStyle(fontSize: 18),
                      ),
                      trailing: Obx(() => Radio<String?>(
                            value: filter.$2,
                            groupValue: controller.statusFilter.value,
                            onChanged: (val) {
                              controller.statusFilter.value = val;
                              controller.fetchWorkOrders();
                              Navigator.pop(context);
                            },
                          )),
                      onTap: () {
                        controller.statusFilter.value = filter.$2;
                        controller.fetchWorkOrders();
                        Navigator.pop(context);
                      },
                    )),
          ],
        ),
      ),
    );
  }
}

class _WorkOrderCard extends StatelessWidget {
  final WorkOrderModel workOrder;
  final WorkOrderController controller;

  const _WorkOrderCard({required this.workOrder, required this.controller});

  Color _getStatusColor() {
    if (workOrder.isCompleted) return Colors.green;
    if (workOrder.isInProcess) return Colors.blue;
    if (workOrder.isStopped) return Colors.red;
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: _getStatusColor().withOpacity(0.3),
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () => _showWorkOrderDetails(context),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  CircularPercentIndicator(
                    radius: 32,
                    lineWidth: 6,
                    percent: workOrder.progressPercentage / 100,
                    center: Text(
                      '${workOrder.progressPercentage.toInt()}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    progressColor: _getStatusColor(),
                    backgroundColor: Colors.grey.shade200,
                    circularStrokeCap: CircularStrokeCap.round,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workOrder.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          workOrder.productionItem,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(status: workOrder.status, color: _getStatusColor()),
                ],
              ),

              const SizedBox(height: 20),

              // Progress Bar
              LinearPercentIndicator(
                padding: EdgeInsets.zero,
                lineHeight: 14,
                percent: workOrder.progressPercentage / 100,
                backgroundColor: Colors.grey[200],
                progressColor: _getStatusColor(),
                barRadius: const Radius.circular(7),
              ),

              const SizedBox(height: 20),

              // Quantity Info
              Row(
                children: [
                  Expanded(
                    child: _MetricBox(
                      icon: Icons.flag,
                      label: 'Target',
                      value: workOrder.qty.toInt().toString(),
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricBox(
                      icon: Icons.check_circle,
                      label: 'Produced',
                      value: workOrder.producedQty.toInt().toString(),
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricBox(
                      icon: Icons.pending_actions,
                      label: 'Pending',
                      value: (workOrder.qty - workOrder.producedQty).toInt().toString(),
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),

              // Material Status Indicator
              if (workOrder.materialTransferredQty != null) ..[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getMaterialStatusColor().withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _getMaterialStatusColor().withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getMaterialStatusIcon(),
                        color: _getMaterialStatusColor(),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _getMaterialStatusText(),
                          style: TextStyle(
                            color: _getMaterialStatusColor(),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getMaterialStatusColor() {
    if (workOrder.materialTransferredQty == null) return Colors.grey;
    if (workOrder.materialTransferredQty! >= workOrder.qty) return Colors.green;
    if (workOrder.materialTransferredQty! > 0) return Colors.orange;
    return Colors.red;
  }

  IconData _getMaterialStatusIcon() {
    if (workOrder.materialTransferredQty == null) return Icons.help_outline;
    if (workOrder.materialTransferredQty! >= workOrder.qty) return Icons.check_circle;
    if (workOrder.materialTransferredQty! > 0) return Icons.warning_amber;
    return Icons.error;
  }

  String _getMaterialStatusText() {
    if (workOrder.materialTransferredQty == null) return 'Material status unknown';
    if (workOrder.materialTransferredQty! >= workOrder.qty) return 'All materials transferred';
    if (workOrder.materialTransferredQty! > 0) return 'Partial material transfer';
    return 'Materials not transferred';
  }

  void _showWorkOrderDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _WorkOrderDetailsSheet(workOrder: workOrder, controller: controller),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final Color color;

  const _StatusBadge({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Text(
        status,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _WorkOrderDetailsSheet extends StatelessWidget {
  final WorkOrderModel workOrder;
  final WorkOrderController controller;

  const _WorkOrderDetailsSheet({required this.workOrder, required this.controller});

  @override
  Widget build(BuildContext context) {
    final canStart = workOrder.status == 'Not Started' || workOrder.status == 'Draft';
    final canStop = workOrder.isInProcess;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workOrder.name,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        workOrder.productionItem,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 32),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Progress Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.3),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${workOrder.producedQty.toInt()} / ${workOrder.qty.toInt()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'PRODUCED',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        LinearPercentIndicator(
                          padding: EdgeInsets.zero,
                          lineHeight: 20,
                          percent: workOrder.progressPercentage / 100,
                          backgroundColor: Colors.white.withOpacity(0.3),
                          progressColor: Colors.white,
                          barRadius: const Radius.circular(10),
                          center: Text(
                            '${workOrder.progressPercentage.toInt()}%',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Operations
                  if (workOrder.operations.isNotEmpty) ..[
                    Text(
                      'Operations',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...workOrder.operations.map((op) {
                      final isCompleted = op.status == 'Completed';
                      final isInProgress = op.status == 'Work In Progress';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isCompleted
                              ? Colors.green.shade50
                              : isInProgress
                                  ? Colors.blue.shade50
                                  : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCompleted
                                ? Colors.green.shade200
                                : isInProgress
                                    ? Colors.blue.shade200
                                    : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isCompleted
                                  ? Icons.check_circle
                                  : isInProgress
                                      ? Icons.play_circle
                                      : Icons.circle_outlined,
                              color: isCompleted
                                  ? Colors.green
                                  : isInProgress
                                      ? Colors.blue
                                      : Colors.grey,
                              size: 32,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    op.operation,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (op.workstation != null)
                                    Text(
                                      op.workstation!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  Text(
                                    '${op.timeInMins.toInt()} mins',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isCompleted
                                    ? Colors.green
                                    : isInProgress
                                        ? Colors.blue
                                        : Colors.grey,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                op.status,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                  ],

                  // Required Materials
                  if (workOrder.requiredItems.isNotEmpty) ..[
                    Text(
                      'Required Materials',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...workOrder.requiredItems.map((item) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.inventory_2, color: Colors.grey[600], size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.itemCode,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                if (item.itemName != null)
                                  Text(
                                    item.itemName!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                Text(
                                  'Required: ${item.requiredQty.toInt()}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${item.transferredQty.toInt()}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: item.isFullyTransferred ? Colors.green : Colors.orange,
                                ),
                              ),
                              Text(
                                'transferred',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )),
                    const SizedBox(height: 24),
                  ],

                  // Action Buttons
                  if (canStart)
                    _ActionButton(
                      label: 'START PRODUCTION',
                      icon: Icons.play_arrow,
                      color: Colors.green,
                      onPressed: () => controller.startWorkOrder(workOrder.name),
                    ),

                  if (canStop) ..[
                    _ActionButton(
                      label: 'STOP PRODUCTION',
                      icon: Icons.stop,
                      color: Colors.red,
                      onPressed: () => controller.stopWorkOrder(workOrder.name),
                    ),
                    const SizedBox(height: 16),
                    _ActionButton(
                      label: 'VIEW JOB CARDS',
                      icon: Icons.assignment,
                      color: Colors.blue,
                      onPressed: () {
                        Navigator.pop(context);
                        // Navigate to job cards filtered by this work order
                      },
                    ),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 6,
          shadowColor: color.withOpacity(0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}