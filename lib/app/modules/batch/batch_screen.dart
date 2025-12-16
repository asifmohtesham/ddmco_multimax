// app/modules/batch/batch_screen.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/batch/batch_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:intl/intl.dart'; // Added for DateFormat

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
            // M3 Large App Bar
            const SliverAppBar.large(
              title: Text('Batches'),
            ),

            // Search Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: TextField(
                  onChanged: controller.onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search Batch ID or Item...',
                    prefixIcon: Icon(Icons.search, color: colorScheme.onSurfaceVariant),
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

            // List Content
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

                    // Determine Status based on Expiry
                    String status = 'Active';
                    if (batch.expiryDate != null) {
                      final expiry = DateTime.tryParse(batch.expiryDate!);
                      if (expiry != null && expiry.isBefore(DateTime.now())) {
                        status = 'Expired';
                      }
                    }

                    return GenericDocumentCard(
                      title: batch.item,
                      subtitle: batch.name,
                      status: status,
                      isExpanded: false, // Fix: Required parameter
                      onTap: () => controller.openBatchForm(batch.name),
                      stats: [
                        if (batch.manufacturingDate != null)
                          GenericDocumentCard.buildIconStat(
                            context,
                            Icons.precision_manufacturing_outlined,
                            FormattingHelper.getRelativeTime(batch.manufacturingDate!), // Fix: Use DateFormat directly
                          ),
                        if (batch.expiryDate != null)
                          GenericDocumentCard.buildIconStat(
                            context,
                            Icons.event_busy_outlined,
                            FormattingHelper.getRelativeTime(batch.expiryDate!), // Fix: Use DateFormat directly
                          ),
                        GenericDocumentCard.buildIconStat(
                          context,
                          Icons.layers_outlined,
                          'Qty: ${batch.customPackagingQty}',
                        ),
                      ],
                    );
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
}