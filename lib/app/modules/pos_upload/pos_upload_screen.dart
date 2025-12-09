import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/pos_upload/pos_upload_controller.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/pos_upload/widgets/pos_upload_filter_bottom_sheet.dart';

class PosUploadScreen extends StatefulWidget {
  const PosUploadScreen({super.key});

  @override
  State<PosUploadScreen> createState() => _PosUploadScreenState();
}

class _PosUploadScreenState extends State<PosUploadScreen> {
  final PosUploadController controller = Get.find();
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
      controller.fetchPosUploads(isLoadMore: true);
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
      const PosUploadFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return Colors.orange;
      case 'completed': return Colors.green;
      case 'failed': return Colors.red;
      case 'processed': return Colors.blue;
      default: return Colors.grey;
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('POS Uploads'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterBottomSheet(context),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.posUploads.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.posUploads.isEmpty) {
          return const Center(child: Text('No POS uploads found.'));
        }

        return RefreshIndicator(
          onRefresh: () async {
            await controller.fetchPosUploads(clear: true);
          },
          child: Scrollbar(
            child: ListView.separated(
              controller: _scrollController,
              itemCount: controller.posUploads.length + (controller.hasMore.value ? 1 : 0),
              separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                if (index >= controller.posUploads.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final upload = controller.posUploads[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(
                    upload.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              upload.customer,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey[700], fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              color: _getStatusColor(upload.status),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(upload.status, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          const Spacer(),
                          Text(
                            _getRelativeTime(upload.modified),
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    Get.toNamed(
                      AppRoutes.POS_UPLOAD_FORM, 
                      arguments: {'name': upload.name, 'mode': upload.status == 'Pending' ? 'edit' : 'view'}
                    );
                  },
                );
              },
            ),
          ),
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Get.toNamed(AppRoutes.POS_UPLOAD_FORM, arguments: {'name': '', 'mode': 'new'});
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
