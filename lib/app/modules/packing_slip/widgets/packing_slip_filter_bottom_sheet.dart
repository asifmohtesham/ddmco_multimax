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

  // Reactive State
  final selectedStatus = RxnString();
  final startDate = Rxn<DateTime>();
  final endDate = Rxn<DateTime>();
  final deliveryNote = ''.obs;

  @override
  void initState() {
    super.initState();
    String initialNote = _extractFilterValue('delivery_note');
    deliveryNoteController = TextEditingController(text: initialNote);
    dateRangeController = TextEditingController();

    deliveryNote.value = initialNote;
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
        controller.activeFilters['creation'] is List) {
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
    deliveryNoteController.dispose();
    dateRangeController.dispose();
    super.dispose();
  }

  int get _activeCount {
    int count = 0;
    if (selectedStatus.value != null) count++;
    if (deliveryNote.value.isNotEmpty) count++;
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
    if (deliveryNoteController.text.isNotEmpty) filters['delivery_note'] = ['like', '%${deliveryNoteController.text}%'];

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
      title: 'Filter Packing Slips',
      activeFilterCount: _activeCount,
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
        selectedStatus.value = null;
        deliveryNoteController.clear();
        dateRangeController.clear();
        startDate.value = null;
        endDate.value = null;
        deliveryNote.value = '';
        controller.clearFilters();
      },
      filterWidgets: [
        DropdownButtonFormField<String>(
          value: selectedStatus.value,
          decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
          items: ['Draft', 'Submitted', 'Cancelled']
              .map((status) => DropdownMenuItem(value: status, child: Text(status)))
              .toList(),
          onChanged: (value) => selectedStatus.value = value,
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
          onChanged: (val) => deliveryNote.value = val,
        ),
      ],
    ));
  }
}