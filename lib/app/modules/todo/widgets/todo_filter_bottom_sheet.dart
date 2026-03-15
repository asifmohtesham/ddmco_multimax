import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/todo/todo_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';

class ToDoFilterBottomSheet extends StatefulWidget {
  const ToDoFilterBottomSheet({super.key});

  @override
  State<ToDoFilterBottomSheet> createState() => _ToDoFilterBottomSheetState();
}

class _ToDoFilterBottomSheetState extends State<ToDoFilterBottomSheet> {
  final ToDoController _ctrl = Get.find();

  final _status = RxnString();
  final _priority = RxnString();
  final _startDate = Rxn<DateTime>();
  final _endDate = Rxn<DateTime>();
  late TextEditingController _dateRangeController;

  @override
  void initState() {
    super.initState();
    _dateRangeController = TextEditingController();
    final af = _ctrl.activeFilters;

    _status.value = af['status'] as String?;
    _priority.value = af['priority'] as String?;

    final date = af['date'];
    if (date is List &&
        date.length == 2 &&
        date[0] == 'between' &&
        date[1] is List) {
      final dates = date[1] as List;
      if (dates.length >= 2) {
        try {
          _startDate.value = DateTime.parse(dates[0].toString());
          _endDate.value = DateTime.parse(dates[1].toString());
          _dateRangeController.text = '${dates[0]} - ${dates[1]}';
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _dateRangeController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _startDate.value != null && _endDate.value != null
          ? DateTimeRange(start: _startDate.value!, end: _endDate.value!)
          : null,
    );
    if (picked != null) {
      _startDate.value = picked.start;
      _endDate.value = picked.end;
      _dateRangeController.text =
          '${DateFormat('yyyy-MM-dd').format(picked.start)} - '
          '${DateFormat('yyyy-MM-dd').format(picked.end)}';
    }
  }

  void _apply() {
    final filters = <String, dynamic>{};
    if (_status.value != null) filters['status'] = _status.value;
    if (_priority.value != null) filters['priority'] = _priority.value;
    if (_startDate.value != null && _endDate.value != null) {
      filters['date'] = [
        'between',
        [
          DateFormat('yyyy-MM-dd').format(_startDate.value!),
          DateFormat('yyyy-MM-dd').format(_endDate.value!),
        ]
      ];
    }
    _ctrl.applyFilters(filters);
    Get.back();
  }

  void _clear() {
    _status.value = null;
    _priority.value = null;
    _startDate.value = null;
    _endDate.value = null;
    _dateRangeController.clear();
    _ctrl.clearFilters();
    Get.back();
  }

  int get _localFilterCount {
    int count = 0;
    if (_status.value != null) count++;
    if (_priority.value != null) count++;
    if (_startDate.value != null && _endDate.value != null) count++;
    return count;
  }

  Widget _chipRow({
    required BuildContext context,
    required String label,
    required List<String> options,
    required RxnString selected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: options.map((opt) {
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Obx(() => ChoiceChip(
                      label: Text(opt),
                      selected: selected.value == opt,
                      onSelected: (sel) =>
                          selected.value = sel ? opt : null,
                    )),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => GlobalFilterBottomSheet(
          title: 'Filter ToDos',
          activeFilterCount: _localFilterCount,
          sortOptions: const [
            SortOption('Modified', 'modified'),
            SortOption('Date', 'date'),
            SortOption('Priority', 'priority'),
            SortOption('Status', 'status'),
          ],
          currentSortField: _ctrl.sortField.value,
          currentSortOrder: _ctrl.sortOrder.value,
          onSortChanged: _ctrl.setSort,
          onApply: _apply,
          onClear: _clear,
          filterWidgets: [
            const SizedBox(height: 16),

            // ── Status ──────────────────────────────────────────────────
            _chipRow(
              context: context,
              label: 'Status',
              options: const ['Open', 'Closed', 'Cancelled'],
              selected: _status,
            ),
            const SizedBox(height: 16),

            // ── Priority ──────────────────────────────────────────────
            _chipRow(
              context: context,
              label: 'Priority',
              options: const ['Low', 'Medium', 'High', 'Urgent'],
              selected: _priority,
            ),
            const SizedBox(height: 16),

            // ── Due Date Range ────────────────────────────────────────
            TextFormField(
              controller: _dateRangeController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Due Date Range',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                suffixIcon: _startDate.value != null
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _startDate.value = null;
                          _endDate.value = null;
                          _dateRangeController.clear();
                        },
                      )
                    : const Icon(Icons.calendar_today_outlined),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
              onTap: _pickDateRange,
            ),
          ],
        ));
  }
}
