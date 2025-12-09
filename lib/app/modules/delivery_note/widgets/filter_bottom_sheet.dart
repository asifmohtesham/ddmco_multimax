import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/delivery_note/delivery_note_controller.dart';

class FilterBottomSheet extends StatefulWidget {
  const FilterBottomSheet({super.key});

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  final DeliveryNoteController controller = Get.find();
  
  late TextEditingController poNoController;
  late TextEditingController customerController;
  late TextEditingController ownerController;
  late TextEditingController itemCodeController;
  late TextEditingController dateRangeController;
  
  String? selectedStatus;
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    poNoController = TextEditingController(text: controller.activeFilters['po_no']);
    customerController = TextEditingController(text: controller.activeFilters['customer']);
    ownerController = TextEditingController(text: controller.activeFilters['owner']);
    itemCodeController = TextEditingController(text: controller.activeFilters['item_code']);
    
    selectedStatus = controller.activeFilters['status'];
    
    dateRangeController = TextEditingController();
  }

  @override
  void dispose() {
    poNoController.dispose();
    customerController.dispose();
    ownerController.dispose();
    itemCodeController.dispose();
    dateRangeController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: startDate != null && endDate != null 
          ? DateTimeRange(start: startDate!, end: endDate!) 
          : null,
    );

    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
        dateRangeController.text = '${DateFormat('yyyy-MM-dd').format(startDate!)} - ${DateFormat('yyyy-MM-dd').format(endDate!)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Sort & Filter', style: Theme.of(context).textTheme.titleLarge),
                TextButton(
                  onPressed: () {
                    controller.clearFilters();
                    Get.back();
                  },
                  child: const Text('Clear All'),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView(
                children: [
                  const Text('Sort By', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Obx(() => Wrap(
                    spacing: 8.0,
                    children: [
                      _buildSortChip('Creation', 'creation'),
                      _buildSortChip('Status', 'status'),
                      _buildSortChip('Customer', 'customer'),
                    ],
                  )),
                  const SizedBox(height: 16),
                  const Text('Filter By', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                    items: ['Draft', 'Submitted', 'Completed', 'Cancelled']
                        .map((status) => DropdownMenuItem(value: status, child: Text(status)))
                        .toList(),
                    onChanged: (value) => selectedStatus = value,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: dateRangeController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Creation Date Range',
                      border: const OutlineInputBorder(),
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    onTap: _pickDateRange,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: customerController,
                    decoration: const InputDecoration(labelText: 'Customer', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: poNoController,
                    decoration: const InputDecoration(labelText: 'PO Number', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: ownerController,
                    decoration: const InputDecoration(labelText: 'Owner', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final filters = <String, dynamic>{};
                if (selectedStatus != null) filters['status'] = selectedStatus;
                if (customerController.text.isNotEmpty) filters['customer'] = ['like', '%${customerController.text}%'];
                if (poNoController.text.isNotEmpty) filters['po_no'] = ['like', '%${poNoController.text}%'];
                if (ownerController.text.isNotEmpty) filters['owner'] = ['like', '%${ownerController.text}%'];
                
                if (startDate != null && endDate != null) {
                  filters['creation'] = ['between', [
                    DateFormat('yyyy-MM-dd').format(startDate!),
                    DateFormat('yyyy-MM-dd').format(endDate!)
                  ]];
                }

                controller.applyFilters(filters);
                Get.back();
              },
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('Apply Filters'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortChip(String label, String field) {
    final isSelected = controller.sortField.value == field;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (isSelected) ...[
            const SizedBox(width: 4),
            Icon(
              controller.sortOrder.value == 'desc' ? Icons.arrow_downward : Icons.arrow_upward,
              size: 16,
            ),
          ],
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (isSelected) {
          // Toggle order
          final newOrder = controller.sortOrder.value == 'desc' ? 'asc' : 'desc';
          controller.setSort(field, newOrder);
        } else {
          // Select field, default desc
          controller.setSort(field, 'desc');
        }
      },
    );
  }
}
