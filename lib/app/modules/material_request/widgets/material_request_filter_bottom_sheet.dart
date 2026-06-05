import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/modules/material_request/material_request_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';

/// Filter bottom sheet for Material Request List View.
///
/// Mirrors [StockEntryFilterBottomSheet] exactly:
///   • Uses [GlobalFilterBottomSheet] shell (Sort + Filter header, sticky Apply)
///   • Status via docstatus ChoiceChips (Draft/Submitted/Cancelled)
///   • Request Type ChoiceChips
///   • Date Range picker
///   • Owner text field + user picker sheet
class MaterialRequestFilterBottomSheet extends StatefulWidget {
  const MaterialRequestFilterBottomSheet({super.key});

  @override
  State<MaterialRequestFilterBottomSheet> createState() =>
      _MaterialRequestFilterBottomSheetState();
}

class _MaterialRequestFilterBottomSheetState
    extends State<MaterialRequestFilterBottomSheet> {
  final MaterialRequestController controller =
      Get.find<MaterialRequestController>();

  late TextEditingController dateRangeController;
  late TextEditingController ownerController;

  final selectedDocstatus = RxnInt();
  final selectedType = RxnString();
  final startDate = Rxn<DateTime>();
  final endDate = Rxn<DateTime>();
  final owner = ''.obs;

  static const _types = [
    'Purchase',
    'Material Transfer',
    'Material Issue',
    'Manufacture',
    'Customer Provided',
  ];

  @override
  void initState() {
    super.initState();

    final initialOwner = _extractFilterValue('owner');
    ownerController = TextEditingController(text: initialOwner);
    dateRangeController = TextEditingController();
    owner.value = initialOwner;

    selectedDocstatus.value = controller.activeFilters['docstatus'];
    selectedType.value =
        controller.activeFilters['material_request_type']?.toString();

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

  String _extractFilterValue(String key) {
    final val = controller.activeFilters[key];
    if (val is List && val.isNotEmpty && val[0] == 'like') {
      return val[1].toString().replaceAll('%', '');
    }
    if (val is String) return val;
    return '';
  }

  @override
  void dispose() {
    dateRangeController.dispose();
    ownerController.dispose();
    super.dispose();
  }

  int get _activeCount {
    int count = 0;
    if (selectedDocstatus.value != null) count++;
    if (selectedType.value != null) count++;
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
      dateRangeController.text =
          '${DateFormat('yyyy-MM-dd').format(startDate.value!)} - ${DateFormat('yyyy-MM-dd').format(endDate.value!)}';
    }
  }

  void _showUserPicker() {
    final searchCtrl = TextEditingController();
    final RxList<User> filteredUsers = RxList<User>(controller.users);

    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16.0),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16.0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select Owner',
                          style: Theme.of(context).textTheme.titleLarge),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Get.back()),
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
                      if (val.isEmpty) {
                        filteredUsers.assignAll(controller.users);
                      } else {
                        filteredUsers.assignAll(controller.users.where((u) {
                          final n = u.name.toLowerCase();
                          final e = u.email.toLowerCase();
                          final t = val.toLowerCase();
                          return n.contains(t) || e.contains(t);
                        }));
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Obx(() {
                      if (controller.isFetchingUsers.value) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (filteredUsers.isEmpty) {
                        return const Center(child: Text('No users found'));
                      }
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: filteredUsers.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final user = filteredUsers[index];
                          final userId = user.email.isNotEmpty
                              ? user.email
                              : user.id;
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(user.name.isNotEmpty
                                  ? user.name[0]
                                  : 'U'),
                            ),
                            title: Text(user.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(user.email),
                            onTap: () {
                              ownerController.text = userId;
                              owner.value = userId;
                              Get.back();
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

  void _applyFilters() {
    final filters = <String, dynamic>{};

    if (selectedDocstatus.value != null) {
      filters['docstatus'] = selectedDocstatus.value;
    }
    if (selectedType.value != null) {
      filters['material_request_type'] = selectedType.value;
    }
    if (ownerController.text.isNotEmpty) {
      filters['owner'] = ownerController.text;
    }
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
    return Obx(() => GlobalFilterBottomSheet(
          title: 'Filter Requests',
          activeFilterCount: _activeCount,
          sortOptions: const [
            SortOption('Creation', 'creation'),
            SortOption('Modified', 'modified'),
            SortOption('Schedule Date', 'schedule_date'),
          ],
          currentSortField: controller.sortField.value,
          currentSortOrder: controller.sortOrder.value,
          onSortChanged: (field, order) =>
              controller.setSort(field, order),
          onApply: _applyFilters,
          onClear: () {
            selectedDocstatus.value = null;
            selectedType.value = null;
            ownerController.clear();
            dateRangeController.clear();
            startDate.value = null;
            endDate.value = null;
            owner.value = '';
            controller.clearFilters();
          },
          filterWidgets: [
            // ── Status ─────────────────────────────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Status',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final entry in {
                        0: 'Draft',
                        1: 'Submitted',
                        2: 'Cancelled'
                      }.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(entry.value),
                            selected:
                                selectedDocstatus.value == entry.key,
                            onSelected: (bool selected) {
                              selectedDocstatus.value =
                                  selected ? entry.key : null;
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Request Type ───────────────────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Request Type',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _types.map((t) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(t),
                          selected: selectedType.value == t,
                          onSelected: (bool selected) {
                            selectedType.value = selected ? t : null;
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Date Range ──────────────────────────────────────────────────
            TextFormField(
              controller: dateRangeController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Date Range',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
                isDense: true,
              ),
              onTap: _pickDateRange,
            ),
            const SizedBox(height: 16),

            // ── Owner ──────────────────────────────────────────────────────────
            TextFormField(
              controller: ownerController,
              readOnly: true,
              onTap: _showUserPicker,
              decoration: const InputDecoration(
                labelText: 'Owner',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
                suffixIcon: Icon(Icons.arrow_drop_down),
                isDense: true,
              ),
            ),
          ],
        ));
  }
}
