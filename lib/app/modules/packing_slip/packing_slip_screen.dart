import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/packing_slip/packing_slip_controller.dart';
import 'package:ddmco_multimax/app/modules/packing_slip/widgets/packing_slip_filter_bottom_sheet.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/status_pill.dart';
import 'package:intl/intl.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart';

class PackingSlipScreen extends StatefulWidget {
  const PackingSlipScreen({super.key});

  @override
  State<PackingSlipScreen> createState() => _PackingSlipScreenState();
}

class _PackingSlipScreenState extends State<PackingSlipScreen> {
  final PackingSlipController controller = Get.find();
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
    if (_isBottom && controller.hasMore.value && !controller.isFetchingMore.value) {
      controller.fetchPackingSlips(isLoadMore: true);
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  void _showFilterBottomSheet(BuildContext context) {
    Get.bottomSheet(
      const PackingSlipFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Packing Slips'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterBottomSheet(context),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.packingSlips.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.packingSlips.isEmpty) {
          return const Center(child: Text('No packing slips found.'));
        }

        return RefreshIndicator(
          onRefresh: () async {
            await controller.fetchPackingSlips(clear: true);
          },
          child: Scrollbar(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: controller.packingSlips.length + (controller.hasMore.value ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= controller.packingSlips.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final slip = controller.packingSlips[index];
                return PackingSlipCard(slip: slip);
              },
            ),
          ),
        );
      }),
    );
  }
}

class PackingSlipCard extends StatelessWidget {
  final dynamic slip;
  final PackingSlipController controller = Get.find();

  PackingSlipCard({super.key, required this.slip});

  String _getRelativeTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return '';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => controller.toggleExpand(slip.name),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: PO Number (or Name) + Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      slip.customPoNo != null && slip.customPoNo.isNotEmpty ? slip.customPoNo : slip.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(status: slip.status),
                ],
              ),
              const SizedBox(height: 6),
              
              // Row 2: Owner + Time
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          slip.owner ?? 'Unknown',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _getRelativeTime(slip.creation),
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // Row 3: Case Range (if available)
              if (slip.fromCaseNo != null && slip.toCaseNo != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 14, color: Colors.blue.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Packages: ${slip.fromCaseNo} - ${slip.toCaseNo}',
                        style: TextStyle(
                          color: Colors.blue.shade900,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              
              // Expansion Content
              Obx(() {
                final isCurrentlyExpanded = controller.expandedSlipName.value == slip.name;
                return AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Container(
                    child: !isCurrentlyExpanded
                        ? const SizedBox.shrink()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 12),
                              // Expanded details (can add more here if needed, keeping it simple for now)
                              if (slip.customPoNo != null && slip.customPoNo != slip.name)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Text('Document: ${slip.name}', style: const TextStyle(color: Colors.grey)),
                                ),
                              if (slip.deliveryNote.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Text('Linked DN: ${slip.deliveryNote}', style: const TextStyle(fontWeight: FontWeight.w500)),
                                ),
                              
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () => Get.toNamed(AppRoutes.PACKING_SLIP_FORM, arguments: {'name': slip.name, 'mode': 'view'}),
                                    child: const Text('View Full Details'),
                                  ),
                                ],
                              )
                            ],
                          ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
