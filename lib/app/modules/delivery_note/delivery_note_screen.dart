import 'package:ddmco_multimax/app/data/utils/formatting_helper.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/delivery_note_controller.dart';
import 'package:intl/intl.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/status_pill.dart';
import 'package:ddmco_multimax/app/data/models/pos_upload_model.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/widgets/filter_bottom_sheet.dart';

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

  void _showFilterBottomSheet(BuildContext context) {
    Get.bottomSheet(
      const FilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
            icon: const Icon(Icons.filter_list), 
            onPressed: () => _showFilterBottomSheet(context),
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
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
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
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: TextField(
                      onChanged: controller.filterPosUploads,
                      decoration: InputDecoration(
                        hintText: 'Search POS Uploads',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Obx(() {
                      if (controller.isFetchingPosUploads.value) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (controller.posUploadsForSelection.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              const Text('No POS Uploads found.', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        );
                      }

                      return ListView.separated(
                        controller: scrollController,
                        itemCount: controller.posUploadsForSelection.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                        itemBuilder: (context, index) {
                          final posUpload = controller.posUploadsForSelection[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            title: Text(posUpload.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Expanded(child: Text(posUpload.customer, overflow: TextOverflow.ellipsis)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      width: 8, height: 8,
                                      decoration: BoxDecoration(
                                        color: posUpload.status == 'Pending' ? Colors.orange : Colors.blue,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(posUpload.status, style: const TextStyle(fontSize: 12)),
                                    const Spacer(),
                                    _getRelativeTimeWidget(posUpload.modified),
                                  ],
                                ),
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                            onTap: () {
                              Get.back();
                              controller.createNewDeliveryNote(posUpload);
                            },
                          );
                        },
                      );
                    }),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          Get.back();
                          controller.createNewDeliveryNote(null);
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(color: Theme.of(context).primaryColor),
                        ),
                        child: const Text('Skip & Create Blank Note'),
                      ),
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
                    FormattingHelper.getRelativeTime(note.creation),
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
                  const Spacer(),
                  if (note.docstatus == 1) // Submitted
                    Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: _buildStatItem(Icons.timer_outlined, FormattingHelper.getTimeTaken(note.creation, note.modified), color: Colors.green),
                    ),
                  // Animated Arrow
                  Obx(() {
                    final isCurrentlyExpanded = controller.expandedNoteName.value == note.name;
                    return AnimatedRotation(
                        turns: isCurrentlyExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: const Icon(Icons.expand_more, size: 20, color: Colors.grey),
                    );
                  }),
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
              Text('Grand Total: ${FormattingHelper.getCurrencySymbol(detailed.currency)}${detailed.grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Posting Date: ${detailed.postingDate}', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (detailed.status == 'Draft') ...[
                    OutlinedButton.icon(
                      onPressed: () => Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM, arguments: {'name': note.name, 'mode': 'edit'}),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        side: const BorderSide(color: Colors.blue),
                      ),
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
