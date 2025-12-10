import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/packing_slip/packing_slip_controller.dart';
import 'package:multimax/app/modules/packing_slip/widgets/packing_slip_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

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

  void _showDNSelectionBottomSheet(BuildContext context) {
    controller.fetchDeliveryNotesForSelection();

    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select Delivery Note',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Get.back(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: controller.filterDeliveryNotes,
                    decoration: const InputDecoration(
                      labelText: 'Search Delivery Notes',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Obx(() {
                      if (controller.isFetchingDNs.value) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (controller.deliveryNotesForSelection.isEmpty) {
                        return const Center(child: Text('No Delivery Notes found.'));
                      }

                      return ListView.separated(
                        controller: scrollController,
                        itemCount: controller.deliveryNotesForSelection.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                        itemBuilder: (context, index) {
                          final dn = controller.deliveryNotesForSelection[index];
                          final hasPO = dn.poNo != null && dn.poNo!.isNotEmpty;
                          final title = hasPO ? dn.poNo! : dn.name;
                          final subtitle = hasPO
                              ? '${dn.name} • ${dn.customer}'
                              : dn.customer;

                          return ListTile(
                            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Get.back();
                              controller.initiatePackingSlipCreation(dn);
                            },
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      isScrollControlled: true,
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
      body: Column(
        children: [
          // 1. Search Box
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              onChanged: controller.onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search slips, customers...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
          ),

          // 2. List
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value && controller.packingSlips.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (controller.packingSlips.isEmpty) {
                return const Center(child: Text('No packing slips found.'));
              }

              final grouped = controller.groupedPackingSlips;
              final groupKeys = grouped.keys.toList();

              if (groupKeys.isEmpty) {
                return const Center(child: Text('No results match your search.'));
              }

              return RefreshIndicator(
                onRefresh: () async {
                  await controller.fetchPackingSlips(clear: true);
                },
                child: Scrollbar(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: groupKeys.length + (controller.hasMore.value ? 1 : 0),
                    padding: const EdgeInsets.only(bottom: 80),
                    itemBuilder: (context, index) {
                      if (index >= groupKeys.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final groupKey = groupKeys[index];
                      final slips = grouped[groupKey]!;

                      // Extract Customer from first slip
                      final customerName = slips.isNotEmpty ? slips.first.customer : null;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Group Header with Customer Info
                            Container(
                              padding: const EdgeInsets.all(12.0),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.description_outlined, size: 20, color: Colors.blueGrey),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          groupKey,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                                        ),
                                        if (customerName != null && customerName.isNotEmpty)
                                          Text(
                                            customerName,
                                            style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade700),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.grey.shade300)
                                    ),
                                    child: Text('${slips.length} slips', style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            // List of Slips in this group
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: slips.length,
                              separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                              itemBuilder: (context, slipIndex) {
                                final slip = slips[slipIndex];
                                return PackingSlipListTile(slip: slip);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDNSelectionBottomSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class PackingSlipListTile extends StatelessWidget {
  final dynamic slip;
  final PackingSlipController controller = Get.find();

  PackingSlipListTile({super.key, required this.slip});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Get.toNamed(AppRoutes.PACKING_SLIP_FORM, arguments: {'name': slip.name, 'mode': 'view'}),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    slip.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                StatusPill(status: slip.status),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Packages: ${slip.fromCaseNo ?? "?"} - ${slip.toCaseNo ?? "?"}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 13),
                ),
                const Spacer(),
                Text(
                  FormattingHelper.getRelativeTime(slip.creation),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ],
            ),
            if (slip.docstatus == 1) // Submitted
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(Icons.timer_outlined, size: 12, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      FormattingHelper.getTimeTaken(slip.creation, slip.modified), // UPDATED: Show duration
                      style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}