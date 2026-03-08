import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:multimax/app/modules/home/home_controller.dart';

class TeamPerformanceCard extends StatelessWidget {
  final HomeController controller;

  const TeamPerformanceCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Team Members',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    // Navigate to detailed team view
                    Get.snackbar('Team View', 'Detailed team analytics coming soon',
                        snackPosition: SnackPosition.BOTTOM);
                  },
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('View All'),
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).primaryColor),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Obx(() {
              if (controller.isLoadingUsers.value) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (controller.userList.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text('No team members found'),
                  ),
                );
              }

              // Show top 5 team members
              final displayUsers = controller.userList.take(5).toList();

              return Column(
                children: displayUsers.map((user) {
                  // Simulate performance metrics (replace with real data)
                  final isCurrentUser = user.email == controller.selectedFilterUser.value?.email;
                  final productivity = (65 + (user.name.hashCode % 30)).clamp(0, 100) / 100;
                  final tasksCompleted = 12 + (user.name.hashCode % 15);

                  return _buildTeamMemberRow(
                    context,
                    name: user.name,
                    email: user.email,
                    productivity: productivity,
                    tasksCompleted: tasksCompleted,
                    isHighlighted: isCurrentUser,
                  );
                }).toList(),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamMemberRow(
    BuildContext context, {
    required String name,
    required String email,
    required double productivity,
    required int tasksCompleted,
    bool isHighlighted = false,
  }) {
    Color productivityColor = productivity >= 0.8
        ? Colors.green
        : productivity >= 0.5
            ? Colors.orange
            : Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isHighlighted
            ? Theme.of(context).primaryColor.withValues(alpha: 0.05)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlighted
              ? Theme.of(context).primaryColor.withValues(alpha: 0.3)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Theme.of(context).primaryColor,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$tasksCompleted tasks completed',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: productivityColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(productivity * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: productivityColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearPercentIndicator(
            padding: EdgeInsets.zero,
            lineHeight: 6,
            percent: productivity,
            backgroundColor: Colors.grey.shade200,
            progressColor: productivityColor,
            barRadius: const Radius.circular(10),
            animation: true,
            animationDuration: 500,
          ),
        ],
      ),
    );
  }
}