import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/packing_slip/packing_slip_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';

class PackingSlipFilterBottomSheet extends StatefulWidget {
  const PackingSlipFilterBottomSheet({super.key});

  @override
  State<PackingSlipFilterBottomSheet> createState() => _PackingSlipFilterBottomSheetState();
}

class _PackingSlipFilterBottomSheetState extends State<PackingSlipFilterBottomSheet> {
  final PackingSlipController controller = Get.find();

  late TextEditingController deliveryNoteController;
  late TextEditingController dateRangeController;

  String? selectedStatus;
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    deliveryNoteController = TextEditingController(text: _extractFilterValue('delivery_note'));
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
        controller.activeFilters['creation'] is List) {
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
    deliveryNoteController.dispose();
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

  void _applyFilters() {
    final filters = <String, dynamic>{};
    if (selectedStatus != null) filters['status'] = selectedStatus;
    if (deliveryNoteController.text.isNotEmpty) filters['delivery_note'] = ['like', '%${deliveryNoteController.text}%'];

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
      title: 'Filter Packing Slips',
      sortOptions: const [
        SortOption('Creation', 'creation'),
        SortOption('Status', 'status'),
        SortOption('Modified', 'modified'),
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
          items: ['Draft', 'Submitted', 'Cancelled']
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
          controller: deliveryNoteController,
          decoration: const InputDecoration(labelText: 'Delivery Note', border: OutlineInputBorder()),
        ),
      ],
    ));
  }
}