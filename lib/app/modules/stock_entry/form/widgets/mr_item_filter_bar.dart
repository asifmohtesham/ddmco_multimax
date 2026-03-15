import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

/// A row of three [FilterChip]s (All / Pending / Completed) that controls
/// [StockEntryFormController.mrItemFilter].
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

      return Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        child: Row(
          children: _filters.map((label) {
            final isSelected = active == label;

            Color selectedBg;
            Color selectedFg;
            switch (label) {
              case 'Pending':
                selectedBg = Colors.orange.shade100;
                selectedFg = Colors.orange.shade800;
                break;
              case 'Completed':
                selectedBg = Colors.green.shade100;
                selectedFg = Colors.green.shade800;
                break;
              default:
                selectedBg = Colors.blue.shade100;
                selectedFg = Colors.blue.shade800;
            }

            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: FilterChip(
                label: Text(label),
                selected: isSelected,
                onSelected: (_) => controller.mrItemFilter.value = label,
                selectedColor: selectedBg,
                labelStyle: TextStyle(
                  color: isSelected ? selectedFg : Colors.black87,
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
