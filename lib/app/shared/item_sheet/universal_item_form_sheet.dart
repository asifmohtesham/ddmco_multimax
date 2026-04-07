import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';

// Re-export the shared widget barrel so callers only need one import.
export 'package:multimax/app/shared/item_sheet/widgets/item_sheet_widgets.dart';

/// A universally-reusable bottom-sheet wrapper for item-level edit forms.
///
/// The sheet is presented via [Get.bottomSheet] with
/// [isScrollControlled: true] and wraps its content in a
/// [DraggableScrollableSheet].
///
/// Commit 2 addition:
///   The [DraggableScrollableSheet] builder captures its [BuildContext] and
///   writes it to [controller.sheetContext] before rendering children.  This
///   gives controller code a scoped, reliable context for
///   [Navigator.of(sheetContext).pop()] instead of [Get.back()], which can
///   target the wrong route when called from a controller.
class UniversalItemFormSheet extends StatelessWidget {
  const UniversalItemFormSheet({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.onSubmit,
    this.onScan,
    this.itemSubtext,
    this.isSaveEnabled = true,
    this.customFields = const [],
  });

  final ItemSheetControllerBase controller;
  final ScrollController scrollController;
  final Future<void> Function() onSubmit;
  final VoidCallback? onScan;
  final String? itemSubtext;
  final bool isSaveEnabled;
  final List<Widget> customFields;

  @override
  Widget build(BuildContext context) {
    // Commit 2: capture the sheet's own BuildContext so controllers can
    // pop the sheet via Navigator.of(sheetContext) instead of Get.back().
    controller.sheetContext = context;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                if (itemSubtext != null && itemSubtext!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      itemSubtext!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                    ),
                  ),
                ...customFields,
                const SizedBox(height: 16),
                if (isSaveEnabled)
                  Obx(() => ElevatedButton(
                        onPressed: controller.isSheetValid.value
                            ? () async {
                                try {
                                  await onSubmit();
                                } catch (e) {
                                  debugPrint('[UniversalItemFormSheet] onSubmit error: $e');
                                }
                              }
                            : null,
                        child: const Text('Save'),
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
