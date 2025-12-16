import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/stock_entry/stock_entry_controller.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';

class StockEntryFilterBottomSheet extends StatefulWidget {
  const StockEntryFilterBottomSheet({super.key});

  @override
  State<StockEntryFilterBottomSheet> createState() => _StockEntryFilterBottomSheetState();
}

class _StockEntryFilterBottomSheetState extends State<StockEntryFilterBottomSheet> {
  final StockEntryController controller = Get.find();

  late TextEditingController purposeController;
  late TextEditingController referenceController;
  late TextEditingController dateRangeController;
  late TextEditingController ownerController;

  // Reactive State
  final selectedDocstatus = RxnInt();
  final selectedStockEntryType = RxnString();
  final startDate = Rxn<DateTime>();
  final endDate = Rxn<DateTime>();

  // Reactive mirrors for count
  final purpose = ''.obs;
  final reference = ''.obs;
  final owner = ''.obs;

  @override
  void initState() {
    super.initState();

    String initialPurpose = _extractFilterValue('purpose');
    String initialRef = _extractFilterValue('custom_reference_no');
    String initialOwner = _extractFilterValue('owner');

    purposeController = TextEditingController(text: initialPurpose);
    referenceController = TextEditingController(text: initialRef);
    ownerController = TextEditingController(text: initialOwner);
    dateRangeController = TextEditingController();

    purpose.value = initialPurpose;
    reference.value = initialRef;
    owner.value = initialOwner;
    selectedDocstatus.value = controller.activeFilters['docstatus'];
    selectedStockEntryType.value = controller.activeFilters['stock_entry_type'];

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
    purposeController.dispose();
    referenceController.dispose();
    dateRangeController.dispose();
    ownerController.dispose();
    super.dispose();
  }

  int get _activeCount {
    int count = 0;
    if (selectedDocstatus.value != null) count++;
    if (selectedStockEntryType.value != null) count++;
    if (purpose.value.isNotEmpty) count++;
    if (reference.value.isNotEmpty) count++;
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

  void _showUserPicker() {
    final searchController = TextEditingController();
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
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select Owner', style: Theme.of(context).textTheme.titleLarge),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Get.back()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: "Search users...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (val) {
                      if (val.isEmpty) {
                        filteredUsers.assignAll(controller.users);
                      } else {
                        filteredUsers.assignAll(controller.users.where((user) {
                          final name = user.name.toLowerCase();
                          final email = user.email.toLowerCase();
                          final term = val.toLowerCase();
                          return name.contains(term) || email.contains(term);
                        }).toList());
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Obx(() {
                      if (controller.isFetchingUsers.value) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (filteredUsers.isEmpty) {
                        return const Center(child: Text("No users found"));
                      }
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: filteredUsers.length,
                        separatorBuilder: (c, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final user = filteredUsers[index];
                          final userId = user.email.isNotEmpty ? user.email : user.id;
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(user.name.isNotEmpty ? user.name[0] : 'U'),
                            ),
                            title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
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

    if (selectedDocstatus.value != null) filters['docstatus'] = selectedDocstatus.value;
    if (selectedStockEntryType.value != null) filters['stock_entry_type'] = selectedStockEntryType.value;
    if (purposeController.text.isNotEmpty) filters['purpose'] = ['like', '%${purposeController.text}%'];
    if (referenceController.text.isNotEmpty) filters['custom_reference_no'] = ['like', '%${referenceController.text}%'];
    if (ownerController.text.isNotEmpty) filters['owner'] = ownerController.text;

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
      title: 'Filter Stock Entries',
      activeFilterCount: _activeCount,
      sortOptions: const [
        SortOption('Creation', 'creation'),
        SortOption('Modified', 'modified'),
        SortOption('Purpose', 'purpose'),
      ],
      currentSortField: controller.sortField.value,
      currentSortOrder: controller.sortOrder.value,
      onSortChanged: (field, order) => controller.setSort(field, order),
      onApply: _applyFilters,
      onClear: () {
        selectedDocstatus.value = null;
        selectedStockEntryType.value = null;
        purposeController.clear();
        referenceController.clear();
        ownerController.clear();
        dateRangeController.clear();
        startDate.value = null;
        endDate.value = null;
        purpose.value = '';
        reference.value = '';
        owner.value = '';
        controller.clearFilters();
      },
      filterWidgets: [
        // Status Chips (ERPNext Style)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in {0: 'Draft', 1: 'Submitted', 2: 'Cancelled'}.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(entry.value),
                        selected: selectedDocstatus.value == entry.key,
                        onSelected: (bool selected) {
                          selectedDocstatus.value = selected ? entry.key : null;
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Stock Entry Type Chips
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Entry Type', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: controller.stockEntryTypes.map((type) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(type),
                      selected: selectedStockEntryType.value == type,
                      onSelected: (bool selected) {
                        selectedStockEntryType.value = selected ? type : null;
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
            labelText: 'Date Range',
            border: OutlineInputBorder(),
            suffixIcon: Icon(Icons.calendar_today),
            isDense: true,
          ),
          onTap: _pickDateRange,
        ),
        TextFormField(
          controller: purposeController,
          decoration: const InputDecoration(labelText: 'Purpose', border: OutlineInputBorder(), isDense: true),
          onChanged: (val) => purpose.value = val,
        ),
        TextFormField(
          controller: referenceController,
          decoration: const InputDecoration(labelText: 'Reference No', border: OutlineInputBorder(), isDense: true),
          onChanged: (val) => reference.value = val,
        ),
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