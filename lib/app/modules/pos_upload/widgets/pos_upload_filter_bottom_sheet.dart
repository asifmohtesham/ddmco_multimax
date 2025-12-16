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

  String? selectedStatus;
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    customerController = TextEditingController(text: _extractFilterValue('customer'));
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
    if (controller.activeFilters.containsKey('date') &&
        controller.activeFilters['date'] is List) {
      final dates = controller.activeFilters['date'][1] as List;
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
    customerController.dispose();
    dateRangeController.dispose();
    super.dispose();
  }

  int get _activeCount {
    int count = 0;
    if (selectedStatus != null) count++;
    if (customerController.text.isNotEmpty) count++;
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

    if (startDate != null && endDate != null) {
      filters['date'] = ['between', [
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
        controller.clearFilters();
        Get.back();
      },
      filterWidgets: [
        DropdownButtonFormField<String>(
          value: selectedStatus,
          decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
          items: ['Pending', 'Processed', 'Completed', 'Failed', 'Cancelled']
              .map((status) => DropdownMenuItem(value: status, child: Text(status)))
              .toList(),
          onChanged: (value) => setState(() => selectedStatus = value),
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
          onChanged: (_) => setState(() {}),
        ),
      ],
    ));
  }
}