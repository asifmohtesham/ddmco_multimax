import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/batch_controller.dart';
import 'package:multimax/app/modules/batch/widgets/batch_list_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:intl/intl.dart';

/// Batch list screen — fully GetX, zero [StatefulWidget].
///
/// [ScrollController] is owned by [BatchController] (created in [onInit],
/// disposed in [onClose]) so this screen needs no local state whatsoever.
class BatchScreen extends GetView<BatchController> {
  const BatchScreen({super.key});

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchBatches(clear: true),
        color: colorScheme.primary,
        child: CustomScrollView(
          controller: controller.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Collapsing header: AppBar + search + filter chips ──────────────
            const BatchListAppBar(),

            // ── List content ───────────────────────────────────────────────
            Obx(() {
              // Loading spinner — only while the first page is in-flight
              if (controller.isLoading.value &&
                  controller.batches.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              // Empty state
              if (controller.batches.isEmpty) {
                return _buildEmptyState(context, theme, colorScheme);
              }

              // Capture reactive values inside Obx before passing to
              // SliverChildBuilderDelegate (which is not itself reactive).
              final batchCount = controller.batches.length;
              final showLoader = controller.hasMore.value;

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= batchCount) {
                      // Pagination loader sentinel
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    return _buildBatchCard(
                        context, controller.batches[index]);
                  },
                  childCount: batchCount + (showLoader ? 1 : 0),
                ),
              );
            }),

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
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

  // ── Empty state ─────────────────────────────────────────────────────────

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    // searchQuery and activeFilters are already tracked by the parent Obx.
    final hasSearch = controller.searchQuery.value.isNotEmpty;
    final hasFilters = controller.activeFilters.isNotEmpty;
    final hasAnyFilter = hasSearch || hasFilters;

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                hasAnyFilter
                    ? Icons.filter_alt_off_outlined
                    : Icons.qr_code_scanner_outlined,
                size: 64,
                color: colorScheme.outlineVariant,
              ),
              const SizedBox(height: 16),
              Text(
                hasAnyFilter ? 'No Matching Batches' : 'No Batches Found',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasAnyFilter
                    ? 'Try adjusting your filters or search term.'
                    : 'Pull to refresh or create a new batch.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              if (hasAnyFilter)
                FilledButton.tonalIcon(
                  onPressed: controller.clearFilters,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear Filters'),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: () => controller.fetchBatches(clear: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Batch card ──────────────────────────────────────────────────────────

  Widget _buildBatchCard(BuildContext context, dynamic batch) {
    final String status;
    if (batch.expiryDate != null) {
      final expiry = DateTime.tryParse(batch.expiryDate!);
      status = (expiry != null && expiry.isBefore(DateTime.now()))
          ? 'Expired'
          : 'Active';
    } else {
      status = 'Active';
    }

    return Obx(() {
      final isExpanded =
          controller.expandedBatchName.value == batch.name;

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
              DateFormat('dd MMM yyyy')
                  .format(DateTime.parse(batch.manufacturingDate!)),
            ),
          if (batch.expiryDate != null)
            GenericDocumentCard.buildIconStat(
              context,
              Icons.event_busy_outlined,
              DateFormat('dd MMM yyyy')
                  .format(DateTime.parse(batch.expiryDate!)),
            ),
          GenericDocumentCard.buildIconStat(
            context,
            Icons.layers_outlined,
            'Qty: ${batch.customPackagingQty}',
          ),
        ],
        expandedContent:
            isExpanded ? _buildExpandedContent(context, batch) : null,
      );
    });
  }

  // ── Expanded content ─────────────────────────────────────────────────────

  Widget _buildExpandedContent(BuildContext context, dynamic batch) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow(
          context,
          'Purchase Order',
          batch.customPurchaseOrder ?? 'Not Linked',
          icon: Icons.receipt_long,
        ),
        const SizedBox(height: 12),

        Obx(() {
          final variant = controller.itemVariants[batch.item];
          final isLoading =
              controller.isLoadingDetails.value && variant == null;

          if (isLoading) {
            return Row(
              children: [
                Icon(Icons.style_outlined,
                    size: 16, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Loading Variant…',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colorScheme.outline),
                ),
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

  // ── Info row helper ──────────────────────────────────────────────────────

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value, {
    required IconData icon,
  }) {
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
              Text(
                label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              Text(
                value,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
