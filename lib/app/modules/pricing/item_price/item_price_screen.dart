import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/result_count_pill.dart';
import 'package:multimax/app/modules/pricing/item_price/item_price_controller.dart';
import 'package:multimax/app/modules/pricing/item_price/widgets/item_price_list_app_bar.dart';
import 'package:multimax/app/modules/pricing/widgets/item_price_row.dart';

/// Item Price list. Rows are navigational (`navigatesOnTap: true`).
class ItemPriceScreen extends GetView<ItemPriceController> {
  const ItemPriceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return AppShellScaffold(
      floatingActionButton: DocTypeGuard(
        doctype: 'Item Price',
        permType: 'create',
        child: FloatingActionButton.extended(
          onPressed: () => controller.openPrice(null),
          tooltip: 'New price',
          icon: const Icon(Icons.add),
          label: const Text('New price'),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
        ),
      ),
      body: RefreshIndicator(
        color: cs.primary,
        backgroundColor: cs.surfaceContainerHighest,
        onRefresh: () async {
          controller.loadPriceLists();
          await controller.fetchPrices();
        },
        child: Scrollbar(
          controller: controller.scrollController,
          child: CustomScrollView(
            controller: controller.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const ItemPriceListAppBar(),
              SliverToBoxAdapter(
                child: Obx(() => ResultCountPill(
                      count: controller.displayCount,
                      hasMore: controller.countHasMore,
                      hasActiveFilters: controller.hasActiveFilters,
                      noun: 'price',
                      icon: Icons.sell_outlined,
                    )),
              ),
              Obx(() {
                if (controller.isLoading.value && controller.prices.isEmpty) {
                  return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (controller.prices.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: ListEmptyState(
                      hasActiveFilters: controller.hasActiveFilters,
                      emptyIcon: Icons.sell_outlined,
                      emptyTitle: 'No item prices',
                      emptyMessage:
                          'Prices added here or by Delivery Notes appear in this list.',
                      filteredTitle: 'No matching prices',
                      filteredMessage: 'Try another price list, search or filter.',
                      onClearFilters: controller.clearFilters,
                      onReload: controller.fetchPrices,
                    ),
                  );
                }
                final count = controller.prices.length;
                final hasMore = controller.hasMore.value;
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      if (i == count) {
                        return ListEndFooter(
                            hasMore: hasMore, bottomPadding: bottomInset + 80);
                      }
                      final p = controller.prices[i];
                      return ItemPriceRow(
                        key: ValueKey(p.name),
                        price: p,
                        onTap: () => controller.openPrice(p),
                      );
                    },
                    childCount: count + 1,
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
