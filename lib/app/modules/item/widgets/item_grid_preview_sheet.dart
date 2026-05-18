import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/item/item_controller.dart';
import 'package:multimax/app/modules/item/widgets/item_expanded_content.dart';
import 'package:multimax/app/modules/item/widgets/item_image.dart';

/// Bottom-sheet preview shown when the user taps an item card in grid view.
///
/// Displays the item image, name, code, group, and a reactive stock-balance
/// section. Navigates to ITEM_FORM when the user taps "View Full Details".
class ItemGridPreviewSheet extends StatelessWidget {
  final Item item;

  const ItemGridPreviewSheet({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final ItemController controller = Get.find();
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    // Trigger stock fetch immediately when the sheet is built.
    // fetchStockLevels is idempotent — safe to call even if data is cached.
    controller.fetchStockLevels(item.itemCode);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header: image + item identity
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ItemImage(
                  key: ValueKey('preview_${item.itemCode}'),
                  imageUrl: item.image != null
                      ? '${controller.baseUrl}${item.image}'
                      : null,
                  size: 64,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.itemName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        item.itemCode,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      Text(
                        item.itemGroup,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.primary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 24),

          // Reactive stock-balance section
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: Obx(() {
              final stockList = controller.getStockFor(item.itemCode);
              final isLoading = controller.isStockLoading(item.itemCode);
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ItemExpandedContent(
                  item: item,
                  stockList: stockList,
                  isLoading: isLoading,
                  colorScheme: cs,
                  theme: theme,
                ),
              );
            }),
          ),

          // CTA — navigate to full detail form
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Get.back();
                  Get.toNamed(
                    AppRoutes.ITEM_FORM,
                    arguments: {'itemCode': item.itemCode},
                  );
                },
                child: const Text('View Full Details'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
