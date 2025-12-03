import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/delivery_note_controller.dart';
import 'package:intl/intl.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/status_pill.dart';
import 'package:ddmco_multimax/app/data/models/pos_upload_model.dart';

class DeliveryNoteScreen extends StatefulWidget {
  const DeliveryNoteScreen({super.key});

  @override
  State<DeliveryNoteScreen> createState() => _DeliveryNoteScreenState();
}

class _DeliveryNoteScreenState extends State<DeliveryNoteScreen> {
  final DeliveryNoteController controller = Get.find();
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
      controller.fetchDeliveryNotes(isLoadMore: true);
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  void _showFilterDialog(BuildContext context) {
    final customerController = TextEditingController(text: controller.activeFilters['customer']);
    String? selectedStatus = controller.activeFilters['status'];

    Get.dialog(
      AlertDialog(
        title: const Text('Filter Delivery Notes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: customerController,
              decoration: const InputDecoration(labelText: 'Customer'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedStatus,
              decoration: const InputDecoration(labelText: 'Status'),
              items: ['Draft', 'Submitted', 'Completed', 'Cancelled']
                  .map((status) => DropdownMenuItem(value: status, child: Text(status)))
                  .toList(),
              onChanged: (value) => selectedStatus = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.clearFilters();
              Get.back();
            },
            child: const Text('Clear'),
          ),
          ElevatedButton(
            onPressed: () {
              final filters = {
                if (customerController.text.isNotEmpty) 'customer': customerController.text,
                if (selectedStatus != null) 'status': selectedStatus,
              };
              controller.applyFilters(filters);
              Get.back();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: () => _showFilterDialog(context),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.deliveryNotes.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.deliveryNotes.isEmpty) {
          return const Center(child: Text('No delivery notes found.'));
        }

        return RefreshIndicator(
          onRefresh: () async {
            await controller.fetchDeliveryNotes(clear: true);
          },
          child: Scrollbar(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: controller.deliveryNotes.length + (controller.hasMore.value ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= controller.deliveryNotes.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final note = controller.deliveryNotes[index];
                return DeliveryNoteCard(note: note);
              },
            ),
          ),
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showPosUploadSelectionBottomSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showPosUploadSelectionBottomSheet(BuildContext context) {
    controller.fetchPosUploadsForSelection();

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
                        'Select POS Upload',
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
                    onChanged: controller.filterPosUploads,
                    decoration: const InputDecoration(
                      labelText: 'Search POS Uploads',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Obx(() {
                      if (controller.isFetchingPosUploads.value) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (controller.posUploadsForSelection.isEmpty) {
                        return const Center(child: Text('No POS Uploads found.'));
                      }

                      return ListView.builder(
                        controller: scrollController,
                        itemCount: controller.posUploadsForSelection.length,
                        itemBuilder: (context, index) {
                          final posUpload = controller.posUploadsForSelection[index];
                          return Card(
                            elevation: 0,
                            color: Colors.grey[50],
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            child: ListTile(
                              title: Text(posUpload.name),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${posUpload.customer} • ${posUpload.date}'),
                                  const SizedBox(height: 4),
                                  StatusPill(status: posUpload.status),
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Get.back();
                                controller.createNewDeliveryNote(posUpload);
                              },
                            ),
                          );
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Get.back();
                        controller.createNewDeliveryNote(null);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Skip & Create Blank'),
                    ),
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
}

class DeliveryNoteCard extends StatelessWidget {
  final dynamic note;
  final DeliveryNoteController controller = Get.find();

  DeliveryNoteCard({super.key, required this.note});

  String _getCurrencySymbol(String currency) {
    final format = NumberFormat.simpleCurrency(name: currency);
    return format.currencySymbol;
  }

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

  String _getTimeTaken(String creation, String modified) {
    try {
      final start = DateTime.parse(creation);
      final end = DateTime.parse(modified);
      final difference = end.difference(start);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ${difference.inHours % 24}h';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ${difference.inMinutes % 60}m';
      } else {
        return '${difference.inMinutes}m';
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
        onTap: () => controller.toggleExpand(note.name),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: PO No (Left) + Status (Right)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      note.poNo != null && note.poNo.isNotEmpty ? note.poNo! : note.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(status: note.status),
                ],
              ),
              const SizedBox(height: 6),
              
              // Row 2: Customer (Left) + Relative Time (Right)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      note.customer,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _getRelativeTime(note.creation),
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // Row 3: Stats (Total Qty, Assigned, Time Taken)
              Row(
                children: [
                  _buildStatItem(Icons.inventory_2_outlined, '${note.totalQty.toStringAsFixed(0)} Items'),
                  // Assuming 'assigned' logic exists or is planned, omitting for now as per model
                  // If 'assigned' refers to 'Assigned To', it's not in the model yet.
                  const Spacer(),
                  if (note.docstatus == 1) // Submitted
                    _buildStatItem(Icons.timer_outlined, _getTimeTaken(note.creation, note.modified), color: Colors.green),
                ],
              ),

              // Expansion Content
              Obx(() {
                final isCurrentlyExpanded = controller.expandedNoteName.value == note.name;
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
                              _buildExpandedDetails(note),
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

  Widget _buildStatItem(IconData icon, String text, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: color ?? Colors.grey.shade700, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildExpandedDetails(dynamic note) {
    return Obx(() {
      final detailed = controller.detailedNote;
      if (controller.isLoadingDetails.value && detailed?.name != note.name) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16.0),
          child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
        );
      }

      if (detailed != null && detailed.name == note.name) {
        return Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Grand Total: ${_getCurrencySymbol(detailed.currency)}${detailed.grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Posting Date: ${detailed.postingDate}', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (detailed.status == 'Draft') ...[
                    TextButton(
                      onPressed: () => Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM, arguments: {'name': note.name, 'mode': 'edit'}),
                      child: const Text('Edit'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Get.snackbar('TODO', 'Submit document'),
                      child: const Text('Submit'),
                    ),
                  ] else ...[
                    TextButton(
                      onPressed: () => Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM, arguments: {'name': note.name, 'mode': 'view'}),
                      child: const Text('View'),
                    ),
                    if (detailed.status == 'Submitted') ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Get.snackbar('TODO', 'Cancel document'),
                        child: const Text('Cancel'),
                      ),
                    ]
                  ]
                ],
              ),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    });
  }
}
