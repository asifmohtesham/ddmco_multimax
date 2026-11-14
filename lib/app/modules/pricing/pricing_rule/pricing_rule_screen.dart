import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/result_count_pill.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/pricing_rule_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/widgets/pricing_rule_list_app_bar.dart';
import 'package:multimax/app/modules/pricing/widgets/pricing_rule_row.dart';

/// Pricing Rule list. Rows are navigational (`navigatesOnTap: true`).
class PricingRuleScreen extends GetView<PricingRuleController> {
  const PricingRuleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return AppShellScaffold(
      floatingActionButton: DocTypeGuard(
        doctype: 'Pricing Rule',
        permType: 'create',
        child: FloatingActionButton.extended(
          onPressed: () => controller.openRule(null),
          tooltip: 'New rule',
          icon: const Icon(Icons.add),
          label: const Text('New rule'),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
        ),
      ),
      body: RefreshIndicator(
        color: cs.primary,
        backgroundColor: cs.surfaceContainerHighest,
        onRefresh: () async {
          controller.loadCounts();
          await controller.fetchRules();
        },
        child: Scrollbar(
          controller: controller.scrollController,
          child: CustomScrollView(
            controller: controller.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const PricingRuleListAppBar(),
              SliverToBoxAdapter(
                child: Obx(() => ResultCountPill(
                      count: controller.rules.length,
                      hasMore: controller.hasMore.value,
                      hasActiveFilters: controller.hasActiveFilters,
                      noun: 'rule',
                      icon: Icons.percent,
                    )),
              ),
              Obx(() {
                if (controller.isLoading.value && controller.rules.isEmpty) {
                  return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (controller.rules.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: ListEmptyState(
                      hasActiveFilters: controller.hasActiveFilters,
                      emptyIcon: Icons.percent,
                      emptyTitle: 'No pricing rules yet',
                      emptyMessage:
                          'Rules apply special rates or discounts automatically on Delivery Notes.',
                      filteredTitle: 'No matching rules',
                      filteredMessage: 'Try another status, side or search.',
                      onClearFilters: controller.clearFilters,
                      onReload: controller.fetchRules,
                      emptyAction: DocTypeGuard(
                        doctype: 'Pricing Rule',
                        permType: 'create',
                        child: FilledButton.icon(
                          onPressed: () => controller.openRule(null),
                          icon: const Icon(Icons.add),
                          label: const Text('New pricing rule'),
                        ),
                      ),
                    ),
                  );
                }
                final count = controller.rules.length;
                final hasMore = controller.hasMore.value;
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      if (i == count) {
                        return ListEndFooter(
                            hasMore: hasMore, bottomPadding: bottomInset + 80);
                      }
                      final r = controller.rules[i];
                      return PricingRuleRow(
                        key: ValueKey(r.name),
                        rule: r,
                        onTap: () => controller.openRule(r),
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
