import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

/// A row of three [FilterChip]s (All / Pending / Completed) that controls
/// [StockEntryFormController.mrItemFilter].
///
/// Each chip label shows the live count of item-codes that fall into that
/// category, e.g. "All (12)", "Pending (5)", "Completed (7)".
///
/// Rendered only when the Stock Entry is linked to a Material Request
/// (i.e. [StockEntryFormController.isMaterialRequestEntry] is true).
class MrItemFilterBar extends StatelessWidget {
  const MrItemFilterBar({super.key});

  static const _filters = ['All', 'Pending', 'Completed'];

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<StockEntryFormController>();

    return Obx(() {
      final active = controller.mrItemFilter.value;

      // Derive counts from mrReferenceItems merged with current entry items.
      // mrFilteredItems already does the merge; we just ask for each category.
      final allRows = controller.mrAllItems;
      final int countAll = allRows.length;
      final int countPending = allRows.where((r) => r.isPending).length;
      final int countCompleted = allRows.where((r) => r.isCompleted).length;

      int _countFor(String filter) {
        switch (filter) {
          case 'Pending':
            return countPending;
          case 'Completed':
            return countCompleted;
          default:
            return countAll;
        }
      }

      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        child: Row(
          children: _filters.map((label) {
            final isSelected = active == label;
            final count = _countFor(label);

            // Status-pill convention: tinted fill + x700 (light) / x300
            // (dark) ink, readable on both themes.
            Color base;
            switch (label) {
              case 'Pending':
                base = AppColors.orange500;
                break;
              case 'Completed':
                base = AppColors.green500;
                break;
              default:
                base = AppColors.blue500;
            }
            final selectedBg = base.withValues(alpha: 0.2);
            Color selectedFg;
            switch (label) {
              case 'Pending':
                selectedFg =
                    isDark ? AppColors.orange300 : AppColors.orange700;
                break;
              case 'Completed':
                selectedFg =
                    isDark ? AppColors.green300 : AppColors.green700;
                break;
              default:
                selectedFg = isDark ? AppColors.blue300 : AppColors.blue700;
            }

            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: FilterChip(
                label: Text('$label ($count)'),
                selected: isSelected,
                onSelected: (_) => controller.mrItemFilter.value = label,
                selectedColor: selectedBg,
                labelStyle: TextStyle(
                  color: isSelected
                      ? selectedFg
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
                checkmarkColor: selectedFg,
                showCheckmark: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                visualDensity: VisualDensity.compact,
              ),
            );
          }).toList(),
        ),
      );
    });
  }
}
