import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/delivery_note/delivery_note_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';

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
  late TextEditingController dateRangeController;

  // Reactive State
  final selectedStatus = RxnString();
  final startDate = Rxn<DateTime>();
  final endDate = Rxn<DateTime>();
  final poNo = ''.obs;
  final customer = ''.obs;
  final owner = ''.obs;

  @override
  void initState() {
    super.initState();
    poNoController = TextEditingController(text: _extractFilterValue('po_no'));
    customerController = TextEditingController(text: _extractFilterValue('customer'));
    ownerController = TextEditingController(text: _extractFilterValue('owner'));
    dateRangeController = TextEditingController();

    poNo.value = poNoController.text;
    customer.value = customerController.text;
    owner.value = ownerController.text;
    selectedStatus.value = controller.activeFilters['status'];

    _initDateRange();
  }

  String _extractFilterValue(String key) {
    final val = controller.activeFilters[key];
    if (val is List && val.isNotEmpty && val[0] == 'like') {
      return val[1].toString().replaceAll('%', '');
    }
    return '';
  }

  void _initDateRange() {
    if (controller.activeFilters.containsKey('creation') &&
        controller.activeFilters['creation'] is List &&
        controller.activeFilters['creation'][0] == 'between') {
      final dates = controller.activeFilters['creation'][1] as List;
      if (dates.length >= 2) {
        dateRangeController.text = '${dates[0]} - ${dates[1]}';
        try {
          startDate.value = DateTime.parse(dates[0]);
          endDate.value = DateTime.parse(dates[1]);
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    poNoController.dispose();
    customerController.dispose();
    ownerController.dispose();
    dateRangeController.dispose();
    super.dispose();
  }

  int get _activeCount {
    int count = 0;
    if (selectedStatus.value != null) count++;
    if (customer.value.isNotEmpty) count++;
    if (poNo.value.isNotEmpty) count++;
    if (owner.value.isNotEmpty) count++;
    if (startDate.value != null && endDate.value != null) count++;
    return count;
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: startDate.value != null && endDate.value != null
          ? DateTimeRange(start: startDate.value!, end: endDate.value!)
          : null,
    );

    if (picked != null) {
      startDate.value = picked.start;
      endDate.value = picked.end;
      dateRangeController.text = '${DateFormat('yyyy-MM-dd').format(startDate.value!)} - ${DateFormat('yyyy-MM-dd').format(endDate.value!)}';
    }
  }

  void _applyFilters() {
    final filters = <String, dynamic>{};
    if (selectedStatus.value != null) filters['status'] = selectedStatus.value;
    if (customerController.text.isNotEmpty) filters['customer'] = ['like', '%${customerController.text}%'];
    if (poNoController.text.isNotEmpty) filters['po_no'] = ['like', '%${poNoController.text}%'];
    if (ownerController.text.isNotEmpty) filters['owner'] = ['like', '%${ownerController.text}%'];

    if (startDate.value != null && endDate.value != null) {
      filters['creation'] = ['between', [
        DateFormat('yyyy-MM-dd').format(startDate.value!),
        DateFormat('yyyy-MM-dd').format(endDate.value!)
      ]];
    }

    controller.applyFilters(filters);
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => GlobalFilterBottomSheet(
      title: 'Filter Delivery Notes',
      activeFilterCount: _activeCount,
      sortOptions: const [
        SortOption('Creation', 'creation'),
        SortOption('Status', 'status'),
        SortOption('Customer', 'customer'),
      ],
      currentSortField: controller.sortField.value,
      currentSortOrder: controller.sortOrder.value,
      onSortChanged: (field, order) => controller.setSort(field, order),
      onApply: _applyFilters,
      onClear: () {
        selectedStatus.value = null;
        customerController.clear();
        poNoController.clear();
        ownerController.clear();
        dateRangeController.clear();
        startDate.value = null;
        endDate.value = null;
        customer.value = '';
        poNo.value = '';
        owner.value = '';
        controller.clearFilters();
      },
      filterWidgets: [
        // Status Chips
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['Draft', 'Submitted', 'Completed', 'Cancelled'].map((status) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(status),
                      selected: selectedStatus.value == status,
                      onSelected: (bool selected) {
                        selectedStatus.value = selected ? status : null;
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        TextFormField(
          controller: dateRangeController,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'Creation Date Range',
            border: OutlineInputBorder(),
            suffixIcon: Icon(Icons.calendar_today),
            isDense: true,
          ),
          onTap: _pickDateRange,
        ),
        TextFormField(
          controller: customerController,
          decoration: const InputDecoration(labelText: 'Customer', border: OutlineInputBorder(), isDense: true),
          onChanged: (val) => customer.value = val,
        ),
        TextFormField(
          controller: poNoController,
          decoration: const InputDecoration(labelText: 'PO Number', border: OutlineInputBorder(), isDense: true),
          onChanged: (val) => poNo.value = val,
        ),
        TextFormField(
          controller: ownerController,
          decoration: const InputDecoration(labelText: 'Owner', border: OutlineInputBorder(), isDense: true),
          onChanged: (val) => owner.value = val,
        ),
      ],
    ));
  }
}