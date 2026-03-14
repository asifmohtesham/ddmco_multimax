import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/batch_controller.dart';
import 'package:multimax/app/modules/batch/widgets/batch_list_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:intl/intl.dart';

class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key});

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  late final BatchController controller;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    controller = Get.find<BatchController>();
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
      controller.fetchBatches(isLoadMore: true);
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    return _scrollController.offset >=
        _scrollController.position.maxScrollExtent * 0.9;
  }

  // ── build ──────────────────────────────────────────────────────────────────

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
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── DocTypeListAppBar (collapsing title + search) ─────────────────
            const BatchListAppBar(),

            // ── Content ──────────────────────────────────────────────────────
            Obx(() {
              if (controller.isLoading.value &&
                  controller.batches.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (controller.batches.isEmpty) {
                return _buildEmptyState(context, theme, colorScheme);
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
                    return _buildBatchCard(
                        context, controller.batches[index]);
                  },
                  childCount: controller.batches.length +
                      (controller.hasMore.value ? 1 : 0),
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

  // ── empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final hasSearch = controller.searchQuery.value.isNotEmpty;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                hasSearch
                    ? Icons.search_off_outlined
                    : Icons.qr_code_scanner_outlined,
                size: 64,
                color: colorScheme.outlineVariant,
              ),
              const SizedBox(height: 16),
              Text(
                hasSearch ? 'No Matching Batches' : 'No Batches Found',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasSearch
                    ? 'Try a different search term.'
                    : 'Pull to refresh or create a new batch.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              if (hasSearch)
                FilledButton.tonalIcon(
                  onPressed: () {
                    controller.searchQuery.value = '';
                    controller.fetchBatches(clear: true);
                  },
                  icon: const Icon(Icons.search_off),
                  label: const Text('Clear Search'),
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

  // ── batch card ──────────────────────────────────────────────────────────────

  Widget _buildBatchCard(BuildContext context, dynamic batch) {
    // Derive status from expiry date
    String status = 'Active';
    if (batch.expiryDate != null) {
      final expiry = DateTime.tryParse(batch.expiryDate!);
      if (expiry != null && expiry.isBefore(DateTime.now())) {
        status = 'Expired';
      }
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

  // ── expanded content ─────────────────────────────────────────────────────────

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

  // ── info row helper ──────────────────────────────────────────────────────────

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
