import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/supplier_model.dart';
import 'package:multimax/app/modules/purchase_order/purchase_order_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';

class PurchaseOrderFilterBottomSheet extends StatefulWidget {
  const PurchaseOrderFilterBottomSheet({super.key});

  @override
  State<PurchaseOrderFilterBottomSheet> createState() =>
      _PurchaseOrderFilterBottomSheetState();
}

class _PurchaseOrderFilterBottomSheetState
    extends State<PurchaseOrderFilterBottomSheet> {
  final PurchaseOrderController controller = Get.find();

  late TextEditingController supplierController;

  final supplierName = ''.obs; // display label
  final supplier = ''.obs;     // filter value (exact Supplier.name)

  @override
  void initState() {
    super.initState();
    supplierController = TextEditingController();

    // Restore from active filters
    final saved = controller.activeFilters['supplier'];
    if (saved is String && saved.isNotEmpty) {
      supplier.value = saved;
      final match =
      controller.suppliers.firstWhereOrNull((s) => s.name == saved);
      final label = match != null ? match.supplierName : saved;
      supplierName.value = label;
      supplierController.text = label;
    }
  }

  @override
  void dispose() {
    supplierController.dispose();
    super.dispose();
  }

  int get _activeCount => supplier.value.isNotEmpty ? 1 : 0;

  // ---------------------------------------------------------------------------
  void _showSupplierPicker() {
    final searchCtrl = TextEditingController();
    final filtered = RxList<SupplierEntry>(controller.suppliers);

    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scrollCtrl) {
            final colorScheme = Theme.of(ctx).colorScheme;
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select Supplier',
                          style: Theme.of(ctx).textTheme.titleLarge),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: Get.back),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search suppliers...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (val) {
                      final term = val.toLowerCase();
                      filtered.assignAll(val.isEmpty
                          ? controller.suppliers
                          : controller.suppliers.where((s) =>
                      s.name.toLowerCase().contains(term) ||
                          s.supplierName.toLowerCase().contains(term)));
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Obx(() {
                      if (controller.isFetchingSuppliers.value) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (filtered.isEmpty) {
                        return const Center(
                            child: Text('No suppliers found'));
                      }
                      return ListView.separated(
                        controller: scrollCtrl,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final s = filtered[i];
                          final isSelected = supplier.value == s.name;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isSelected
                                  ? colorScheme.primaryContainer
                                  : colorScheme.secondaryContainer,
                              child: Text(
                                s.supplierName.isNotEmpty
                                    ? s.supplierName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: isSelected
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              s.supplierName,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                            ),
                            subtitle: s.name != s.supplierName
                                ? Text(s.name,
                                style: Theme.of(ctx)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                    color: colorScheme
                                        .onSurfaceVariant))
                                : null,
                            trailing: isSelected
                                ? Icon(Icons.check_circle,
                                color: colorScheme.primary, size: 18)
                                : null,
                            onTap: () {
                              Get.back();
                              supplier.value = s.name;
                              supplierName.value = s.supplierName;
                              supplierController.text = s.supplierName;
                            },
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      isScrollControlled: true,
    );
  }

  // ---------------------------------------------------------------------------
  void _applyFilters() {
    final filters = <String, dynamic>{};
    if (supplier.value.isNotEmpty) {
      filters['supplier'] = supplier.value; // exact match
    }
    controller.applyFilters(filters);
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => GlobalFilterBottomSheet(
      title: 'Filter Purchase Orders',
      activeFilterCount: _activeCount,
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
        supplier.value = '';
        supplierName.value = '';
        supplierController.clear();
        controller.clearFilters();
      },
      filterWidgets: [
        Obx(() => TextFormField(
          controller: supplierController,
          readOnly: true,
          onTap: _showSupplierPicker,
          decoration: InputDecoration(
            labelText: 'Supplier',
            hintText: 'Tap to select',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.business_outlined),
            suffixIcon: supplier.value.isNotEmpty
                ? IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Clear',
              onPressed: () {
                supplier.value = '';
                supplierName.value = '';
                supplierController.clear();
              },
            )
                : const Icon(Icons.arrow_drop_down),
            isDense: true,
          ),
        )),
      ],
    ));
  }
}
