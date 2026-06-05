import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/packing_slip/packing_slip_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';

class PackingSlipFilterBottomSheet extends StatefulWidget {
  const PackingSlipFilterBottomSheet({super.key});

  @override
  State<PackingSlipFilterBottomSheet> createState() =>
      _PackingSlipFilterBottomSheetState();
}

class _PackingSlipFilterBottomSheetState
    extends State<PackingSlipFilterBottomSheet> {
  final PackingSlipController _ctrl = Get.find();

  // Local reactive state — committed only on Apply
  final _deliveryNote = ''.obs;
  final _poNo = ''.obs;
  final _status = RxnString();
  final _startDate = Rxn<DateTime>();
  final _endDate = Rxn<DateTime>();

  late TextEditingController _dateRangeController;

  @override
  void initState() {
    super.initState();
    _dateRangeController = TextEditingController();

    final af = _ctrl.activeFilters;

    // Restore Delivery Note
    final dn = af['delivery_note'];
    if (dn is List && dn.length == 2 && dn[0] == 'like') {
      _deliveryNote.value = dn[1].toString().replaceAll('%', '');
    }

    // Restore PO No
    final po = af['custom_po_no'];
    if (po is List && po.length == 2 && po[0] == 'like') {
      _poNo.value = po[1].toString().replaceAll('%', '');
    }

    // Restore Status
    _status.value = af['status'] as String?;

    // Restore Date Range
    final creation = af['creation'];
    if (creation is List &&
        creation.length == 2 &&
        creation[0] == 'between' &&
        creation[1] is List) {
      final dates = creation[1] as List;
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

  // ── Generic searchable bottom-sheet picker ─────────────────────────────────

  void _showSearchPicker({
    required BuildContext context,
    required String title,
    required String hintText,
    required Future<List<_PickerItem>> Function(String query) searcher,
    required void Function(String value) onSelected,
  }) {
    final results = <_PickerItem>[].obs;
    final isLoading = false.obs;

    () async {
      isLoading.value = true;
      results.value = await searcher('');
      isLoading.value = false;
    }();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (ctx2, scrollCtrl) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: hintText,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: (val) async {
                  isLoading.value = true;
                  results.value = await searcher(val);
                  isLoading.value = false;
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Obx(() {
                  if (isLoading.value) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (results.isEmpty) {
                    return const Center(child: Text('No results'));
                  }
                  return ListView.separated(
                    controller: scrollCtrl,
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final item = results[i];
                      return ListTile(
                        title: Text(item.label),
                        subtitle: item.subtitle != null
                            ? Text(item.subtitle!,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey))
                            : null,
                        onTap: () {
                          onSelected(item.value);
                          Navigator.of(ctx).pop();
                        },
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Searcher helpers ───────────────────────────────────────────────────────

  Future<List<_PickerItem>> _searchDNs(String q) async {
    try {
      final res = await _ctrl.packingSlipProvider.searchDeliveryNotes(q);
      if (res.statusCode == 200 && res.data['data'] != null) {
        return (res.data['data'] as List).map((e) {
          final name = e['name'] as String? ?? '';
          final customer = e['customer'] as String? ?? '';
          final po = e['po_no'] as String? ?? '';
          return _PickerItem(
            value: name,
            label: name,
            subtitle: [customer, if (po.isNotEmpty) 'PO: $po']
                .where((s) => s.isNotEmpty)
                .join(' • '),
          );
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<_PickerItem>> _searchPOs(String q) async {
    try {
      final res = await _ctrl.packingSlipProvider.searchPONumbers(q);
      if (res.statusCode == 200 && res.data['data'] != null) {
        final seen = <String>{};
        final items = <_PickerItem>[];
        for (final e in res.data['data'] as List) {
          final po = e['custom_po_no'] as String? ?? '';
          if (po.isNotEmpty && seen.add(po)) {
            items.add(_PickerItem(value: po, label: po));
          }
        }
        return items;
      }
    } catch (_) {}
    return [];
  }

  // ── Date range picker ──────────────────────────────────────────────────────

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
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

  // ── Apply / Clear ──────────────────────────────────────────────────────────

  void _apply() {
    final filters = <String, dynamic>{};

    if (_deliveryNote.value.isNotEmpty) {
      filters['delivery_note'] = ['like', '%${_deliveryNote.value}%'];
    }
    if (_poNo.value.isNotEmpty) {
      filters['custom_po_no'] = ['like', '%${_poNo.value}%'];
    }
    // Status is sent as docstatus filter since 'status' is virtual.
    // Frappe Packing Slip: Draft=0, Submitted=1, Cancelled=2
    if (_status.value != null) {
      final docstatusMap = {'Draft': 0, 'Submitted': 1, 'Cancelled': 2};
      final ds = docstatusMap[_status.value];
      if (ds != null) filters['docstatus'] = ds;
    }
    if (_startDate.value != null && _endDate.value != null) {
      filters['creation'] = [
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
    _deliveryNote.value = '';
    _poNo.value = '';
    _status.value = null;
    _startDate.value = null;
    _endDate.value = null;
    _dateRangeController.clear();
    _ctrl.clearFilters();
    Get.back();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  int get _localFilterCount {
    int count = 0;
    if (_deliveryNote.value.isNotEmpty) count++;
    if (_poNo.value.isNotEmpty) count++;
    if (_status.value != null) count++;
    if (_startDate.value != null && _endDate.value != null) count++;
    return count;
  }

  Widget _pickerTile({
    required BuildContext context,
    required String label,
    required RxString value,
    required String hint,
    required IconData icon,
    required Future<List<_PickerItem>> Function(String) searcher,
  }) {
    return Obx(() => InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showSearchPicker(
            context: context,
            title: 'Select $label',
            hintText: 'Search $label…',
            searcher: searcher,
            onSelected: (v) => value.value = v,
          ),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              prefixIcon: Icon(icon),
              suffixIcon: value.value.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => value.value = '',
                    )
                  : const Icon(Icons.arrow_drop_down),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            child: Text(
              value.value.isNotEmpty ? value.value : hint,
              style: TextStyle(
                color: value.value.isNotEmpty
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                overflow: TextOverflow.ellipsis,
              ),
              maxLines: 1,
            ),
          ),
        ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Obx(() => GlobalFilterBottomSheet(
          title: 'Filter Packing Slips',
          activeFilterCount: _localFilterCount,
          // 'status' and 'from_case_no' removed — not real DB columns on
          // Packing Slip; using them in orderBy causes a Frappe FieldError.
          sortOptions: const [
            SortOption('Creation', 'creation'),
            SortOption('Modified', 'modified'),
            SortOption('Case No', 'from_case_no'),
          ],
          currentSortField: _ctrl.sortField.value,
          currentSortOrder: _ctrl.sortOrder.value,
          onSortChanged: _ctrl.setSort,
          onApply: _apply,
          onClear: _clear,
          filterWidgets: [
            const SizedBox(height: 16),

            // ── Delivery Note ────────────────────────────────────────────
            _pickerTile(
              context: context,
              label: 'Delivery Note',
              value: _deliveryNote,
              hint: 'All Delivery Notes',
              icon: Icons.local_shipping_outlined,
              searcher: _searchDNs,
            ),
            const SizedBox(height: 12),

            // ── PO No ────────────────────────────────────────────────────
            _pickerTile(
              context: context,
              label: 'PO No',
              value: _poNo,
              hint: 'All PO Numbers',
              icon: Icons.receipt_long_outlined,
              searcher: _searchPOs,
            ),
            const SizedBox(height: 16),

            // ── Status ───────────────────────────────────────────────────
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Status',
                  style: Theme.of(context).textTheme.labelLarge),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['Draft', 'Submitted', 'Cancelled'].map((s) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Obx(() => ChoiceChip(
                          label: Text(s),
                          selected: _status.value == s,
                          onSelected: (selected) =>
                              _status.value = selected ? s : null,
                        )),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // ── Creation Date Range ──────────────────────────────────────
            TextFormField(
              controller: _dateRangeController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Creation Date Range',
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

// ── Internal picker data model ─────────────────────────────────────────────

class _PickerItem {
  final String value;
  final String label;
  final String? subtitle;
  const _PickerItem(
      {required this.value, required this.label, this.subtitle});
}
