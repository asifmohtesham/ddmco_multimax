import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/manufacturing/job_card/job_card_controller.dart';
import 'package:multimax/app/modules/manufacturing/models/job_card_model.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'dart:async';

class JobCardScreen extends GetView<JobCardController> {
  const JobCardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: MainAppBar(
        title: 'Job Cards',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 28),
            onPressed: controller.fetchJobCards,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.jobCards.isEmpty) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 6));
        }

        if (controller.jobCards.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_outlined, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 24),
                Text(
                  'No Job Cards',
                  style: TextStyle(fontSize: 24, color: Colors.grey[600], fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start a Work Order to create jobs',
                  style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: controller.fetchJobCards,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: controller.jobCards.length,
            itemBuilder: (context, index) {
              final jobCard = controller.jobCards[index];
              return _JobCardTile(jobCard: jobCard, controller: controller);
            },
          ),
        );
      }),
    );
  }
}

class _JobCardTile extends StatelessWidget {
  final JobCardModel jobCard;
  final JobCardController controller;

  const _JobCardTile({required this.jobCard, required this.controller});

  Color _getStatusColor() {
    if (jobCard.isCompleted) return Colors.green;
    if (jobCard.isInProgress) return Colors.orange;
    return Colors.blue;
  }

  IconData _getStatusIcon() {
    if (jobCard.isCompleted) return Icons.check_circle;
    if (jobCard.isInProgress) return Icons.play_circle_filled;
    return Icons.circle_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _getStatusColor().withOpacity(0.3),
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () => _showJobCardDetails(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getStatusColor().withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getStatusIcon(),
                      color: _getStatusColor(),
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          jobCard.operation,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          jobCard.name,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _getStatusColor(),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      jobCard.status,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Progress Bar
              Row(
                children: [
                  Expanded(
                    child: LinearPercentIndicator(
                      padding: EdgeInsets.zero,
                      lineHeight: 16,
                      percent: jobCard.progressPercentage / 100,
                      backgroundColor: Colors.grey[200],
                      progressColor: _getStatusColor(),
                      barRadius: const Radius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${jobCard.progressPercentage.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Quantity Info
              Row(
                children: [
                  Expanded(
                    child: _InfoChip(
                      icon: Icons.inventory_2,
                      label: 'Target',
                      value: '${jobCard.forQuantity.toInt()}',
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _InfoChip(
                      icon: Icons.check_circle_outline,
                      label: 'Done',
                      value: '${jobCard.totalCompletedQty.toInt()}',
                      color: Colors.green,
                    ),
                  ),
                  if (jobCard.workstation != null) ..[
                    const SizedBox(width: 12),
                    Expanded(
                      child: _InfoChip(
                        icon: Icons.precision_manufacturing,
                        label: 'Station',
                        value: jobCard.workstation!.split(' ').first,
                        color: Colors.purple,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showJobCardDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _JobCardDetailsSheet(jobCard: jobCard, controller: controller),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
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
          ),
        ],
      ),
    );
  }
}

class _JobCardDetailsSheet extends StatefulWidget {
  final JobCardModel jobCard;
  final JobCardController controller;

  const _JobCardDetailsSheet({required this.jobCard, required this.controller});

  @override
  State<_JobCardDetailsSheet> createState() => _JobCardDetailsSheetState();
}

class _JobCardDetailsSheetState extends State<_JobCardDetailsSheet> {
  Timer? _timer;
  Duration _elapsedTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.jobCard.hasActiveTimeLog) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    final activeLog = widget.jobCard.timeLogs.firstWhere((log) => log.isActive);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedTime = DateTime.now().difference(activeLog.fromTime);
      });
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = widget.jobCard.hasActiveTimeLog;
    final canStart = widget.jobCard.isOpen || (!isRunning && !widget.jobCard.isCompleted);
    final canComplete = widget.jobCard.totalCompletedQty >= widget.jobCard.forQuantity;

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
                        widget.jobCard.operation,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Work Order: ${widget.jobCard.workOrder}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
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
                  // Timer Display (if running)
                  if (isRunning)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.orange.shade400, Colors.orange.shade600],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.4),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'RUNNING',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _formatDuration(_elapsedTime),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Progress Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Progress',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                            ),
                            Text(
                              '${widget.jobCard.totalCompletedQty.toInt()} / ${widget.jobCard.forQuantity.toInt()}',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        LinearPercentIndicator(
                          padding: EdgeInsets.zero,
                          lineHeight: 20,
                          percent: widget.jobCard.progressPercentage / 100,
                          backgroundColor: Colors.blue.shade100,
                          progressColor: Colors.blue.shade600,
                          barRadius: const Radius.circular(10),
                          center: Text(
                            '${widget.jobCard.progressPercentage.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Materials (if any)
                  if (widget.jobCard.items.isNotEmpty) ..[
                    Text(
                      'Materials',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...widget.jobCard.items.map((item) => Container(
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
                                    fontSize: 16,
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
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: item.pendingQty > 0
                                  ? Colors.orange.shade50
                                  : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${item.requiredQty.toInt()} ${item.requiredQty > 1 ? 'units' : 'unit'}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: item.pendingQty > 0
                                    ? Colors.orange.shade700
                                    : Colors.green.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
                    const SizedBox(height: 24),
                  ],

                  // Action Buttons
                  if (canStart && !isRunning)
                    _BigActionButton(
                      label: 'START WORK',
                      icon: Icons.play_arrow,
                      color: Colors.green,
                      onPressed: () => widget.controller.startJobCard(widget.jobCard.name),
                    ),

                  if (isRunning) ..[
                    _BigActionButton(
                      label: 'PAUSE',
                      icon: Icons.pause,
                      color: Colors.orange,
                      onPressed: () => widget.controller.pauseJobCard(widget.jobCard.name),
                    ),
                    const SizedBox(height: 16),
                    _BigActionButton(
                      label: 'ADD QUANTITY',
                      icon: Icons.add_circle,
                      color: Colors.blue,
                      onPressed: () => _showQuantityDialog(context),
                    ),
                  ],

                  if (!widget.jobCard.isCompleted && widget.jobCard.totalCompletedQty > 0) ..[
                    const SizedBox(height: 16),
                    _BigActionButton(
                      label: canComplete ? 'COMPLETE JOB' : 'FINISH REMAINING',
                      icon: Icons.check_circle,
                      color: canComplete ? Colors.green : Colors.grey,
                      onPressed: canComplete
                          ? () => widget.controller.completeJobCard(widget.jobCard.name)
                          : null,
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

  void _showQuantityDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Completed Quantity'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            hintText: 'Enter quantity',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () {
              final qty = double.tryParse(controller.text);
              if (qty != null && qty > 0) {
                widget.controller.updateCompletedQty(widget.jobCard.name, qty);
                Navigator.pop(context);
              }
            },
            child: const Text('Save', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _BigActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _BigActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: onPressed != null ? color : Colors.grey,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: onPressed != null ? 8 : 2,
          shadowColor: color.withOpacity(0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                fontSize: 20,
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