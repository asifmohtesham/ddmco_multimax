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

  Widget _getRelativeTimeWidget(String? modified) {
    if (modified == null || modified.isEmpty) return const SizedBox.shrink();

    try {
      final date = DateTime.parse(modified);
      final now = DateTime.now();
      final difference = now.difference(date);

      String text;
      if (difference.inDays > 0) {
        text = '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        text = '${difference.inHours}h ago';
      } else {
        text = '${difference.inMinutes}m ago';
      }

      Color color;
      Color bgColor;

      if (difference.inHours < 6) {
        color = const Color(0xFF8A6D3B); 
        bgColor = const Color(0xFFFCF8E3); 
      } else if (difference.inHours < 48) {
        color = const Color(0xFFE65100);
        bgColor = const Color(0xFFFFF3E0);
      } else {
        color = const Color(0xFFA94442);
        bgColor = const Color(0xFFF2DEDE);
      }

      return Container(
        margin: const EdgeInsets.only(top: 4.0),
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4.0),
        ),
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      );
    } catch (e) {
      return const SizedBox.shrink();
    }
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

        return Scrollbar(
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
                                  Row(
                                    children: [
                                      StatusPill(status: posUpload.status),
                                      const SizedBox(width: 8),
                                      _getRelativeTimeWidget(posUpload.modified),
                                    ],
                                  ),
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

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      clipBehavior: Clip.antiAlias,
      child: Obx(() {
        final isCurrentlyExpanded = controller.expandedNoteName.value == note.name;
        return Column(
          children: [
            ListTile(
              title: Text(note.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (note.poNo != null && note.poNo.isNotEmpty)
                    Text('PO: ${note.poNo}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                      '${note.customer} - ${_getCurrencySymbol(note.currency)}${note.grandTotal.toStringAsFixed(2)}'),
                  const SizedBox(height: 4),
                  StatusPill(status: note.status),
                ],
              ),
              trailing: AnimatedRotation(
                turns: isCurrentlyExpanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: const Icon(Icons.expand_more),
              ),
              onTap: () => controller.toggleExpand(note.name),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Container(
                child: !isCurrentlyExpanded
                    ? const SizedBox.shrink()
                    : Obx(() {
                        final detailed = controller.detailedNote;
                        if (controller.isLoadingDetails.value && detailed?.name != note.name) {
                          return const LinearProgressIndicator();
                        }

                        if (detailed != null && detailed.name == note.name) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(height: 1),
                                Padding(
                                  padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                                  child: Text('Posting Date: ${detailed.postingDate}'),
                                ),
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
                      }),
              ),
            ),
          ],
        );
      }),
    );
  }
}
