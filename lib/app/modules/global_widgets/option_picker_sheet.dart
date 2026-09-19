import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/widgets/sheet_status_bar_gap.dart';

/// Single-choice bottom sheet: title + close, one row per option, a check on
/// [selected]. Extracted from the ToDo form so the pricing forms reuse it.
void showOptionPickerSheet(
  BuildContext context, {
  required String title,
  required List<String> options,
  required String selected,
  required ValueChanged<String> onSelected,
}) {
  Get.bottomSheet(
    // Uncapped: one row per option, so a long list would run under the status
    // bar. Callers that nest the shell in a DraggableScrollableSheet are
    // already capped and must not add this.
    SheetStatusBarGap(
      child: SafeArea(
        child: OptionPickerSheetShell(
          title: title,
          mainAxisSize: MainAxisSize.min,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in options)
                ListTile(
                  title: Text(option),
                  trailing: option == selected ? const Icon(Icons.check) : null,
                  onTap: () {
                    Navigator.of(context).pop();
                    onSelected(option);
                  },
                ),
            ],
          ),
        ),
      ),
    ),
    isScrollControlled: true,
  );
}

/// Rounded surface sheet chrome with a title row and close button.
class OptionPickerSheetShell extends StatelessWidget {
  final String title;
  final Widget child;
  final MainAxisSize mainAxisSize;

  const OptionPickerSheetShell({
    super.key,
    required this.title,
    required this.child,
    this.mainAxisSize = MainAxisSize.max,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      child: Column(
        mainAxisSize: mainAxisSize,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
