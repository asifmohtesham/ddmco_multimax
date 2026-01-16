import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/widgets/frappe_form_layout.dart';
import 'package:multimax/widgets/generic_frappe_form.dart'; // Import Generic Form

class StockEntryFormScreen extends GetView<StockEntryFormController> {
  const StockEntryFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isReadOnly = controller.isSubmitted;
      final isLoading = controller.isMetaLoading.value || (controller.data.isEmpty && controller.name != 'New Stock Entry');

      return FrappeFormLayout(
        title: controller.name,
        isLoading: isLoading,
        status: controller.status,
        onSave: isReadOnly ? null : controller.save,

        // FIX: Added StatusPill to AppBar actions since we removed the manual header
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: StatusPill(status: controller.status),
          ),
        ],

        // FIX: Removed SingleChildScrollView & Column wrappers.
        // GenericFrappeForm must be the direct child to handle its own layout (Tabs/Scrolling).
        body: GenericFrappeForm(controller: controller),
      );
    });
  }
}