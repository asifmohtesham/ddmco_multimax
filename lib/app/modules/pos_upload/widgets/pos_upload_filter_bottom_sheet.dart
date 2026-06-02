import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/customer_model.dart';
import 'package:multimax/app/modules/pos_upload/pos_upload_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';

class PosUploadFilterBottomSheet extends StatefulWidget {
  const PosUploadFilterBottomSheet({super.key});

  @override
  State<PosUploadFilterBottomSheet> createState() =>
      _PosUploadFilterBottomSheetState();
}

class _PosUploadFilterBottomSheetState
    extends State<PosUploadFilterBottomSheet> {
  final PosUploadController controller = Get.find();

  late TextEditingController customerController;
  late TextEditingController dateRangeController;

  final selectedStatus = RxnString();
  final startDate = Rxn<DateTime>();
  final endDate = Rxn<DateTime>();
  final customerName = ''.obs; // display label
  final customer = ''.obs;     // exact Frappe name (filter value)

  @override
  void initState() {
    super.initState();
    customerController = TextEditingController();
    dateRangeController = TextEditingController();

    selectedStatus.value = controller.activeFilters['status'];

    // Restore customer — stored as exact name
    final saved = controller.activeFilters['customer'];
    if (saved is String && saved.isNotEmpty) {
      customer.value = saved;
      final match = controller.customers
          .firstWhereOrNull((c) => c.name == saved);
      final label = match != null ? match.customerName : saved;
      customerName.value = label;
      customerController.text = label;
    }

    _initDateRange();
  }

  void _initDateRange() {
    final f = controller.activeFilters['date'];
    if (f is List && f.isNotEmpty && f[0] == 'between') {
      final dates = f[1] as List;
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
      dateRangeController.text =
      '${DateFormat('yyyy-MM-dd').format(startDate.value!)} '
          '- ${DateFormat('yyyy-MM-dd').format(endDate.value!)}';
    }
  }

  // ---------------------------------------------------------------------------
  // Customer picker
  // ---------------------------------------------------------------------------
  void _showCustomerPicker() {
    final searchCtrl = TextEditingController();
    final filtered = RxList<CustomerEntry>(controller.customers);

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
                      Text('Select Customer',
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
                      hintText: 'Search customers...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (val) {
                      final term = val.toLowerCase();
                      filtered.assignAll(val.isEmpty
                          ? controller.customers
                          : controller.customers.where((c) =>
                      c.name.toLowerCase().contains(term) ||
                          c.customerName.toLowerCase().contains(term)));
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Obx(() {
                      if (controller.isFetchingCustomers.value) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (filtered.isEmpty) {
                        return const Center(
                            child: Text('No customers found'));
                      }
                      return ListView.separated(
                        controller: scrollCtrl,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = filtered[i];
                          final isSelected = customer.value == c.name;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isSelected
                                  ? colorScheme.primaryContainer
                                  : colorScheme.secondaryContainer,
                              child: Text(
                                c.customerName.isNotEmpty
                                    ? c.customerName[0].toUpperCase()
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
                              c.customerName,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                            ),
                            subtitle: c.name != c.customerName
                                ? Text(c.name,
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
                              customer.value = c.name;
                              customerName.value = c.customerName;
                              customerController.text = c.customerName;
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
    if (selectedStatus.value != null) filters['status'] = selectedStatus.value;
    if (customer.value.isNotEmpty) filters['customer'] = customer.value; // exact
    if (startDate.value != null && endDate.value != null) {
      filters['date'] = [
        'between',
        [
          DateFormat('yyyy-MM-dd').format(startDate.value!),
          DateFormat('yyyy-MM-dd').format(endDate.value!),
        ]
      ];
    }
    controller.applyFilters(filters);
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        customer.value = '';
        customerName.value = '';
        customerController.clear();
        dateRangeController.clear();
        startDate.value = null;
        endDate.value = null;
        controller.clearFilters();
      },
      filterWidgets: [
        // ── Status chips ────────────────────────────────────────────
        Text('Status', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Obx(() => Row(
            children: [
              for (final s in [
                'Pending',
                'Processed',
                'Completed',
                'Failed',
                'Cancelled',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s),
                    selected: selectedStatus.value == s,
                    onSelected: (sel) =>
                    selectedStatus.value = sel ? s : null,
                  ),
                ),
            ],
          )),
        ),
        const SizedBox(height: 16),

        // ── Date range ───────────────────────────────────────────────
        TextFormField(
          controller: dateRangeController,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'Upload Date Range',
            hintText: 'Tap to select',
            border: OutlineInputBorder(),
            suffixIcon: Icon(Icons.calendar_today),
            isDense: true,
          ),
          onTap: _pickDateRange,
        ),
        const SizedBox(height: 16),

        // ── Customer Link picker ─────────────────────────────────────
        Obx(() => TextFormField(
          controller: customerController,
          readOnly: true,
          onTap: _showCustomerPicker,
          decoration: InputDecoration(
            labelText: 'Customer',
            hintText: 'Tap to select',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person_outline),
            suffixIcon: customer.value.isNotEmpty
                ? IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Clear',
              onPressed: () {
                customer.value = '';
                customerName.value = '';
                customerController.clear();
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
