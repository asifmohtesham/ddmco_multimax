import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/stock_entry/stock_entry_controller.dart';

class StockEntryFilterBottomSheet extends StatefulWidget {
  const StockEntryFilterBottomSheet({super.key});

  @override
  State<StockEntryFilterBottomSheet> createState() => _StockEntryFilterBottomSheetState();
}

class _StockEntryFilterBottomSheetState extends State<StockEntryFilterBottomSheet> {
  final StockEntryController controller = Get.find();

  late TextEditingController purposeController;
  late TextEditingController referenceController;
  late TextEditingController dateRangeController;

  int? selectedDocstatus; // 0=Draft, 1=Submitted, 2=Cancelled
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    purposeController = TextEditingController(text: controller.activeFilters['purpose']);
    referenceController = TextEditingController(text: controller.activeFilters['custom_reference_no']);
    selectedDocstatus = controller.activeFilters['docstatus'];
    dateRangeController = TextEditingController();

    // Attempt to parse existing date filter if it exists (simple check)
    if (controller.activeFilters.containsKey('creation') && controller.activeFilters['creation'] is List) {
      // Logic to pre-fill date text if needed, usually skipped for simplicity in reset
    }
  }

  @override
  void dispose() {
    purposeController.dispose();
    referenceController.dispose();
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
                      _buildSortChip('Modified', 'modified'),
                      _buildSortChip('Purpose', 'purpose'),
                    ],
                  )),
                  const SizedBox(height: 16),
                  const Text('Filter By', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: selectedDocstatus,
                    decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Draft')),
                      DropdownMenuItem(value: 1, child: Text('Submitted')),
                      DropdownMenuItem(value: 2, child: Text('Cancelled')),
                    ],
                    onChanged: (value) => selectedDocstatus = value,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: dateRangeController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Date Range',
                      border: const OutlineInputBorder(),
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    onTap: _pickDateRange,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: purposeController,
                    decoration: const InputDecoration(labelText: 'Purpose', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: referenceController,
                    decoration: const InputDecoration(labelText: 'Reference No', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final filters = <String, dynamic>{};

                if (selectedDocstatus != null) filters['docstatus'] = selectedDocstatus;
                if (purposeController.text.isNotEmpty) filters['purpose'] = ['like', '%${purposeController.text}%'];
                if (referenceController.text.isNotEmpty) filters['custom_reference_no'] = ['like', '%${referenceController.text}%'];

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
          final newOrder = controller.sortOrder.value == 'desc' ? 'asc' : 'desc';
          controller.setSort(field, newOrder);
        } else {
          controller.setSort(field, 'desc');
        }
      },
    );
  }
}