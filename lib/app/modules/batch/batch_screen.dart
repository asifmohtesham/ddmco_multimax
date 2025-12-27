import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/batch_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:intl/intl.dart';

class BatchScreen extends GetView<BatchController> {
  const BatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final scrollController = ScrollController();

    scrollController.addListener(() {
      if (scrollController.position.pixels >= scrollController.position.maxScrollExtent * 0.9 &&
          controller.hasMore.value &&
          !controller.isFetchingMore.value) {
        controller.fetchBatches(isLoadMore: true);
      }
    });

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchBatches(clear: true),
        color: colorScheme.primary,
        child: CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: const Text('Batch'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Global Search',
                  onPressed: () {
                    showSearch(
                      context: context,
                      delegate: GlobalSearchDelegate(
                        doctype: 'Batch',
                        targetRoute: AppRoutes.BATCH_FORM,
                      ),
                    );
                  },
                ),
              ],
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: TextField(
                  onChanged: controller.onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Filter List...',
                    prefixIcon: Icon(Icons.filter_list, color: colorScheme.onSurfaceVariant),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  ),
                ),
              ),
            ),

            Obx(() {
              if (controller.isLoading.value && controller.batches.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (controller.batches.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_scanner, size: 64, color: colorScheme.outlineVariant),
                        const SizedBox(height: 16),
                        Text(
                          'No Batches Found',
                          style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: () => controller.fetchBatches(clear: true),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reload'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    if (index >= controller.batches.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final batch = controller.batches[index];

                    // Determine Status
                    String status = 'Active';
                    if (batch.expiryDate != null) {
                      final expiry = DateTime.tryParse(batch.expiryDate!);
                      if (expiry != null && expiry.isBefore(DateTime.now())) {
                        status = 'Expired';
                      }
                    }

                    return Obx(() {
                      final isExpanded = controller.expandedBatchName.value == batch.name;

                      return GenericDocumentCard(
                        title: batch.item,
                        subtitle: batch.name,
                        status: status,
                        isExpanded: isExpanded,
                        onTap: () => controller.toggleExpand(batch.name),
                        stats: [
                          if (batch.manufacturingDate != null)
                            GenericDocumentCard.buildIconStat(
                              context,
                              Icons.precision_manufacturing_outlined,
                              DateFormat('dd MMM yyyy').format(DateTime.parse(batch.manufacturingDate!)),
                            ),
                          if (batch.expiryDate != null)
                            GenericDocumentCard.buildIconStat(
                              context,
                              Icons.event_busy_outlined,
                              DateFormat('dd MMM yyyy').format(DateTime.parse(batch.expiryDate!)),
                            ),
                          GenericDocumentCard.buildIconStat(
                            context,
                            Icons.layers_outlined,
                            'Qty: ${batch.customPackagingQty}',
                          ),
                        ],
                        expandedContent: isExpanded ? _buildExpandedContent(context, batch) : null,
                      );
                    });
                  },
                  childCount: controller.batches.length + (controller.hasMore.value ? 1 : 0),
                ),
              );
            }),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => controller.openBatchForm(null),
        icon: const Icon(Icons.add),
        label: const Text('New Batch'),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),
    );
  }

  Widget _buildExpandedContent(BuildContext context, dynamic batch) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),

        // Purchase Order Field
        _buildInfoRow(
          context,
          'Purchase Order',
          batch.purchaseOrder ?? 'Not Linked',
          icon: Icons.receipt_long,
        ),

        const SizedBox(height: 12),

        // Variant Of Field
        Obx(() {
          final variant = controller.itemVariants[batch.item];
          final isLoading = controller.isLoadingDetails.value && variant == null;

          if (isLoading) {
            return Row(
              children: [
                Icon(Icons.style_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text('Loading Variant...', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.outline)),
              ],
            );
          }

          return _buildInfoRow(
            context,
            'Variant Of',
            variant ?? 'N/A',
            icon: Icons.style_outlined,
          );
        }),

        const SizedBox(height: 16),

        // Actions
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => controller.openBatchForm(batch.name),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit Details'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value, {required IconData icon}) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}