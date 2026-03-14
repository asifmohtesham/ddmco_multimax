import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
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
      controller.fetchDeliveryNotes(isLoadMore: true);
    }
    final far = _scrollController.hasClients && _scrollController.offset > 80;
    if (_isFarFromTop.value != far) _isFarFromTop.value = far;
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    return _scrollController.offset >=
        _scrollController.position.maxScrollExtent * 0.9;
  }

  void _showFilterBottomSheet() {
    Get.bottomSheet(
      const FilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  // ---------------------------------------------------------------------------
  // Active filter chips
  // ---------------------------------------------------------------------------
  List<Widget> _buildActiveFilterChips(BuildContext context) {
    final chips = <Widget>[];
    final f     = controller.activeFilters;

    if (controller.searchQuery.value.isNotEmpty) {
      chips.add(_chip(
        context,
        icon: Icons.search,
        label: 'Search: ${controller.searchQuery.value}',
        onDeleted: () {
          controller.searchQuery.value = '';
          controller.fetchDeliveryNotes(clear: true);
        },
      ));
    }

    if (f.containsKey('status')) {
      chips.add(_chip(context,
          icon: Icons.flag_outlined,
          label: 'Status: ${f['status']}',
          onDeleted: () => controller.removeFilter('status')));
    }

    if (f.containsKey('customer') && f['customer'].toString().isNotEmpty) {
      // customer is an exact name — resolve display label from loaded list
      final match = controller.customers
          .firstWhereOrNull((c) => c.name == f['customer']);
      final display = match != null ? match.customerName : f['customer'].toString();
      chips.add(_chip(context,
          icon: Icons.business_outlined,
          label: 'Customer: $display',
          onDeleted: () => controller.removeFilter('customer')));
    }

    if (f.containsKey('po_no')) {
      final val = f['po_no'];
      final display = val is List
          ? val[1].toString().replaceAll('%', '')
          : val.toString();
      chips.add(_chip(context,
          icon: Icons.tag,
          label: 'PO: $display',
          onDeleted: () => controller.removeFilter('po_no')));
    }

    if (f.containsKey('set_warehouse')) {
      chips.add(_chip(context,
          icon: Icons.warehouse_outlined,
          label: 'Warehouse: ${f['set_warehouse']}',
          onDeleted: () => controller.removeFilter('set_warehouse')));
    }

    if (f.containsKey('owner') && f['owner'].toString().isNotEmpty) {
      chips.add(_chip(context,
          icon: Icons.person_outline,
          label: 'Created By: ${f['owner']}',
          onDeleted: () => controller.removeFilter('owner')));
    }

    if (f.containsKey('modified_by') &&
        f['modified_by'].toString().isNotEmpty) {
      chips.add(_chip(context,
          icon: Icons.edit_outlined,
          label: 'Modified By: ${f['modified_by']}',
          onDeleted: () => controller.removeFilter('modified_by')));
    }

    if (f.containsKey('creation')) {
      final cr = f['creation'];
      if (cr is List &&
          cr.length >= 2 &&
          cr[0] == 'between' &&
          cr[1] is List &&
          (cr[1] as List).length >= 2) {
        final dates = cr[1] as List;
        chips.add(_chip(context,
            icon: Icons.date_range,
            label: '${dates[0]}  →  ${dates[1]}',
            onDeleted: () => controller.removeFilter('creation')));
      }
    }

    return chips;
  }

  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onDeleted,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 16, color: colorScheme.onSecondaryContainer),
      label: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
      backgroundColor: colorScheme.secondaryContainer,
      deleteIconColor: colorScheme.onSecondaryContainer,
      onDeleted: onDeleted,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme        = Theme.of(context);
    final colorScheme  = theme.colorScheme;
    final navBarHeight = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchDeliveryNotes(clear: true),
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── AppBar ─────────────────────────────────────────────────────
            const SliverAppBar.large(
              title: Text('Delivery Notes'),
            ),

            // ── Result count pill ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Obx(() {
                if (controller.isLoading.value &&
                    controller.deliveryNotes.isEmpty) {
                  return const SizedBox.shrink();
                }
                final count      = controller.deliveryNotes.length;
                final hasMore    = controller.hasMore.value;
                final hasFilters = controller.activeFilters.isNotEmpty ||
                    controller.searchQuery.value.isNotEmpty;
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
                            Icon(Icons.description_outlined,
                                size: 14,
                                color: colorScheme.onSecondaryContainer),
                            const SizedBox(width: 6),
                            Text(
                              hasMore
                                  ? '$count+ notes'
                                  : '$count note${count == 1 ? '' : 's'}',
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
                                      .withOpacity(0.7)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),

            // ── Search bar + filter button in trailing ─────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Obx(() {
                  final filterCount = controller.activeFilters.length;
                  return SearchBar(
                    hintText: 'Search ID, Customer...',
                    leading: const Icon(Icons.search),
                    onChanged: controller.onSearchChanged,
                    trailing: [
                      if (controller.searchQuery.value.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Clear search',
                          onPressed: () {
                            controller.searchQuery.value = '';
                            controller.fetchDeliveryNotes(clear: true);
                          },
                        ),
                      Tooltip(
                        message: filterCount > 0
                            ? '$filterCount filter${filterCount > 1 ? 's' : ''} active'
                            : 'Filter notes',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _showFilterBottomSheet,
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  filterCount > 0
                                      ? Icons.filter_alt
                                      : Icons.filter_list,
                                  color: filterCount > 0
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                ),
                                if (filterCount > 0)
                                  Positioned(
                                    top: -4,
                                    right: -6,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: colorScheme.error,
                                        shape: BoxShape.circle,
                                      ),
                                      constraints: const BoxConstraints(
                                          minWidth: 16, minHeight: 16),
                                      child: Text(
                                        '$filterCount',
                                        style: TextStyle(
                                          color: colorScheme.onError,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          height: 1.0,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    elevation: const WidgetStatePropertyAll(0),
                    backgroundColor: WidgetStatePropertyAll(
                        colorScheme.surfaceContainerHighest),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28)),
                    ),
                  );
                }),
              ),
            ),

            // ── Active filter chips ────────────────────────────────────────
            SliverToBoxAdapter(
              child: Obx(() {
                final hasFilters = controller.activeFilters.isNotEmpty;
                final hasSearch  = controller.searchQuery.value.isNotEmpty;
                if (!hasFilters && !hasSearch) return const SizedBox.shrink();
                final chips = _buildActiveFilterChips(context);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ...chips,
                      if (chips.length > 1)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.error,
                            visualDensity: VisualDensity.compact,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: controller.clearFilters,
                          icon: const Icon(Icons.clear_all, size: 16),
                          label: const Text('Clear all'),
                        ),
                    ],
                  ),
                );
              }),
            ),

            // ── List content ───────────────────────────────────────────────
            Obx(() {
              if (controller.isLoading.value &&
                  controller.deliveryNotes.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (controller.deliveryNotes.isEmpty) {
                final bool hasFilters =
                    controller.activeFilters.isNotEmpty ||
                        controller.searchQuery.value.isNotEmpty;

                String emptySubtitle;
                if (hasFilters) {
                  final parts = <String>[];
                  final af    = controller.activeFilters;
                  if (af.containsKey('status'))
                    parts.add('Status: ${af['status']}');
                  if (af.containsKey('customer')) {
                    final match = controller.customers
                        .firstWhereOrNull((c) => c.name == af['customer']);
                    final label = match != null
                        ? match.customerName
                        : af['customer'].toString();
                    parts.add('Customer: $label');
                  }
                  if (controller.searchQuery.value.isNotEmpty)
                    parts.add('Search: "${controller.searchQuery.value}"');
                  emptySubtitle = parts.isNotEmpty
                      ? 'No notes found for ${parts.join(' + ')}.'
                      : 'Try adjusting your filters or search query.';
                } else {
                  emptySubtitle = 'Pull to refresh or create a new one.';
                }

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
                                : Icons.description_outlined,
                            size: 64,
                            color: colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            hasFilters
                                ? 'No Matching Notes'
                                : 'No Delivery Notes',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            emptySubtitle,
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
                                  controller.fetchDeliveryNotes(clear: true),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reload'),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final showLoader = controller.hasMore.value;
              final baseCount  = controller.deliveryNotes.length;

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= baseCount) {
                      if (showLoader) {
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

                    final note = controller.deliveryNotes[index];

                    return Obx(() {
                      final isExpanded =
                          controller.expandedNoteName.value == note.name;
                      final isLoadingDetails =
                          controller.isLoadingDetails.value &&
                              controller.detailedNote?.name != note.name;

                      // ── Card layout — mirrors SE card exactly ──────────
                      // title:    PO number if present, else doc name
                      // subtitle: doc name • customer (mono font via GenericDocumentCard)
                      // stats row 1 (primary): qty | warehouse | posting date
                      // stats row 2 (audit):   owner | modifiedBy (if different)
                      final bool hasPo =
                          note.poNo != null && note.poNo!.isNotEmpty;
                      final String title =
                          hasPo ? note.poNo! : note.name;
                      final String subtitle = hasPo
                          ? '${note.name} • ${note.customer}'
                          : note.customer;

                      final showModified = note.modifiedBy != null &&
                          note.modifiedBy!.isNotEmpty &&
                          note.modifiedBy != note.owner &&
                          note.creation != note.modified;

                      return GenericDocumentCard(
                        title: title,
                        subtitle: subtitle,
                        status: note.status,
                        stats: [
                          GenericDocumentCard.buildIconStat(
                            context,
                            Icons.inventory_2_outlined,
                            '${note.totalQty.toStringAsFixed(0)} Items',
                          ),
                          if (note.setWarehouse != null &&
                              note.setWarehouse!.isNotEmpty)
                            GenericDocumentCard.buildIconStat(
                              context,
                              Icons.warehouse_outlined,
                              note.setWarehouse!,
                            ),
                          GenericDocumentCard.buildIconStat(
                            context,
                            Icons.calendar_today_outlined,
                            note.postingDate.isNotEmpty
                                ? note.postingDate
                                : FormattingHelper.getRelativeTime(
                                    note.creation),
                          ),
                        ],
                        auditStats: [
                          if (note.owner != null && note.owner!.isNotEmpty)
                            GenericDocumentCard.buildIconStat(
                              context,
                              Icons.person_add_alt_1_outlined,
                              note.owner!,
                            ),
                          if (showModified)
                            GenericDocumentCard.buildIconStat(
                              context,
                              Icons.edit_outlined,
                              note.modifiedBy!,
                            ),
                        ],
                        isExpanded: isExpanded,
                        isLoadingDetails: isLoadingDetails && isExpanded,
                        onTap: () => controller.toggleExpand(note.name),
                        expandedContent: isExpanded
                            ? _buildExpandedContent(context, note.name)
                            : null,
                      );
                    });
                  },
                  childCount: baseCount + 1,
                ),
              );
            }),
          ],
        ),
      ),
      floatingActionButton: Obx(() => _isFarFromTop.value
          ? FloatingActionButton(
              onPressed: controller.openCreateDialog,
              tooltip: 'Create Delivery Note',
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              elevation: 4,
              child: const Icon(Icons.add),
            )
          : FloatingActionButton.extended(
              onPressed: controller.openCreateDialog,
              icon: const Icon(Icons.add),
              label: const Text('Create'),
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              elevation: 4,
            )),
    );
  }

  // ---------------------------------------------------------------------------
  // Expanded card content — mirrors SE _buildDetailedContent exactly
  // ---------------------------------------------------------------------------
  Widget _buildExpandedContent(BuildContext context, String noteName) {
    return Obx(() {
      final detailed = controller.detailedNote;
      if (detailed == null || detailed.name != noteName) {
        return const SizedBox.shrink();
      }

      final theme       = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final currencySymbol =
          FormattingHelper.getCurrencySymbol(detailed.currency);
      final grandTotal =
          NumberFormat.decimalPatternDigits(decimalDigits: 2)
              .format(detailed.grandTotal);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Source warehouse full-width cell (only when set)
          if (detailed.setWarehouse != null &&
              detailed.setWarehouse!.isNotEmpty) ...[
            _infoCell(
              context,
              label: 'SOURCE WAREHOUSE',
              value: detailed.setWarehouse!,
              icon: Icons.warehouse_outlined,
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: colorScheme.outlineVariant),
            const SizedBox(height: 12),
          ],

          // Grand total
          if (detailed.grandTotal > 0) ...[
            _infoCell(
              context,
              label: 'GRAND TOTAL',
              value: '$currencySymbol $grandTotal',
              icon: Icons.payments_outlined,
              valueColor: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: colorScheme.outlineVariant),
            const SizedBox(height: 12),
          ],

          // Posting date + total qty side-by-side
          Row(
            children: [
              Expanded(
                child: _infoCell(
                  context,
                  label: 'POSTING DATE',
                  value: detailed.postingDate,
                  icon: Icons.calendar_today_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _infoCell(
                  context,
                  label: 'TOTAL QTY',
                  value: detailed.totalQty.toStringAsFixed(0),
                  icon: Icons.inventory_2_outlined,
                  alignRight: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Action button
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (detailed.status == 'Draft')
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(
                    AppRoutes.DELIVERY_NOTE_FORM,
                    arguments: {'name': detailed.name, 'mode': 'edit'},
                  ),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit'),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(
                    AppRoutes.DELIVERY_NOTE_FORM,
                    arguments: {'name': detailed.name, 'mode': 'view'},
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('View Details'),
                ),
            ],
          ),
        ],
      );
    });
  }

  // Mirrors SE _infoCell exactly.
  Widget _infoCell(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
    bool alignRight = false,
  }) {
    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment:
              alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!alignRight) ...[
              Icon(icon, size: 12, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
              ),
            ),
            if (alignRight) ...[
              const SizedBox(width: 4),
              Icon(icon, size: 12, color: colorScheme.onSurfaceVariant),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            color: valueColor ?? colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignRight ? TextAlign.end : TextAlign.start,
        ),
      ],
    );
  }
}
