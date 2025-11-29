import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/pos_upload/pos_upload_controller.dart';
import 'package:intl/intl.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/status_pill.dart';

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

  void _showFilterDialog(BuildContext context) {
    final statusController = TextEditingController(text: controller.activeFilters['status']);

    Get.dialog(
      AlertDialog(
        title: const Text('Filter POS Uploads'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: statusController,
              decoration: const InputDecoration(labelText: 'Status'),
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
                if (statusController.text.isNotEmpty) 'status': statusController.text,
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
        title: const Text('POS Uploads'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: () => _showFilterDialog(context),
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

        return Scrollbar(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: controller.posUploads.length + (controller.hasMore.value ? 1 : 0),
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
              return PosUploadCard(upload: upload);
            },
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

class PosUploadCard extends StatelessWidget {
  final dynamic upload;
  final PosUploadController controller = Get.find();

  PosUploadCard({super.key, required this.upload});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      clipBehavior: Clip.antiAlias,
      child: Obx(() {
        final isCurrentlyExpanded = controller.expandedUploadName.value == upload.name;
        return Column(
          children: [
            ListTile(
              title: Text(upload.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Modified: ${upload.modified}'),
                  const SizedBox(height: 4),
                  StatusPill(status: upload.status),
                ],
              ),
              trailing: AnimatedRotation(
                turns: isCurrentlyExpanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: const Icon(Icons.expand_more),
              ),
              onTap: () => controller.toggleExpand(upload.name),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Container(
                child: !isCurrentlyExpanded
                    ? const SizedBox.shrink()
                    : Obx(() {
                        final detailed = controller.detailedUpload;
                        if (controller.isLoadingDetails.value && detailed?.name != upload.name) {
                          return const LinearProgressIndicator();
                        }

                        if (detailed != null && detailed.name == upload.name) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(height: 1),
                                Padding(
                                  padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                                  child: Text('Modified On: ${detailed.modified}'),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (detailed.status == 'Draft') ...[
                                      TextButton(
                                        onPressed: () => Get.snackbar('TODO', 'Submit document'),
                                        child: const Text('Submit'),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed: () => Get.toNamed(AppRoutes.POS_UPLOAD_FORM, arguments: {'name': upload.name, 'mode': 'edit'}),
                                        child: const Text('Edit'),
                                      ),
                                    ] else if (detailed.status == 'Submitted') ...[
                                      TextButton(
                                        onPressed: () => Get.toNamed(AppRoutes.POS_UPLOAD_FORM, arguments: {'name': upload.name, 'mode': 'view'}),
                                        child: const Text('View'),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed: () => Get.snackbar('TODO', 'Cancel document'),
                                        child: const Text('Cancel'),
                                      ),
                                    ] else ...[
                                      ElevatedButton(
                                        onPressed: () => Get.toNamed(AppRoutes.POS_UPLOAD_FORM, arguments: {'name': upload.name, 'mode': 'view'}),
                                        child: const Text('View'),
                                      ),
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
