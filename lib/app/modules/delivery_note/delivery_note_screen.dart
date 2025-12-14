import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/delivery_note/delivery_note_controller.dart';
import 'package:multimax/app/modules/delivery_note/widgets/filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';

class DeliveryNoteScreen extends StatefulWidget {
  const DeliveryNoteScreen({super.key});

  @override
  State<DeliveryNoteScreen> createState() => _DeliveryNoteScreenState();
}

class _DeliveryNoteScreenState extends State<DeliveryNoteScreen> {
  final DeliveryNoteController controller = Get.find();
  final _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
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

  // Local search handler mapping to controller's filter logic
  void _onSearchChanged(String val) {
    // Debounce can be added here if needed
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_searchController.text == val) {
        final filters = Map<String, dynamic>.from(controller.activeFilters);
        if (val.isNotEmpty) {
          filters['name'] = ['like', '%$val%'];
        } else {
          filters.remove('name');
        }
        controller.applyFilters(filters);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          await controller.fetchDeliveryNotes(clear: true);
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // M3 Large App Bar
            SliverAppBar.large(
              title: const Text('Delivery Notes'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: () => _showFilterBottomSheet(context),
                ),
              ],
            ),

            // Search Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search ID...',
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
              if (controller.isLoading.value && controller.deliveryNotes.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (controller.deliveryNotes.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.description_outlined, size: 64, color: colorScheme.outlineVariant),
                          const SizedBox(height: 16),
                          Text(
                            'No delivery notes found',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: () => controller.fetchDeliveryNotes(clear: true),
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
                    if (index >= controller.deliveryNotes.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final note = controller.deliveryNotes[index];

                    return Obx(() {
                      final isExpanded = controller.expandedNoteName.value == note.name;
                      final isLoadingDetails = controller.isLoadingDetails.value && controller.detailedNote?.name != note.name;

                      // Logic to determine title/subtitle
                      final bool hasPo = note.poNo != null && note.poNo!.isNotEmpty;
                      final String title = hasPo ? note.poNo! : note.name;
                      final String subtitle = hasPo ? '${note.name} • ${note.customer}' : note.customer;

                      return GenericDocumentCard(
                        title: title,
                        subtitle: subtitle,
                        status: note.status,
                        isExpanded: isExpanded,
                        isLoadingDetails: isLoadingDetails && isExpanded,
                        onTap: () => controller.toggleExpand(note.name),
                        stats: [
                          GenericDocumentCard.buildIconStat(
                            context,
                            Icons.inventory_2_outlined,
                            '${note.totalQty.toStringAsFixed(0)} Items',
                          ),
                          GenericDocumentCard.buildIconStat(
                            context,
                            Icons.access_time,
                            FormattingHelper.getRelativeTime(note.creation),
                          ),
                          if (note.docstatus == 1) // Submitted
                            GenericDocumentCard.buildIconStat(
                              context,
                              Icons.timer_outlined,
                              FormattingHelper.getTimeTaken(note.creation, note.modified),
                            ),
                        ],
                        expandedContent: _buildExpandedContent(context, note),
                      );
                    });
                  },
                  childCount: controller.deliveryNotes.length + (controller.hasMore.value ? 1 : 0),
                ),
              );
            }),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: controller.openCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('Create'),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),
    );
  }

  Widget _buildExpandedContent(BuildContext context, DeliveryNote note) {
    return Obx(() {
      final detailed = controller.detailedNote;
      // Double check matches to avoid stale data display
      if (detailed == null || detailed.name != note.name) {
        return const SizedBox.shrink();
      }

      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final currencySymbol = FormattingHelper.getCurrencySymbol(detailed.currency);
      final grandTotal = NumberFormat('#,##0.00').format(detailed.grandTotal);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info Block (Warehouse)
          if (detailed.setWarehouse != null && detailed.setWarehouse!.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _buildDetailField(context, 'Source Warehouse', detailed.setWarehouse!),
            ),

          const SizedBox(height: 16),

          // Details Grid
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildDetailField(
                  context,
                  'Posting Date',
                  detailed.postingDate,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Grand Total', style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(
                      '$currencySymbol $grandTotal',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (detailed.status == 'Draft') ...[
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM, arguments: {'name': note.name, 'mode': 'edit'}),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit'),
                ),
              ] else ...[
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM, arguments: {'name': note.name, 'mode': 'view'}),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View Details'),
                ),
              ]
            ],
          ),
        ],
      );
    });
  }

  Widget _buildDetailField(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
      ],
    );
  }
}