import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/pos_upload/pos_upload_controller.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/pos_upload/widgets/pos_upload_filter_bottom_sheet.dart';

class PosUploadScreen extends StatefulWidget {
  const PosUploadScreen({super.key});

  @override
  State<PosUploadScreen> createState() => _PosUploadScreenState();
}

class _PosUploadScreenState extends State<PosUploadScreen> {
  final PosUploadController controller = Get.find();
  final _scrollController = ScrollController();
  final _isFarFromTop = false.obs;

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
    if (_isBottom &&
        controller.hasMore.value &&
        !controller.isFetchingMore.value) {
      controller.fetchPosUploads(isLoadMore: true);
    }
    final far = _scrollController.hasClients && _scrollController.offset > 80;
    if (_isFarFromTop.value != far) _isFarFromTop.value = far;
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    return _scrollController.offset >=
        _scrollController.position.maxScrollExtent * 0.9;
  }

  void _showFilterSheet() {
    Get.bottomSheet(
      const PosUploadFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final navBarHeight = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchPosUploads(clear: true),
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Unified header ─────────────────────────────────────────────
            DocTypeListHeader(
              title: 'POS Uploads',
              activeFilters: controller.activeFilters,
              onFilterTap: _showFilterSheet,
            ),

            // ── Result count pill ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Obx(() {
                if (controller.isLoading.value &&
                    controller.posUploads.isEmpty) {
                  return const SizedBox.shrink();
                }
                final count = controller.posUploads.length;
                final hasMore = controller.hasMore.value;
                final hasFilters = controller.activeFilters.isNotEmpty;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_upload_outlined,
                                size: 14,
                                color: colorScheme.onSecondaryContainer),
                            const SizedBox(width: 6),
                            Text(
                              hasMore
                                  ? '\$count+ uploads'
                                  : '\$count upload\${count == 1 ? '' : 's'}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (hasFilters) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.filter_alt,
                                  size: 12,
                                  color: colorScheme.onSecondaryContainer
                                      .withValues(alpha: 0.7)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),

            // ── List content ───────────────────────────────────────────────
            Obx(() {
              if (controller.isLoading.value &&
                  controller.posUploads.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (controller.posUploads.isEmpty) {
                final hasFilters = controller.activeFilters.isNotEmpty;
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            hasFilters
                                ? Icons.filter_alt_off_outlined
                                : Icons.cloud_upload_outlined,
                            size: 64,
                            color: colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            hasFilters
                                ? 'No Matching Uploads'
                                : 'No POS Uploads',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hasFilters
                                ? 'Try adjusting your filters.'
                                : 'Pull to refresh or create a new upload.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          if (hasFilters)
                            FilledButton.tonalIcon(
                              onPressed: controller.clearFilters,
                              icon: const Icon(Icons.clear_all),
                              label: const Text('Clear Filters'),
                            )
                          else
                            FilledButton.tonalIcon(
                              onPressed: () =>
                                  controller.fetchPosUploads(clear: true),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reload'),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= controller.posUploads.length) {
                      if (controller.hasMore.value) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      return Padding(
                        padding: EdgeInsets.only(
                            top: 16, bottom: 16 + navBarHeight),
                        child: Center(
                          child: Text(
                            'End of results',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      );
                    }

                    final upload = controller.posUploads[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                            color: colorScheme.outlineVariant),
                      ),
                      color: colorScheme.surfaceContainerLowest,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        title: Text(
                          upload.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.person_outline,
                                    size: 14,
                                    color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    upload.customer,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                StatusPill(status: upload.status),
                                const Spacer(),
                                Text(
                                  FormattingHelper.getRelativeTime(
                                      upload.modified),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: Icon(Icons.chevron_right,
                            color: colorScheme.onSurfaceVariant),
                        onTap: () => Get.toNamed(
                          AppRoutes.POS_UPLOAD_FORM,
                          arguments: {
                            'name': upload.name,
                            'mode': upload.status == 'Pending' ? 'edit' : 'view',
                          },
                        ),
                      ),
                    );
                  },
                  childCount: controller.posUploads.length + 1,
                ),
              );
            }),
          ],
        ),
      ),
      floatingActionButton: Obx(() => _isFarFromTop.value
          ? FloatingActionButton(
              onPressed: () => Get.toNamed(AppRoutes.POS_UPLOAD_FORM,
                  arguments: {'name': '', 'mode': 'new'}),
              tooltip: 'Create POS Upload',
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              child: const Icon(Icons.add),
            )
          : FloatingActionButton.extended(
              onPressed: () => Get.toNamed(AppRoutes.POS_UPLOAD_FORM,
                  arguments: {'name': '', 'mode': 'new'}),
              icon: const Icon(Icons.add),
              label: const Text('Create'),
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            )),
    );
  }
}
