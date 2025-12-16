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

  String? selectedStatus;
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    poNoController = TextEditingController(text: _extractFilterValue('po_no'));
    customerController = TextEditingController(text: _extractFilterValue('customer'));
    ownerController = TextEditingController(text: _extractFilterValue('owner'));
    selectedStatus = controller.activeFilters['status'];

    dateRangeController = TextEditingController();
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
          startDate = DateTime.parse(dates[0]);
          endDate = DateTime.parse(dates[1]);
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
    if (selectedStatus != null) count++;
    if (customerController.text.isNotEmpty) count++;
    if (poNoController.text.isNotEmpty) count++;
    if (ownerController.text.isNotEmpty) count++;
    if (startDate != null && endDate != null) count++;
    return count;
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

  void _applyFilters() {
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
        controller.clearFilters();
        Get.back();
      },
      filterWidgets: [
        DropdownButtonFormField<String>(
          value: selectedStatus,
          decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
          items: ['Draft', 'Submitted', 'Completed', 'Cancelled']
              .map((status) => DropdownMenuItem(value: status, child: Text(status)))
              .toList(),
          onChanged: (value) => setState(() => selectedStatus = value),
        ),
        TextFormField(
          controller: dateRangeController,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'Creation Date Range',
            border: OutlineInputBorder(),
            suffixIcon: Icon(Icons.calendar_today),
          ),
          onTap: _pickDateRange,
        ),
        TextFormField(
          controller: customerController,
          decoration: const InputDecoration(labelText: 'Customer', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        TextFormField(
          controller: poNoController,
          decoration: const InputDecoration(labelText: 'PO Number', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        TextFormField(
          controller: ownerController,
          decoration: const InputDecoration(labelText: 'Owner', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ));
  }
}