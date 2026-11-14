import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/landed_cost_voucher/landed_cost_voucher_controller.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';

/// List of Landed Cost Vouchers. Users with create permission get a FAB; tapping a card opens it (drafts are editable).
class LandedCostVoucherScreen extends GetView<LandedCostVoucherController> {
  const LandedCostVoucherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final navBarHeight = MediaQuery.of(context).padding.bottom;

    return AppShellScaffold(
      floatingActionButton: DocTypeGuard(
        doctype: 'Landed Cost Voucher',
        permType: 'create',
        child: FloatingActionButton.extended(
          onPressed: controller.openCreateForm,
          tooltip: 'New Landed Cost Voucher',
          icon: const Icon(Icons.add),
          label: const Text('New Voucher'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchLandedCostVouchers(clear: true),
        child: Scrollbar(
          controller: controller.scrollController,
          child: CustomScrollView(
            controller: controller.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              DocTypeListHeader(title: 'Landed Cost Vouchers'),
              Obx(() {
                if (controller.isLoading.value && controller.vouchers.isEmpty) {
                  return SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => const DocCardSkeleton(),
                        childCount: 5,
                      ),
                    ),
                  );
                }

                if (controller.vouchers.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: ListEmptyState(
                      hasActiveFilters: controller.activeFilters.isNotEmpty,
                      emptyIcon: Icons.receipt_long,
                      emptyTitle: 'No Landed Cost Vouchers',
                      emptyMessage: 'No vouchers found matching your criteria.',
                      filteredTitle: 'No matches found',
                      filteredMessage: 'Try adjusting your filters.',
                      onClearFilters: controller.clearFilters,
                      onReload: () =>
                          controller.fetchLandedCostVouchers(clear: true),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index == controller.vouchers.length) {
                          return ListEndFooter(
                            hasMore: controller.hasMore.value,
                            bottomPadding: navBarHeight,
                          );
                        }

                        final voucher = controller.vouchers[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GenericDocumentCard(
                            title: voucher.name,
                            subtitle: voucher.company,
                            status: voucher.docstatus == 1
                                ? 'Submitted'
                                : voucher.docstatus == 2
                                    ? 'Cancelled'
                                    : 'Draft',
                            isExpanded: false,
                            onTap: () => controller.openVoucher(voucher.name),
                            stats: [
                              GenericDocumentCard.buildIconStat(
                                context,
                                Icons.calendar_today,
                                voucher.postingDate,
                              ),
                              GenericDocumentCard.buildIconStat(
                                context,
                                Icons.attach_money,
                                FormattingHelper.formatAmount(
                                  voucher.totalTaxesAndCharges,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: controller.vouchers.length + 1,
                    ),
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
