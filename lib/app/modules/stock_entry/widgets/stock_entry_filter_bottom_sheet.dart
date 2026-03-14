import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/stock_entry/stock_entry_controller.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';

// ---------------------------------------------------------------------------
// Frappe / ERPNext canonical docstatus colours — kept in sync with
// GenericDocumentCard._statusAccentColor and StatusPill.
// ---------------------------------------------------------------------------
const _kDraftColor     = Color(0xFFE54D4D); // Frappe danger red
const _kSubmittedColor = Color(0xFF36A564); // Frappe success green
const _kCancelledColor = Color(0xFF5A6673); // Frappe muted grey

class StockEntryFilterBottomSheet extends StatefulWidget {
  const StockEntryFilterBottomSheet({super.key});

  @override
  State<StockEntryFilterBottomSheet> createState() =>
      _StockEntryFilterBottomSheetState();
}

class _StockEntryFilterBottomSheetState
    extends State<StockEntryFilterBottomSheet> {
  final StockEntryController controller = Get.find();

  late TextEditingController fromWarehouseController;
  late TextEditingController referenceController;
  late TextEditingController dateRangeController;
  late TextEditingController ownerController;
  late TextEditingController modifiedByController;

  // Display name observables (email stored separately as filter value)
  final ownerDisplayName      = ''.obs;
  final modifiedByDisplayName = ''.obs;

  // Reactive state
  final selectedDocstatus      = RxnInt();
  final selectedStockEntryType = RxnString();
  final startDate              = Rxn<DateTime>();
  final endDate                = Rxn<DateTime>();

  // Reactive mirrors for active count
  final fromWarehouse = ''.obs;
  final reference     = ''.obs;
  final owner         = ''.obs;
  final modifiedBy    = ''.obs;

  @override
  void initState() {
    super.initState();

    final initialFromWarehouse = _extractFilterValue('from_warehouse');
    final initialRef           = _extractFilterValue('custom_reference_no');
    final initialOwner         = _extractFilterValue('owner');
    final initialModifiedBy    = _extractFilterValue('modified_by');

    fromWarehouseController = TextEditingController(text: initialFromWarehouse);
    referenceController     = TextEditingController(text: initialRef);
    ownerController         = TextEditingController();
    modifiedByController    = TextEditingController();
    dateRangeController     = TextEditingController();

    fromWarehouse.value = initialFromWarehouse;
    reference.value     = initialRef;
    owner.value         = initialOwner;
    modifiedBy.value    = initialModifiedBy;

    selectedDocstatus.value      = controller.activeFilters['docstatus'];
    selectedStockEntryType.value = controller.activeFilters['stock_entry_type'];

    // Resolve owner email → display name on open
    if (initialOwner.isNotEmpty) {
      final match = controller.users.firstWhereOrNull(
        (u) => u.email == initialOwner || u.id == initialOwner,
      );
      final display =
          (match != null && match.name.isNotEmpty) ? match.name : initialOwner;
      ownerController.text      = display;
      ownerDisplayName.value    = display;
    }

    // Resolve modifiedBy email → display name on open
    if (initialModifiedBy.isNotEmpty) {
      final match = controller.users.firstWhereOrNull(
        (u) => u.email == initialModifiedBy || u.id == initialModifiedBy,
      );
      final display = (match != null && match.name.isNotEmpty)
          ? match.name
          : initialModifiedBy;
      modifiedByController.text   = display;
      modifiedByDisplayName.value = display;
    }

    // Restore date range — now stored under posting_date
    final dateFilter = controller.activeFilters['posting_date'];
    if (dateFilter is List &&
        dateFilter.isNotEmpty &&
        dateFilter[0] == 'between') {
      final dates = dateFilter[1] as List;
      if (dates.length >= 2) {
        dateRangeController.text = '${dates[0]} - ${dates[1]}';
        try {
          startDate.value = DateTime.parse(dates[0]);
          endDate.value   = DateTime.parse(dates[1]);
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
    fromWarehouseController.dispose();
    referenceController.dispose();
    dateRangeController.dispose();
    ownerController.dispose();
    modifiedByController.dispose();
    super.dispose();
  }

  int get _activeCount {
    int count = 0;
    if (selectedDocstatus.value != null)      count++;
    if (selectedStockEntryType.value != null) count++;
    if (fromWarehouse.value.isNotEmpty)       count++;
    if (reference.value.isNotEmpty)           count++;
    if (owner.value.isNotEmpty)               count++;
    if (modifiedBy.value.isNotEmpty)          count++;
    if (startDate.value != null && endDate.value != null) count++;
    return count;
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      // Allow up to 30 days ahead — ERPNext permits future posting dates
      lastDate: DateTime.now().add(const Duration(days: 30)),
      initialDateRange: startDate.value != null && endDate.value != null
          ? DateTimeRange(start: startDate.value!, end: endDate.value!)
          : null,
      helpText: 'Select Posting Date Range',
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
  // Generic user picker — reused for both Owner and Modified By.
  // Stores email/id as filter value; shows display name in the text field.
  // ---------------------------------------------------------------------------
  void _showUserPicker({
    required String title,
    required void Function(String userId, String displayName) onSelected,
  }) {
    final searchController = TextEditingController();
    final RxList<User> filteredUsers = RxList<User>(controller.users);

    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            final colorScheme = Theme.of(context).colorScheme;
            return Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16.0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleLarge),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: Get.back),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
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
                        final term = val.toLowerCase();
                        filteredUsers.assignAll(
                          controller.users.where((u) =>
                              u.name.toLowerCase().contains(term) ||
                              u.email.toLowerCase().contains(term)),
                        );
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
                          final userId =
                              user.email.isNotEmpty ? user.email : user.id;
                          final displayName =
                              user.name.isNotEmpty ? user.name : userId;
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
                            subtitle: Text(user.email),
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

  void _applyFilters() {
    final filters = <String, dynamic>{};

    if (selectedDocstatus.value != null)
      filters['docstatus'] = selectedDocstatus.value;
    if (selectedStockEntryType.value != null)
      filters['stock_entry_type'] = selectedStockEntryType.value;
    if (fromWarehouseController.text.isNotEmpty)
      filters['from_warehouse'] = [
        'like',
        '%${fromWarehouseController.text}%'
      ];
    if (referenceController.text.isNotEmpty)
      filters['custom_reference_no'] = [
        'like',
        '%${referenceController.text}%'
      ];
    if (owner.value.isNotEmpty)
      filters['owner'] = owner.value;
    if (modifiedBy.value.isNotEmpty)
      filters['modified_by'] = modifiedBy.value;

    // Filter on posting_date — the warehouse movement date, not creation time
    if (startDate.value != null && endDate.value != null) {
      filters['posting_date'] = [
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

  // ---------------------------------------------------------------------------
  // Frappe-coloured docstatus chip helper.
  // Selected state uses the canonical Frappe palette instead of generic M3.
  // ---------------------------------------------------------------------------
  Widget _statusChip({
    required int value,
    required String label,
    required Color frappeColor,
  }) {
    final isSelected = selectedDocstatus.value == value;
    // Derive a light background (10% opacity) from the Frappe colour
    final bgColor    = frappeColor.withOpacity(0.12);
    final labelColor = isSelected ? frappeColor : Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) =>
            selectedDocstatus.value = isSelected ? null : value,
        showCheckmark: false,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        selectedColor: bgColor,
        side: BorderSide(
          color: isSelected ? frappeColor : Theme.of(context).colorScheme.outline,
          width: isSelected ? 1.5 : 1.0,
        ),
        labelStyle: TextStyle(
          color: labelColor,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        avatar: isSelected
            ? Icon(Icons.circle, size: 8, color: frappeColor)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme        = Theme.of(context);
    final colorScheme  = theme.colorScheme;

    return Obx(() => GlobalFilterBottomSheet(
          title: 'Filter Stock Entries',
          activeFilterCount: _activeCount,
          sortOptions: const [
            // posting_date first — most meaningful for warehouse staff
            SortOption('Posting Date', 'posting_date'),
            SortOption('Creation',     'creation'),
            SortOption('Modified',     'modified'),
          ],
          currentSortField: controller.sortField.value,
          currentSortOrder: controller.sortOrder.value,
          onSortChanged: (field, order) => controller.setSort(field, order),
          onApply: _applyFilters,
          onClear: () {
            selectedDocstatus.value      = null;
            selectedStockEntryType.value = null;
            fromWarehouseController.clear();
            referenceController.clear();
            ownerController.clear();
            modifiedByController.clear();
            dateRangeController.clear();
            startDate.value             = null;
            endDate.value               = null;
            fromWarehouse.value         = '';
            reference.value             = '';
            owner.value                 = '';
            modifiedBy.value            = '';
            ownerDisplayName.value      = '';
            modifiedByDisplayName.value = '';
            controller.clearFilters();
          },
          filterWidgets: [
            // ── Status (Frappe-coloured chips) ─────────────────────────────
            Text('Status', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Obx(() => Row(
                children: [
                  _statusChip(
                    value: 0,
                    label: 'Draft',
                    frappeColor: _kDraftColor,
                  ),
                  _statusChip(
                    value: 1,
                    label: 'Submitted',
                    frappeColor: _kSubmittedColor,
                  ),
                  _statusChip(
                    value: 2,
                    label: 'Cancelled',
                    frappeColor: _kCancelledColor,
                  ),
                ],
              )),
            ),
            const SizedBox(height: 16),

            // ── Entry Type chips ───────────────────────────────────────────
            Text('Entry Type', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.white,
                  Colors.white,
                  Colors.white.withOpacity(0.0),
                ],
                stops: const [0.0, 0.75, 1.0],
              ).createShader(bounds),
              blendMode: BlendMode.dstIn,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ...controller.stockEntryTypes.map((type) => Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(type),
                            selected: selectedStockEntryType.value == type,
                            onSelected: (selected) =>
                                selectedStockEntryType.value =
                                    selected ? type : null,
                          ),
                        )),
                    const SizedBox(width: 32),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Posting Date range ─────────────────────────────────────────
            // Uses posting_date (warehouse movement date), not creation time.
            TextFormField(
              controller: dateRangeController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Posting Date Range',
                hintText: 'Tap to select',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
                isDense: true,
              ),
              onTap: _pickDateRange,
            ),
            const SizedBox(height: 16),

            // ── Source warehouse (replaces free-text purpose) ──────────────
            // from_warehouse is the meaningful differentiator within a type.
            TextFormField(
              controller: fromWarehouseController,
              decoration: const InputDecoration(
                labelText: 'Source Warehouse',
                hintText: 'e.g. Main Store - DXB',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.warehouse_outlined),
                isDense: true,
              ),
              onChanged: (val) => fromWarehouse.value = val,
            ),
            const SizedBox(height: 16),

            // ── Reference No ───────────────────────────────────────────────
            TextFormField(
              controller: referenceController,
              decoration: const InputDecoration(
                labelText: 'Reference No',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.tag),
                isDense: true,
              ),
              onChanged: (val) => reference.value = val,
            ),
            const SizedBox(height: 16),

            // ── Owner (Created By) ─────────────────────────────────────────
            Obx(() => TextFormField(
                  controller: ownerController,
                  readOnly: true,
                  onTap: () => _showUserPicker(
                    title: 'Select Owner',
                    onSelected: (userId, displayName) {
                      owner.value           = userId;
                      ownerController.text  = displayName;
                      ownerDisplayName.value = displayName;
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
                              owner.value           = '';
                              ownerController.clear();
                              ownerDisplayName.value = '';
                            },
                          )
                        : const Icon(Icons.arrow_drop_down),
                    isDense: true,
                  ),
                )),
            const SizedBox(height: 16),

            // ── Modified By ────────────────────────────────────────────────
            Obx(() => TextFormField(
                  controller: modifiedByController,
                  readOnly: true,
                  onTap: () => _showUserPicker(
                    title: 'Select Modified By',
                    onSelected: (userId, displayName) {
                      modifiedBy.value           = userId;
                      modifiedByController.text  = displayName;
                      modifiedByDisplayName.value = displayName;
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
                              modifiedBy.value           = '';
                              modifiedByController.clear();
                              modifiedByDisplayName.value = '';
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
