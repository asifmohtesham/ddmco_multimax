import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/result_count_pill.dart';
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

  List<Widget> _buildActiveFilterChips(BuildContext context) {
    final chips = <Widget>[];
    final f = controller.activeFilters;

    if (controller.searchQuery.value.isNotEmpty) {
      chips.add(_chip(context,
          icon: Icons.search,
          label: 'Search: ${controller.searchQuery.value}',
          onDeleted: () {
            controller.searchQuery.value = '';
            controller.fetchPosUploads(clear: true);
          }));
    }
    if (f.containsKey('status')) {
      chips.add(_chip(context,
          icon: Icons.flag_outlined,
          label: 'Status: ${f['status']}',
          onDeleted: () => controller.removeFilter('status')));
    }
    if (f.containsKey('customer') && f['customer'].toString().isNotEmpty) {
      final match = controller.customers
          .firstWhereOrNull((c) => c.name == f['customer']);
      final display =
      match != null ? match.customerName : f['customer'].toString();
      chips.add(_chip(context,
          icon: Icons.person_outline,
          label: 'Customer: $display',
          onDeleted: () => controller.removeFilter('customer')));
    }
    if (f.containsKey('date')) {
      final dr = f['date'];
      if (dr is List && dr[0] == 'between' && dr[1] is List) {
        final dates = dr[1] as List;
        chips.add(_chip(context,
            icon: Icons.date_range,
            label: '${dates[0]}  →  ${dates[1]}',
            onDeleted: () => controller.removeFilter('date')));
      }
    }
    return chips;
  }

  Widget _chip(BuildContext context,
      {required IconData icon,
        required String label,
        required VoidCallback onDeleted}) {
    // Routes through the shared FilterChipWidget so chip styling stays uniform
    // across every list screen.
    return FilterChipWidget(icon: icon, label: label, onDeleted: onDeleted);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final navBarHeight = MediaQuery.of(context).padding.bottom;

    return AppShellScaffold(
      body: RefreshIndicator(
        onRefresh: () => controller.fetchPosUploads(clear: true),
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Unified header ─────────────────────────────────────────────────
            DocTypeListHeader(
              title: 'POS Upload',
              automaticallyImplyLeading: false,
              searchDoctype: 'POS Invoice',
              searchRoute: AppRoutes.POS_UPLOAD_FORM,
              searchQuery: controller.searchQuery,
              onSearchChanged: controller.onSearchChanged,
              onSearchClear: () {
                controller.searchQuery.value = '';
                controller.fetchPosUploads(clear: true);
              },
              activeFilters: controller.activeFilters,
              onFilterTap: _showFilterSheet,
              filterChipsBuilder: _buildActiveFilterChips,
              onClearAllFilters: controller.clearFilters,
            ),

            // ── Result count pill ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Obx(() {
                if (controller.isLoading.value &&
                    controller.posUploads.isEmpty) {
                  return const SizedBox.shrink();
                }
                return ResultCountPill(
                  count: controller.posUploads.length,
                  hasMore: controller.hasMore.value,
                  hasActiveFilters: controller.activeFilters.isNotEmpty ||
                      controller.searchQuery.value.isNotEmpty,
                  noun: 'upload',
                  icon: Icons.cloud_upload_outlined,
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
                final hasFilters = controller.activeFilters.isNotEmpty ||
                    controller.searchQuery.value.isNotEmpty;
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: ListEmptyState(
                    hasActiveFilters: hasFilters,
                    emptyIcon: Icons.cloud_upload_outlined,
                    emptyTitle: 'No POS Uploads',
                    emptyMessage: 'Pull to refresh or create a new upload.',
                    filteredTitle: 'No Matching Uploads',
                    filteredMessage: 'Try adjusting your filters.',
                    onClearFilters: controller.clearFilters,
                    onReload: () => controller.fetchPosUploads(clear: true),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= controller.posUploads.length) {
                      return ListEndFooter(
                        hasMore: controller.hasMore.value,
                        bottomPadding: navBarHeight,
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
              tooltip: 'New POS Upload',
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              child: const Icon(Icons.add),
            )
          : FloatingActionButton.extended(
              onPressed: () => Get.toNamed(AppRoutes.POS_UPLOAD_FORM,
                  arguments: {'name': '', 'mode': 'new'}),
              tooltip: 'New POS Upload',
              icon: const Icon(Icons.add),
              label: const Text('New POS Upload'),
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            )),
    );
  }
}
