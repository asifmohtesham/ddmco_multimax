import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/purchase_receipt/purchase_receipt_controller.dart';

/// Bottom sheet that lists submitted, non-closed Purchase Orders so the user
/// can pick one to create a new Purchase Receipt against.
///
/// Phase 4 Step 4.1: extracted from the inline DraggableScrollableSheet that
/// was previously built inside PurchaseReceiptController.openCreateDialog().
/// All state lives in [PurchaseReceiptController]; this widget is purely
/// presentational.
class PurchaseReceiptPoSelectionSheet extends StatelessWidget {
  const PurchaseReceiptPoSelectionSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PurchaseReceiptController>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28.0)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Drag handle ─────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.only(top: 16.0, bottom: 8.0),
                alignment: Alignment.center,
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Header row ──────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(20, 4, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Select Purchase Order',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Get.back(),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            colorScheme.surfaceContainerHigh,
                        foregroundColor:
                            colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Search field ─────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0),
                child: TextField(
                  onChanged: controller.filterPurchaseOrders,
                  decoration: InputDecoration(
                    hintText: 'Search by PO number or supplier…',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor:
                        colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ),

              const SizedBox(height: 12),
              Divider(
                  height: 1, color: colorScheme.outlineVariant),

              // ── List ─────────────────────────────────────────────────────
              Expanded(
                child: Obx(() {
                  if (controller.isFetchingPOs.value) {
                    return Center(
                      child: CircularProgressIndicator(
                          color: colorScheme.primary),
                    );
                  }

                  if (controller
                      .purchaseOrdersForSelection.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 56,
                              color: colorScheme.outlineVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No Purchase Orders Found',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No submitted, open POs match your search.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(
                                color:
                                    colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    controller: scrollController,
                    padding: EdgeInsets.only(
                      bottom:
                          MediaQuery.of(context).padding.bottom +
                              16,
                    ),
                    itemCount: controller
                        .purchaseOrdersForSelection.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 72,
                        endIndent: 16,
                        color: colorScheme.outlineVariant
                            .withValues(alpha: 0.5)),
                    itemBuilder: (context, index) {
                      final po = controller
                          .purchaseOrdersForSelection[index];
                      return ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 4),
                        leading: CircleAvatar(
                          backgroundColor:
                              colorScheme.primaryContainer,
                          foregroundColor:
                              colorScheme.onPrimaryContainer,
                          child: const Icon(
                              Icons.receipt_long_outlined,
                              size: 20),
                        ),
                        title: Text(
                          po.name,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          '${po.supplier} \u2022 ${po.transactionDate}',
                          style:
                              theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onTap: () {
                          Get.back();
                          controller
                              .initiatePurchaseReceiptCreation(
                                  po);
                        },
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}
