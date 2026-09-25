import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/landed_cost_voucher/landed_cost_voucher_controller.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';

class LandedCostVoucherScreen extends GetView<LandedCostVoucherController> {
  const LandedCostVoucherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShellScaffold(
      body: CustomScrollView(
        controller: controller.scrollController,
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
                      return ListEndFooter(hasMore: controller.hasMore.value);
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
                        onTap: () {
                          Get.toNamed(
                            AppRoutes.LANDED_COST_VOUCHER_FORM,
                            arguments: {'mode': 'edit', 'name': voucher.name},
                          );
                        },
                        stats: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 14,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                voucher.postingDate ?? '',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.attach_money,
                                size: 14,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                FormattingHelper.formatAmount(
                                  voucher.totalTaxesAndCharges ?? 0.0,
                                ),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
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
      floatingActionButton: Obx(() {
        return AnimatedScale(
          scale: controller.isFarFromTop.value ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: FloatingActionButton(
            onPressed: () {
              Get.toNamed(
                AppRoutes.LANDED_COST_VOUCHER_FORM,
                arguments: {'mode': 'new'},
              );
            },
            child: const Icon(Icons.add),
          ),
        );
      }),
    );
  }
}
