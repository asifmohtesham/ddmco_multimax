import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/info_block.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'bom_form_controller.dart';
import 'widgets/bom_items_tab.dart';
import 'widgets/bom_exploded_items_tab.dart';
import 'widgets/bom_costing_tab.dart';

class BomFormScreen extends GetView<BomFormController> {
  const BomFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (controller.isDirty.value) {
          await controller.confirmDiscard();
        } else {
          Get.back();
        }
      },
      child: Obx(() {
        final bom = controller.bom.value;
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: MainAppBar(
              title: bom?.name ?? controller.bomName,
              status: bom?.status,
              actions: [
                // ── Create Work Order action ──
                Obx(() => bom != null
                    ? IconButton(
                        icon: const Icon(
                            Icons.precision_manufacturing_outlined),
                        tooltip: 'Create Work Order',
                        onPressed: controller.createWorkOrder,
                      )
                    : const SizedBox.shrink()),
                // ── Save (toggle changes only) ──
                Obx(() => SaveIconButton(
                      onPressed:  controller.save,
                      isSaving:   controller.isSaving.value,
                      isDirty:    controller.isDirty.value,
                      saveResult: controller.saveResult.value,
                      tooltip:    'Save toggle changes',
                    )),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Items'),
                  Tab(text: 'Exploded Items'),
                  Tab(text: 'Costing'),
                ],
              ),
            ),
            body: controller.isLoading.value
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      _BomHeaderCard(controller: controller),
                      Expanded(
                        child: TabBarView(
                          children: [
                            BomItemsTab(items: bom?.items ?? []),
                            BomExplodedItemsTab(
                                items: bom?.explodedItems ?? []),
                            bom != null
                                ? BomCostingTab(bom: bom)
                                : const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        );
      }),
    );
  }
}

// ── Header summary card ────────────────────────────────────────────────────────────────

class _BomHeaderCard extends StatelessWidget {
  final BomFormController controller;
  const _BomHeaderCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Obx(() {
      final bom = controller.bom.value;
      if (bom == null) return const SizedBox.shrink();

      return Container(
        color: cs.surface,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Item code + name row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bom.item,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((bom.itemName ?? '').isNotEmpty)
                        Text(
                          bom.itemName!,
                          style: text.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                StatusPill(status: bom.status),
              ],
            ),
            const SizedBox(height: 10),

            // Info row: Qty | Currency | Item count
            Row(
              children: [
                Expanded(
                  child: InfoBlock(
                    label: 'Quantity',
                    // uom is String? — null-coalesce
                    value: '${_fmtQty(bom.quantity)} ${bom.uom ?? ''}',
                    icon: Icons.numbers_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InfoBlock(
                    label: 'Currency',
                    // currency is String? — null-coalesce before isNotEmpty
                    value: (bom.currency?.isNotEmpty ?? false)
                        ? bom.currency!
                        : '-',
                    icon: Icons.currency_exchange_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InfoBlock(
                    label: 'Items',
                    value: '${bom.items.length}',
                    icon: Icons.list_alt_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Toggle row: Active | Default
            Row(
              children: [
                Expanded(
                  child: Obx(() => _ToggleTile(
                        label: 'Active',
                        value: controller.isActive.value,
                        onChanged: (_) => controller.toggleActive(),
                        colorScheme: cs,
                      )),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Obx(() => _ToggleTile(
                        label: 'Default',
                        value: controller.isDefault.value,
                        onChanged: (_) => controller.toggleDefault(),
                        colorScheme: cs,
                      )),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  static String _fmtQty(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(3);
}

// ── Toggle tile ───────────────────────────────────────────────────────────────────────

class _ToggleTile extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final ColorScheme colorScheme;
  const _ToggleTile({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: value
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: value
                ? colorScheme.primary.withValues(alpha: 0.4)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: value
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeColor: colorScheme.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}
