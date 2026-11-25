import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/sales_order_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/filter_focus.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/header_choice_row.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/result_count_pill.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_strip.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_controller.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_logic.dart';
import 'package:multimax/app/modules/selling/sales_order/widgets/sales_order_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/selling/sales_order/widgets/so_progress_row.dart';

class SalesOrderScreen extends StatefulWidget {
  const SalesOrderScreen({super.key});

  @override
  State<SalesOrderScreen> createState() => _SalesOrderScreenState();
}

class _SalesOrderScreenState extends State<SalesOrderScreen> {
  final SalesOrderController controller = Get.find();
  final _scrollController = ScrollController();
  final _headerKey = GlobalKey();

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
        !controller.isLoading.value &&
        !controller.isFetchingMore.value) {
      controller.fetch(isLoadMore: true);
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    return _scrollController.offset >=
        _scrollController.position.maxScrollExtent * 0.9;
  }

  /// [focusKey] opens the sheet on that filter, ready to edit.
  void _showFilterSheet({String? focusKey}) {
    Get.bottomSheet(
      FilterFocusScope.wrap(const SalesOrderFilterBottomSheet(),
          focusKey: focusKey),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  List<Widget> _buildFilterChips(BuildContext context) {
    final chips = <Widget>[];
    final filters = controller.activeFilters;

    if (controller.searchQuery.value.isNotEmpty) {
      chips.add(FilterChipWidget(
        icon: Icons.search,
        label: 'Search: ${controller.searchQuery.value}',
        onDeleted: controller.clearSearch,
        onTap: () => editListSearch(
          context,
          doctype: 'Sales Order',
          targetRoute: AppRoutes.SALES_ORDER_FORM,
          searchQuery: controller.searchQuery,
          onSearchChanged: controller.onSearchChanged,
          onSearchClear: controller.clearSearch,
        ),
      ));
    }

    if (filters.containsKey('status')) {
      chips.add(FilterChipWidget(
        icon: Icons.flag_outlined,
        label: 'Status: ${statusFilterLabel(filters['status'])}',
        onDeleted: () => controller.removeFilter('status'),
        onTap: () => _showFilterSheet(focusKey: 'status'),
      ));
    }

    if (filters.containsKey('customer')) {
      chips.add(FilterChipWidget(
        icon: Icons.person_outline,
        label: 'Customer: ${filters['customer']}',
        onDeleted: () => controller.removeFilter('customer'),
        onTap: () => _showFilterSheet(focusKey: 'customer'),
      ));
    }

    if (filters.containsKey('delivery_date')) {
      final range = filters['delivery_date'];
      String label = 'Delivery';
      if (range is List && range.length == 2 && range[1] is List) {
        final bounds = range[1] as List;
        final from = bounds.isNotEmpty ? bounds[0]?.toString() ?? '' : '';
        final to = bounds.length > 1 ? bounds[1]?.toString() ?? '' : '';
        label = 'Delivery: ${from.isEmpty ? '…' : from} → ${to.isEmpty ? '…' : to}';
      } else if (range is List && range.length == 2) {
        label = 'Delivery: ${range[0]} ${range[1]}';
      }
      chips.add(FilterChipWidget(
        icon: Icons.event_outlined,
        label: label,
        onDeleted: () => controller.removeFilter('delivery_date'),
        onTap: () => _showFilterSheet(focusKey: 'delivery_date'),
      ));
    }

    if (filters.containsKey('owner')) {
      final owner = filters['owner']?.toString() ?? '';
      final match = controller.users.firstWhereOrNull((u) => u.email == owner);
      chips.add(FilterChipWidget(
        icon: Icons.person_search_outlined,
        label: 'Owner: ${match?.name ?? owner}',
        onDeleted: () => controller.removeFilter('owner'),
        onTap: () => _showFilterSheet(focusKey: 'owner'),
      ));
    }

    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppShellScaffold(
      floatingActionButtonHeaderKey: _headerKey,
      // No Obx here: DocTypeGuard is reactive internally, and an Obx whose
      // builder reads no observables throws GetX's improper-use error.
      floatingActionButton: DocTypeGuard(
        doctype: 'Sales Order',
        permType: 'create',
        child: FloatingActionButton.extended(
          onPressed: controller.openCreate,
          tooltip: 'New Sales Order',
          icon: const Icon(Icons.add),
          label: const Text('New Sales Order'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.fetch(clear: true),
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: Scrollbar(
          controller: _scrollController,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Unified header: AppBar + status chips + filter chips ──────
              DocTypeListHeader(
                sliverKey: _headerKey,
                title: 'Sales Order',
                automaticallyImplyLeading: false,
                searchDoctype: 'Sales Order',
                searchRoute: AppRoutes.SALES_ORDER_FORM,
                searchQuery: controller.searchQuery,
                onSearchChanged: controller.onSearchChanged,
                onSearchClear: controller.clearSearch,
                activeFilters: controller.activeFilters,
                onFilterTap: () => _showFilterSheet(),
                filterChipsBuilder: _buildFilterChips,
                onClearAllFilters: controller.clearFilters,
                measuredBottomBuilder: _buildQuickChips,
              ),

              // ── Result count pill ────────────────────────────────────────
              SliverToBoxAdapter(
                child: Obx(() {
                  if (controller.isLoading.value && controller.orders.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return ResultCountPill(
                    count: controller.orders.length,
                    hasMore: controller.hasMore.value,
                    hasActiveFilters: controller.activeFilters.isNotEmpty ||
                        controller.searchQuery.value.isNotEmpty,
                    noun: 'order',
                    icon: Icons.receipt_long_outlined,
                  );
                }),
              ),

              // ── List content ──────────────────────────────────────────────
              Obx(() {
                if (controller.isLoading.value && controller.orders.isEmpty) {
                  return const SliverToBoxAdapter(child: DocCardSkeletonList());
                }

                if (controller.orders.isEmpty) {
                  final hasFilters = controller.activeFilters.isNotEmpty ||
                      controller.searchQuery.value.isNotEmpty;
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: ListEmptyState(
                      hasActiveFilters: hasFilters,
                      emptyIcon: Icons.receipt_long_outlined,
                      emptyTitle: 'No Sales Orders',
                      emptyMessage: 'Pull to refresh or create a new one.',
                      filteredTitle: 'No Matching Orders',
                      filteredMessage:
                          'Try adjusting your filters or search query.',
                      onClearFilters: controller.clearFilters,
                      onReload: () => controller.fetch(clear: true),
                    ),
                  );
                }

                final baseCount = controller.orders.length;
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= baseCount) {
                        return ListEndFooter(hasMore: controller.hasMore.value);
                      }
                      return _buildCard(context, controller.orders[index]);
                    },
                    childCount: baseCount + 1,
                  ),
                );
              }),

              // ── Bottom padding for FAB + nav bar ─────────────────────────
              SliverToBoxAdapter(
                child: SizedBox(
                    height: MediaQuery.paddingOf(context).bottom + 80),
              ),
            ],
          ),
        ),
      ),
    );
  }

  HeaderChoiceRow _buildQuickChips(BuildContext _) {
    const scopes = {
      ActionableScope.mine: 'Mine',
      ActionableScope.everyone: 'Everyone',
    };
    final scope = controller.scope.value;
    final status = controller.activeFilters['status'];
    final busy = controller.isLoading.value;
    return HeaderChoiceRow(
      busy: busy,
      busyLabel: busy ? 'Loading sales orders' : null,
      options: [
        for (final entry in scopes.entries)
          HeaderChoiceOption(
            id: 'scope:${entry.key.name}',
            groupId: 'scope',
            label: entry.value,
            semanticLabel: 'Order scope, ${entry.value}',
            selected: entry.key == scope,
            onPressed: () => controller.setScope(entry.key),
          ),
        for (final label in SalesOrderController.statusChips)
          HeaderChoiceOption(
            id: 'status:$label',
            groupId: 'status',
            label: label,
            semanticLabel: 'Order status, $label',
            selected: label == status,
            selectedHint: 'Activate to clear status filter',
            onPressed: () => controller.setStatusChip(label),
          ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, SalesOrder so) {
    final currencySymbol = FormattingHelper.getCurrencySymbol(so.currency);
    final grandTotal = NumberFormat('#,##0.00').format(so.grandTotal);

    return GenericDocumentCard(
      title: so.name,
      subtitle: so.customerName.isNotEmpty ? so.customerName : so.customer,
      status: so.status,
      isExpanded: false,
      navigatesOnTap: true,
      onTap: () => controller.open(so),
      stats: [
        GenericDocumentCard.buildIconStat(
          context,
          Icons.calendar_today,
          FormattingHelper.getRelativeTime(so.transactionDate),
        ),
        if (shortDeliveryDate(so.deliveryDate) != null)
          GenericDocumentCard.buildIconStat(
            context,
            Icons.local_shipping_outlined,
            shortDeliveryDate(so.deliveryDate)!,
          ),
        GenericDocumentCard.buildIconStat(
          context,
          Icons.attach_money,
          '$currencySymbol $grandTotal',
        ),
      ],
      // `body` is full-width within the card (unlike `stats`, a Wrap row that
      // gives children unconstrained width — a LinearProgressIndicator there
      // would hit an infinite-width layout assertion).
      body: so.docstatus == 1
          ? SoProgressRow(perDelivered: so.perDelivered, perBilled: so.perBilled)
          : null,
    );
  }
}
