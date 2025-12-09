import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/job_card/job_card_controller.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

class JobCardScreen extends GetView<JobCardController> {
  const JobCardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Job Cards'),
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
    if (controller.jobCards.isEmpty) {
      return const Center(child: Text('No Job Cards found.'));
    }
    return ListView.builder(
      itemCount: controller.jobCards.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) {
        final jc = controller.jobCards[index];
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            title: Text(jc.operation, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${jc.name} • ${jc.workOrder}'),
                if (jc.workstation != null) Text('Station: ${jc.workstation}'),
                const SizedBox(height: 4),
                Text('Qty: ${jc.totalCompletedQty} / ${jc.forQuantity}'),
              ],
            ),
            trailing: StatusPill(status: jc.status),
          ),
        );
      },
    );
  }

  Widget _buildDashboardView(BuildContext context) {
    final bool isEmpty = controller.jobCards.isEmpty;

    // Data Selection (Real vs Sample)
    final int totalCards = isEmpty ? 45 : controller.totalCards;
    final int openCards = isEmpty ? 18 : controller.openCards;
    final int completedCards = isEmpty ? 27 : controller.completedCards;

    final double completionRate = totalCards > 0 ? completedCards / totalCards : 0.0;

    final Map<String, int> operations = isEmpty
        ? {'Cutting': 12, 'Welding': 8, 'Assembly': 15, 'Quality Check': 10}
        : controller.operationBreakdown;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isEmpty) _buildSampleDataBanner(),

          const Text('Shop Floor Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Card 1: Shop Floor Load Meter
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Job Completion Rate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Icon(Icons.precision_manufacturing, color: Colors.blueGrey),
                    ],
                  ),
                  const SizedBox(height: 24),
                  LinearPercentIndicator(
                    lineHeight: 20.0,
                    percent: completionRate,
                    center: Text(
                      "${(completionRate * 100).toInt()}%",
                      style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    barRadius: const Radius.circular(10),
                    progressColor: _getColorForRate(completionRate),
                    backgroundColor: Colors.grey.shade300,
                    animation: true,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMiniStat('Open Jobs', '$openCards', Colors.orange),
                      Container(width: 1, height: 30, color: Colors.grey.shade300),
                      _buildMiniStat('Completed', '$completedCards', Colors.green),
                      Container(width: 1, height: 30, color: Colors.grey.shade300),
                      _buildMiniStat('Total', '$totalCards', Colors.blue),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          const Text('Active Operations Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          // Card 2: Operations Grid
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.5,
            children: operations.entries.map((e) {
              return Card(
                elevation: 1,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${e.value} Cards', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                          Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey.shade400),
                        ],
                      )
                    ],
                  ),
                ),
              );
            }).toList(),
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
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.insights, color: Colors.purple),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sample Data Visualization', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                Text('Assign Job Cards to workstations to see real-time shop floor load and efficiency metrics.', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Color _getColorForRate(double rate) {
    if (rate < 0.3) return Colors.red;
    if (rate < 0.7) return Colors.orange;
    return Colors.green;
  }
}