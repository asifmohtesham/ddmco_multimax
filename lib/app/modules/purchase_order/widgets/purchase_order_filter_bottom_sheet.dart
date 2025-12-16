import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/purchase_order/purchase_order_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';

class PurchaseOrderFilterBottomSheet extends StatefulWidget {
  const PurchaseOrderFilterBottomSheet({super.key});

  @override
  State<PurchaseOrderFilterBottomSheet> createState() => _PurchaseOrderFilterBottomSheetState();
}

class _PurchaseOrderFilterBottomSheetState extends State<PurchaseOrderFilterBottomSheet> {
  final PurchaseOrderController controller = Get.find();
  late TextEditingController supplierController;

  @override
  void initState() {
    super.initState();
    supplierController = TextEditingController(text: _extractFilterValue('supplier'));
  }

  String _extractFilterValue(String key) {
    final val = controller.activeFilters[key];
    if (val is List && val.isNotEmpty && val[0] == 'like') {
      return val[1].toString().replaceAll('%', '');
    }
    if (val is String) return val;
    return '';
  }

  @override
  void dispose() {
    supplierController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    final filters = <String, dynamic>{};
    if (supplierController.text.isNotEmpty) {
      filters['supplier'] = ['like', '%${supplierController.text}%'];
    }
    controller.applyFilters(filters);
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => GlobalFilterBottomSheet(
      title: 'Filter Purchase Orders',
      sortOptions: const [
        SortOption('Date', 'transaction_date'),
        SortOption('Modified', 'modified'),
        SortOption('Supplier', 'supplier'),
        SortOption('Total', 'grand_total'),
      ],
      currentSortField: controller.sortField.value,
      currentSortOrder: controller.sortOrder.value,
      onSortChanged: (field, order) => controller.setSort(field, order),
      onApply: _applyFilters,
      onClear: () {
        controller.clearFilters();
        Get.back();
      },
      filterWidgets: [
        TextFormField(
          controller: supplierController,
          decoration: const InputDecoration(
            labelText: 'Supplier',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.business),
          ),
        ),
      ],
    ));
  }
}