import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/purchase_receipt/purchase_receipt_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';

class PurchaseReceiptFilterBottomSheet extends StatefulWidget {
  const PurchaseReceiptFilterBottomSheet({super.key});

  @override
  State<PurchaseReceiptFilterBottomSheet> createState() => _PurchaseReceiptFilterBottomSheetState();
}

class _PurchaseReceiptFilterBottomSheetState extends State<PurchaseReceiptFilterBottomSheet> {
  final PurchaseReceiptController controller = Get.find();

  // Local State
  late TextEditingController supplierController;
  String? selectedStatus;

  @override
  void initState() {
    super.initState();
    // Initialize from controller's active filters
    supplierController = TextEditingController(text: controller.activeFilters['supplier']);
    selectedStatus = controller.activeFilters['status'];
  }

  @override
  void dispose() {
    supplierController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    final filters = <String, dynamic>{};

    if (supplierController.text.isNotEmpty) {
      filters['supplier'] = supplierController.text;
    }
    if (selectedStatus != null) {
      filters['status'] = selectedStatus;
    }

    controller.applyFilters(filters);
    Get.back();
  }

  void _clearFilters() {
    supplierController.clear();
    setState(() {
      selectedStatus = null;
    });
    controller.clearFilters();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate active filter count (Supplier + Status)
    int activeCount = 0;
    if (supplierController.text.isNotEmpty) activeCount++;
    if (selectedStatus != null) activeCount++;

    return Obx(() => GlobalFilterBottomSheet(
      title: 'Filter Purchase Receipts',
      activeFilterCount: activeCount,

      // Sort Configuration
      sortOptions: const [
        SortOption('Date', 'creation'),
        SortOption('Supplier', 'supplier'),
        SortOption('Status', 'status'),
        SortOption('Grand Total', 'grand_total'),
      ],
      currentSortField: controller.sortField.value,
      currentSortOrder: controller.sortOrder.value,
      onSortChanged: (field, order) => controller.setSort(field, order),

      // Actions
      onApply: _applyFilters,
      onClear: _clearFilters,

      // Filter Widgets
      filterWidgets: [
        TextField(
          controller: supplierController,
          decoration: const InputDecoration(
            labelText: 'Supplier',
            prefixIcon: Icon(Icons.store),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: selectedStatus,
          decoration: const InputDecoration(
            labelText: 'Status',
            prefixIcon: Icon(Icons.flag),
            border: OutlineInputBorder(),
          ),
          items: ['Draft', 'Submitted', 'Completed', 'Cancelled']
              .map((status) => DropdownMenuItem(value: status, child: Text(status)))
              .toList(),
          onChanged: (value) => setState(() => selectedStatus = value),
        ),
      ],
    ));
  }
}