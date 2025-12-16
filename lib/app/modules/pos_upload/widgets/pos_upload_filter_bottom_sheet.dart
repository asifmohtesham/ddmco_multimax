import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/pos_upload/pos_upload_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';

class PosUploadFilterBottomSheet extends StatefulWidget {
  const PosUploadFilterBottomSheet({super.key});

  @override
  State<PosUploadFilterBottomSheet> createState() => _PosUploadFilterBottomSheetState();
}

class _PosUploadFilterBottomSheetState extends State<PosUploadFilterBottomSheet> {
  final PosUploadController controller = Get.find();

  late TextEditingController customerController;
  late TextEditingController dateRangeController;

  // Reactive State
  final selectedStatus = RxnString();
  final startDate = Rxn<DateTime>();
  final endDate = Rxn<DateTime>();
  final customer = ''.obs;

  @override
  void initState() {
    super.initState();
    String initialCustomer = _extractFilterValue('customer');
    customerController = TextEditingController(text: initialCustomer);
    dateRangeController = TextEditingController();

    customer.value = initialCustomer;
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
    if (controller.activeFilters.containsKey('date') &&
        controller.activeFilters['date'] is List) {
      final dates = controller.activeFilters['date'][1] as List;
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
    customerController.dispose();
    dateRangeController.dispose();
    super.dispose();
  }

  int get _activeCount {
    int count = 0;
    if (selectedStatus.value != null) count++;
    if (customer.value.isNotEmpty) count++;
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

    if (startDate.value != null && endDate.value != null) {
      filters['date'] = ['between', [
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
      title: 'Filter POS Uploads',
      activeFilterCount: _activeCount,
      sortOptions: const [
        SortOption('Date', 'date'),
        SortOption('Status', 'status'),
        SortOption('Customer', 'customer'),
        SortOption('Last Modified', 'modified'),
      ],
      currentSortField: controller.sortField.value,
      currentSortOrder: controller.sortOrder.value,
      onSortChanged: (field, order) => controller.setSort(field, order),
      onApply: _applyFilters,
      onClear: () {
        selectedStatus.value = null;
        customerController.clear();
        dateRangeController.clear();
        startDate.value = null;
        endDate.value = null;
        customer.value = '';
        controller.clearFilters();
      },
      filterWidgets: [
        DropdownButtonFormField<String>(
          value: selectedStatus.value,
          decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
          items: ['Pending', 'Processed', 'Completed', 'Failed', 'Cancelled']
              .map((status) => DropdownMenuItem(value: status, child: Text(status)))
              .toList(),
          onChanged: (value) => selectedStatus.value = value,
        ),
        TextFormField(
          controller: dateRangeController,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'Upload Date Range',
            border: OutlineInputBorder(),
            suffixIcon: Icon(Icons.calendar_today),
          ),
          onTap: _pickDateRange,
        ),
        TextFormField(
          controller: customerController,
          decoration: const InputDecoration(labelText: 'Customer', border: OutlineInputBorder()),
          onChanged: (val) => customer.value = val,
        ),
      ],
    ));
  }
}