import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/bom/reports/bom_search/bom_search_controller.dart';

/// Filter bottom sheet for BOM Search.
///
/// Exposes Item Code 1–5 only:
///   • Item Code 1 (index 0) — required, drives [BomSearchController.canRun].
///   • Item Code 2–5 (index 1–4) — optional sub-assembly filters.
///
/// Scan behaviour (hardware key → DataWedgeService → controller):
///   The controller’s _scanWorker fills the first empty slot automatically.
///   [isScanning] shows a spinner in the sheet header while resolution is in
///   progress so the user has visual feedback.
///
/// BOM No is intentionally absent — removed per product decision.
class BomSearchFilterSheet extends GetView<BomSearchController> {
  const BomSearchFilterSheet({super.key});

  /// Opens the sheet as a modal bottom sheet.
  static Future<void> show() => Get.bottomSheet(
        const BomSearchFilterSheet(),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        // Keep the sheet alive while scanning so the spinner stays visible.
        ignoreSafeArea: false,
      );

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize:     0.45,
      maxChildSize:     0.92,
      expand:           false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color:        cs.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        // Lift content above soft keyboard.
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Drag handle ──────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color:        cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Header row ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
              child: Row(
                children: [
                  Icon(Icons.account_tree_outlined,
                      color: cs.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'BOM Search Filters',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  // Scan-in-progress spinner
                  Obx(() => controller.isScanning.value
                      ? Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width:  18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary,
                            ),
                          ),
                        )
                      : const SizedBox.shrink()),
                  IconButton(
                    icon:      const Icon(Icons.close),
                    tooltip:   'Close',
                    onPressed: Get.back,
                  ),
                ],
              ),
            ),

            // Sub-title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
              child: Text(
                'Item Code 1 is required. '
                'Scan a barcode or type to fill each slot. '
                'The report runs automatically after each successful scan.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),

            const Divider(height: 1),

            // ── Item Code 1–5 fields ────────────────────────────────
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding:
                    const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  for (int i = 0; i < 5; i++) ...[
                    _ItemCodeField(index: i),
                    if (i < 4) const SizedBox(height: 12),
                  ],

                  const SizedBox(height: 28),

                  // ── Action row ─────────────────────────────────
                  Obx(() {
                    final enabled = controller.canRun.value &&
                        !controller.isLoading.value;
                    return Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: enabled
                                ? () async {
                                    await controller.runReport();
                                    Get.back();
                                  }
                                : null,
                            icon: controller.isLoading.value
                                ? const SizedBox(
                                    width:  16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.search),
                            label: Text(
                              controller.isLoading.value
                                  ? 'Searching…'
                                  : 'Apply & Run',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: controller.clearAll,
                          icon:  const Icon(Icons.clear_all),
                          label: const Text('Clear All'),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Single Item Code field widget ─────────────────────────────────────────

class _ItemCodeField extends GetView<BomSearchController> {
  final int index;
  const _ItemCodeField({required this.index});

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final ctrl    = controller.subAssemblyControllers[index];
    final isSlot1 = index == 0;

    return TextFormField(
      controller:      ctrl,
      textInputAction: index < 4
          ? TextInputAction.next
          : TextInputAction.done,
      decoration: InputDecoration(
        labelText: isSlot1
            ? 'Item Code 1 *'   // required
            : 'Item Code ${index + 1}',
        hintText:   'Scan or type item code',
        prefixIcon: Icon(
          isSlot1
              ? Icons.category_outlined
              : Icons.qr_code_scanner_outlined,
          color: isSlot1
              ? cs.primary.withValues(alpha: 0.85)
              : cs.primary.withValues(alpha: 0.6),
        ),
        // Inline clear button
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: ctrl,
          builder: (_, val, __) => val.text.isNotEmpty
              ? IconButton(
                  icon:    const Icon(Icons.clear, size: 18),
                  tooltip: 'Clear',
                  onPressed: () {
                    ctrl.clear();
                    // Re-run report if Item Code 1 is still set
                    // (clearing a slot 2-5 should refresh results).
                    if (controller.canRun.value) {
                      controller.runReport();
                    }
                  },
                )
              : const SizedBox.shrink(),
        ),
        border:         const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 12),
        // Visually distinguish Item Code 1 as required
        enabledBorder: isSlot1
            ? OutlineInputBorder(
                borderSide: BorderSide(
                  color: cs.primary.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              )
            : null,
        focusedBorder: isSlot1
            ? OutlineInputBorder(
                borderSide: BorderSide(
                  color: cs.primary,
                  width: 2,
                ),
              )
            : null,
      ),
      onFieldSubmitted: (_) {
        if (index < 4) {
          FocusScope.of(context).nextFocus();
        } else {
          // Last field — run & close
          if (controller.canRun.value) {
            controller.runReport().then((_) => Get.back());
          }
        }
      },
    );
  }
}
