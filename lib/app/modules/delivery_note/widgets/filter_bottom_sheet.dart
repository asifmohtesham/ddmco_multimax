import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/user_model.dart';
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
  late TextEditingController modifiedByController;
  late TextEditingController setWarehouseController;
  late TextEditingController dateRangeController;

  final selectedStatus  = RxnString();
  final startDate       = Rxn<DateTime>();
  final endDate         = Rxn<DateTime>();
  final poNo            = ''.obs;
  final customer        = ''.obs;
  final owner           = ''.obs;
  final modifiedBy      = ''.obs;
  final setWarehouse    = ''.obs;

  @override
  void initState() {
    super.initState();

    poNoController        = TextEditingController(text: _extractLike('po_no'));
    customerController    = TextEditingController(text: _extractLike('customer'));
    ownerController       = TextEditingController();
    modifiedByController  = TextEditingController();
    setWarehouseController = TextEditingController();
    dateRangeController   = TextEditingController();

    poNo.value     = poNoController.text;
    customer.value = customerController.text;

    selectedStatus.value = controller.activeFilters['status'];

    // Restore owner
    final savedOwner = controller.activeFilters['owner'];
    if (savedOwner is String && savedOwner.isNotEmpty) {
      owner.value = savedOwner;
      final match = controller.users
          .firstWhereOrNull((u) => u.email == savedOwner || u.id == savedOwner);
      ownerController.text =
          (match != null && match.name.isNotEmpty) ? match.name : savedOwner;
    }

    // Restore modified_by
    final savedModifiedBy = controller.activeFilters['modified_by'];
    if (savedModifiedBy is String && savedModifiedBy.isNotEmpty) {
      modifiedBy.value = savedModifiedBy;
      final match = controller.users.firstWhereOrNull(
          (u) => u.email == savedModifiedBy || u.id == savedModifiedBy);
      modifiedByController.text =
          (match != null && match.name.isNotEmpty) ? match.name : savedModifiedBy;
    }

    // Restore set_warehouse
    final savedWarehouse = controller.activeFilters['set_warehouse'];
    if (savedWarehouse is String && savedWarehouse.isNotEmpty) {
      setWarehouse.value       = savedWarehouse;
      setWarehouseController.text = savedWarehouse;
    }

    _initDateRange();
  }

  String _extractLike(String key) {
    final val = controller.activeFilters[key];
    if (val is List && val.isNotEmpty && val[0] == 'like') {
      return val[1].toString().replaceAll('%', '');
    }
    if (val is String) return val;
    return '';
  }

  void _initDateRange() {
    final f = controller.activeFilters['creation'];
    if (f is List && f.isNotEmpty && f[0] == 'between') {
      final dates = f[1] as List;
      if (dates.length >= 2) {
        dateRangeController.text = '${dates[0]} - ${dates[1]}';
        try {
          startDate.value = DateTime.parse(dates[0]);
          endDate.value   = DateTime.parse(dates[1]);
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    poNoController.dispose();
    customerController.dispose();
    ownerController.dispose();
    modifiedByController.dispose();
    setWarehouseController.dispose();
    dateRangeController.dispose();
    super.dispose();
  }

  int get _activeCount {
    int count = 0;
    if (selectedStatus.value != null)                    count++;
    if (customer.value.isNotEmpty)                       count++;
    if (poNo.value.isNotEmpty)                           count++;
    if (owner.value.isNotEmpty)                          count++;
    if (modifiedBy.value.isNotEmpty)                     count++;
    if (setWarehouse.value.isNotEmpty)                   count++;
    if (startDate.value != null && endDate.value != null) count++;
    return count;
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      initialDateRange: startDate.value != null && endDate.value != null
          ? DateTimeRange(start: startDate.value!, end: endDate.value!)
          : null,
      helpText: 'Select Creation Date Range',
    );
    if (picked != null) {
      startDate.value = picked.start;
      endDate.value   = picked.end;
      dateRangeController.text =
          '${DateFormat('yyyy-MM-dd').format(startDate.value!)} '
          '- ${DateFormat('yyyy-MM-dd').format(endDate.value!)}';
    }
  }

  // ---------------------------------------------------------------------------
  // Generic user picker
  // ---------------------------------------------------------------------------
  void _showUserPicker({
    required String title,
    required void Function(String userId, String displayName) onSelected,
  }) {
    final searchCtrl   = TextEditingController();
    final RxList<User> filtered = RxList<User>(controller.users);

    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
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
                      Text(title,
                          style: Theme.of(ctx).textTheme.titleLarge),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: Get.back),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search users...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (val) {
                      final term = val.toLowerCase();
                      filtered.assignAll(val.isEmpty
                          ? controller.users
                          : controller.users.where((u) =>
                              u.name.toLowerCase().contains(term) ||
                              u.email.toLowerCase().contains(term)));
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Obx(() {
                      if (controller.isFetchingUsers.value) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (filtered.isEmpty) {
                        return const Center(child: Text('No users found'));
                      }
                      return ListView.separated(
                        controller: scrollCtrl,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final u = filtered[i];
                          final userId =
                              u.email.isNotEmpty ? u.email : u.id;
                          final displayName =
                              u.name.isNotEmpty ? u.name : userId;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  colorScheme.secondaryContainer,
                              child: Text(
                                displayName[0].toUpperCase(),
                                style: TextStyle(
                                    color:
                                        colorScheme.onSecondaryContainer),
                              ),
                            ),
                            title: Text(displayName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(u.email),
                            onTap: () {
                              Get.back();
                              onSelected(userId, displayName);
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
  // Warehouse picker
  // ---------------------------------------------------------------------------
  void _showWarehousePicker() {
    final searchCtrl = TextEditingController();
    final RxList<String> filtered = RxList<String>(controller.warehouses);

    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
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
                      Text('Select Warehouse',
                          style: Theme.of(ctx).textTheme.titleLarge),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: Get.back),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search warehouses...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (val) {
                      final term = val.toLowerCase();
                      filtered.assignAll(val.isEmpty
                          ? controller.warehouses
                          : controller.warehouses.where(
                              (w) => w.toLowerCase().contains(term)));
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Obx(() {
                      if (controller.isFetchingWarehouses.value) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (filtered.isEmpty) {
                        return const Center(
                            child: Text('No warehouses found'));
                      }
                      return ListView.separated(
                        controller: scrollCtrl,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final wh         = filtered[i];
                          final isSelected = setWarehouse.value == wh;
                          return ListTile(
                            leading: Icon(
                              Icons.warehouse_outlined,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            title: Text(
                              wh,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                            ),
                            trailing: isSelected
                                ? Icon(Icons.check_circle,
                                    color: colorScheme.primary, size: 18)
                                : null,
                            onTap: () {
                              Get.back();
                              setWarehouse.value          = wh;
                              setWarehouseController.text = wh;
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
  // Apply
  // ---------------------------------------------------------------------------
  void _applyFilters() {
    final filters = <String, dynamic>{};

    if (selectedStatus.value != null)
      filters['status'] = selectedStatus.value;
    if (customerController.text.isNotEmpty)
      filters['customer'] = ['like', '%${customerController.text}%'];
    if (poNoController.text.isNotEmpty)
      filters['po_no'] = ['like', '%${poNoController.text}%'];
    if (owner.value.isNotEmpty)
      filters['owner'] = owner.value;
    if (modifiedBy.value.isNotEmpty)
      filters['modified_by'] = modifiedBy.value;
    if (setWarehouse.value.isNotEmpty)
      filters['set_warehouse'] = setWarehouse.value;
    if (startDate.value != null && endDate.value != null) {
      filters['creation'] = [
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
          title: 'Filter Delivery Notes',
          activeFilterCount: _activeCount,
          sortOptions: const [
            SortOption('Creation',     'creation'),
            SortOption('Posting Date', 'posting_date'),
            SortOption('Status',       'status'),
            SortOption('Customer',     'customer'),
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
            modifiedByController.clear();
            setWarehouseController.clear();
            dateRangeController.clear();
            startDate.value    = null;
            endDate.value      = null;
            customer.value     = '';
            poNo.value         = '';
            owner.value        = '';
            modifiedBy.value   = '';
            setWarehouse.value = '';
            controller.clearFilters();
          },
          filterWidgets: [
            // ── Status chips ───────────────────────────────────────────────
            Text('Status', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Obx(() => Row(
                    children: [
                      for (final s in [
                        'Draft',
                        'Submitted',
                        'Return',
                        'Completed',
                        'Cancelled'
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

            // ── Creation date range ───────────────────────────────────────
            TextFormField(
              controller: dateRangeController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Creation Date Range',
                hintText: 'Tap to select',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
                isDense: true,
              ),
              onTap: _pickDateRange,
            ),
            const SizedBox(height: 16),

            // ── Customer ─────────────────────────────────────────────────
            TextFormField(
              controller: customerController,
              decoration: const InputDecoration(
                labelText: 'Customer',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business_outlined),
                isDense: true,
              ),
              onChanged: (val) => customer.value = val,
            ),
            const SizedBox(height: 16),

            // ── PO Number ───────────────────────────────────────────────
            TextFormField(
              controller: poNoController,
              decoration: const InputDecoration(
                labelText: 'PO Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.tag),
                isDense: true,
              ),
              onChanged: (val) => poNo.value = val,
            ),
            const SizedBox(height: 16),

            // ── Source Warehouse (Warehouse DocType picker) ───────────────
            Obx(() => TextFormField(
                  controller: setWarehouseController,
                  readOnly: true,
                  onTap: _showWarehousePicker,
                  decoration: InputDecoration(
                    labelText: 'Source Warehouse',
                    hintText: 'Tap to select',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.warehouse_outlined),
                    suffixIcon: setWarehouse.value.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Clear',
                            onPressed: () {
                              setWarehouse.value = '';
                              setWarehouseController.clear();
                            },
                          )
                        : const Icon(Icons.arrow_drop_down),
                    isDense: true,
                  ),
                )),
            const SizedBox(height: 16),

            // ── Created By (user picker) ───────────────────────────────
            Obx(() => TextFormField(
                  controller: ownerController,
                  readOnly: true,
                  onTap: () => _showUserPicker(
                    title: 'Select Owner',
                    onSelected: (userId, displayName) {
                      owner.value          = userId;
                      ownerController.text = displayName;
                    },
                  ),
                  decoration: InputDecoration(
                    labelText: 'Created By',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.person_add_alt_1_outlined),
                    suffixIcon: owner.value.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Clear',
                            onPressed: () {
                              owner.value = '';
                              ownerController.clear();
                            },
                          )
                        : const Icon(Icons.arrow_drop_down),
                    isDense: true,
                  ),
                )),
            const SizedBox(height: 16),

            // ── Modified By (user picker) ────────────────────────────
            Obx(() => TextFormField(
                  controller: modifiedByController,
                  readOnly: true,
                  onTap: () => _showUserPicker(
                    title: 'Select Modified By',
                    onSelected: (userId, displayName) {
                      modifiedBy.value          = userId;
                      modifiedByController.text = displayName;
                    },
                  ),
                  decoration: InputDecoration(
                    labelText: 'Modified By',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.edit_outlined),
                    suffixIcon: modifiedBy.value.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Clear',
                            onPressed: () {
                              modifiedBy.value = '';
                              modifiedByController.clear();
                            },
                          )
                        : const Icon(Icons.arrow_drop_down),
                    isDense: true,
                  ),
                )),
            const SizedBox(height: 8),
          ],
        ));
  }
}
