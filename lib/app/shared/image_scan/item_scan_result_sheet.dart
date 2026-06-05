// lib/app/shared/image_scan/item_scan_result_sheet.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/shared/image_scan/image_scan_controller.dart';
import 'package:multimax/app/shared/image_scan/image_scan_result.dart';

/// Bottom panel shown inside the scan dialog when an Item or Batch has been
/// resolved. Slides up from the bottom of the Stack — not a separate route.
class ItemScanResultSheet extends StatelessWidget {
  final ImageScanController controller;
  final String imagePath;

  const ItemScanResultSheet({
    super.key,
    required this.controller,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() => _build(context, controller.scanState.value));
  }

  Widget _build(BuildContext context, ImageScanState state) {
    if (state == ImageScanState.notFound) return _notFoundPanel(context);
    if (state == ImageScanState.found) return _foundPanel(context);
    return const SizedBox.shrink();
  }

  // ── Not-found panel ─────────────────────────────────────────────────────────

  Widget _notFoundPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return _panel(
      cs: cs,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.search_off, color: cs.error, size: 28),
          const SizedBox(height: 8),
          Text('No item found',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: cs.onSurface, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('No matching Item in ERPNext.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Dismiss'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Found panel ─────────────────────────────────────────────────────────────

  Widget _foundPanel(BuildContext context) {
    return Obx(() {
      final cs = Theme.of(context).colorScheme;
      final theme = Theme.of(context);
      final itemCode = controller.foundItemCode.value!;
      final itemName = controller.foundItemName.value ?? itemCode;
      final itemGroup = controller.foundItemGroup.value ?? '';
      final hasImage = controller.foundItemHasImage.value;
      final batchNo = controller.foundBatchNo.value;
      final isEnriching = controller.isEnriching.value;

      return _panel(
        cs: cs,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: cs.primary, size: 20),
                const SizedBox(width: 6),
                Text('Item Found',
                    style: theme.textTheme.titleSmall?.copyWith(
                        color: cs.primary, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),

            // ── Item name ────────────────────────────────────────────────
            Text(itemName,
                style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onSurface, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),

            // ── Item code pill ───────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(itemCode,
                  style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: cs.onSecondaryContainer)),
            ),

            // ── Item group ───────────────────────────────────────────────
            if (itemGroup.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(itemGroup,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ],

            // ── Batch context ────────────────────────────────────────────
            if (batchNo != null) ...[
              const SizedBox(height: 4),
              Text('Batch: $batchNo',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic)),
            ],

            // ── Enrichment row (only when item has no image) ─────────────
            if (!hasImage) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        color: cs.onTertiaryContainer, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Save this image as the item photo?',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onTertiaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // ── Actions ──────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isEnriching
                        ? null
                        : () => Navigator.of(context)
                            .pop(controller.buildResult()),
                    child: const Text('Open'),
                  ),
                ),
                if (!hasImage) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: isEnriching
                          ? null
                          : () => _saveAndOpen(context),
                      child: isEnriching
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))
                          : const Text('Save & Open'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    });
  }

  Future<void> _saveAndOpen(BuildContext context) async {
    final ImageScanResult? result = await controller.enrichAndComplete(imagePath);
    if (!context.mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result);
    } else {
      GlobalSnackbar.error(
          message:
              'Could not save image. Tap "Open" to continue without saving.');
    }
  }

  // ── Shared panel shell ──────────────────────────────────────────────────────

  Widget _panel({required ColorScheme cs, required Widget child}) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 16)
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: child,
      ),
    );
  }
}
