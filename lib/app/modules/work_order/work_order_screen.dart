import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/work_order/work_order_controller.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/status_pill.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:intl/intl.dart';

class WorkOrderScreen extends GetView<WorkOrderController> {
  const WorkOrderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Work Orders'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'List'),
              Tab(text: 'Dashboard'),
            ],
          ),
        ),
        body: Obx(() {
          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }
          return TabBarView(
            children: [
              _buildListView(),
              _buildDashboardView(context),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildListView() {
    if (controller.workOrders.isEmpty) {
      return const Center(child: Text('No Work Orders found.'));
    }
    return ListView.builder(
      itemCount: controller.workOrders.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) {
        final wo = controller.workOrders[index];
        final percent = (wo.qty > 0) ? (wo.producedQty / wo.qty).clamp(0.0, 1.0) : 0.0;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(wo.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                    StatusPill(status: wo.status),
                  ],
                ),
                const SizedBox(height: 8),
                Text(wo.itemName, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 4),
                Text('Start: ${wo.plannedStartDate}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Produced: ${wo.producedQty} / ${wo.qty}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${(percent * 100).toInt()}%', style: const TextStyle(color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 4),
                LinearPercentIndicator(
                  lineHeight: 6.0,
                  percent: percent,
                  backgroundColor: Colors.grey.shade200,
                  progressColor: Colors.blue,
                  barRadius: const Radius.circular(3),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDashboardView(BuildContext context) {
    final bool isEmpty = controller.workOrders.isEmpty;

    // Data Selection (Real vs Sample)
    final int totalCount = isEmpty ? 24 : controller.totalCount;
    final int inProcess = isEmpty ? 8 : controller.countInProgress;
    final int completed = isEmpty ? 12 : controller.countCompleted;
    final int draft = isEmpty ? 4 : controller.countDraft;

    final double overallProgress = isEmpty ? 0.65 : controller.overallProgress;
    final double producedQty = isEmpty ? 1540 : controller.totalProducedQty;
    final double plannedQty = isEmpty ? 2360 : controller.totalPlannedQty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isEmpty) _buildSampleDataBanner(),

          const Text('Production Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Top Row: Circular Gauge & Summary
          Row(
            children: [
              Expanded(
                flex: 5,
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        CircularPercentIndicator(
                          radius: 50.0,
                          lineWidth: 10.0,
                          percent: overallProgress,
                          center: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "${(overallProgress * 100).toInt()}%",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20.0),
                              ),
                              const Text("Produced", style: TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                          progressColor: Colors.blue,
                          backgroundColor: Colors.blue.shade50,
                          circularStrokeCap: CircularStrokeCap.round,
                        ),
                        const SizedBox(height: 16),
                        const Text('Overall Yield', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                        Text('${NumberFormat.compact().format(producedQty)} / ${NumberFormat.compact().format(plannedQty)} Items', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    _buildStatCard('Active Orders', inProcess.toString(), Icons.settings, Colors.orange),
                    const SizedBox(height: 12),
                    _buildStatCard('Completed', completed.toString(), Icons.check_circle, Colors.green),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Text('Work Order Pipeline', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          // Pipeline / Funnel Chart (Simulated with Bars)
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildPipelineRow('Draft / Pending', draft, totalCount, Colors.grey),
                  const SizedBox(height: 16),
                  _buildPipelineRow('In Production', inProcess, totalCount, Colors.blue),
                  const SizedBox(height: 16),
                  _buildPipelineRow('Completed', completed, totalCount, Colors.green),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSampleDataBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.blue),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sample Data Mode', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                Text('Add Work Orders to track production progress and yield in real-time.', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2)),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPipelineRow(String label, int count, int total, Color color) {
    double pct = total > 0 ? (count / total) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text('$count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        Stack(
          children: [
            Container(height: 8, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4))),
            FractionallySizedBox(
              widthFactor: pct.clamp(0.0, 1.0),
              child: Container(height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
            ),
          ],
        )
      ],
    );
  }
}