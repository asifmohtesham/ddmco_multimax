import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/filter_focus.dart';
import 'package:multimax/app/modules/global_widgets/link_search_sheet.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';

/// Opens the POS & DN Item Rate filter editor as a scrollable bottom sheet.
/// Reads/writes the controller's reactive filter state; multi-select link
/// filters render as removable chips fed by a searchable picker.
/// [focusKey] (an `activeFilters` key) opens the sheet on that filter, ready
/// to edit: a link list opens its picker, a date its date picker, a switch
/// scrolls into view.
void showPosDnItemRateFilterSheet(
    BuildContext context, PosDnItemRateController c, {String? focusKey}) {
  Get.bottomSheet(
    FilterFocusScope.wrap(_PosDnFilterSheet(c: c), focusKey: focusKey),
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
  );
}

class _PosDnFilterSheet extends StatefulWidget {
  final PosDnItemRateController c;
  const _PosDnFilterSheet({required this.c});

  @override
  State<_PosDnFilterSheet> createState() => _PosDnFilterSheetState();
}

class _PosDnFilterSheetState extends State<_PosDnFilterSheet> {
  PosDnItemRateController get c => widget.c;

  Future<void> _pickLink({
    required String doctype,
    required String title,
    required ValueChanged<String> onSelected,
  }) async {
    await Get.bottomSheet(
      LinkSearchSheet(
        title: title,
        onSearch: (q) =>
            Get.find<ApiProvider>().searchLinkOptions(doctype, query: q),
        onSelected: onSelected,
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _pickDate(RxnString target) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(target.value ?? '') ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      target.value = '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }

  void _addPosUpload() => _pickLink(
        doctype: 'POS Upload',
        title: 'Select POS Upload',
        onSelected: (v) => c.addTo(c.posUploads, v),
      );

  void _addCustomer() => _pickLink(
        doctype: 'Customer',
        title: 'Select Customer',
        onSelected: (v) => c.addTo(c.customers, v),
      );

  void _addCustomerGroup() => _pickLink(
        doctype: 'Customer Group',
        title: 'Select Customer Group',
        onSelected: (v) => c.addTo(c.customerGroups, v),
      );

  void _addItemGroup() => _pickLink(
        doctype: 'Item Group',
        title: 'Select Item Group',
        onSelected: (v) => c.addTo(c.itemGroups, v),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Filters',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  c.clearFilters();
                  setState(() {});
                },
                child: const Text('Clear Filters'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                FilterFocusTarget(
                  filterKey: 'pos_upload',
                  onActivate: _addPosUpload,
                  child: _MultiLinkSection(
                  label: 'POS Uploads',
                  values: c.posUploads,
                  onAdd: _addPosUpload,
                  onRemove: (v) => c.removeFrom(c.posUploads, v),
                )),
                FilterFocusTarget(
                  filterKey: 'customer',
                  onActivate: _addCustomer,
                  child: _MultiLinkSection(
                  label: 'Customers',
                  values: c.customers,
                  onAdd: _addCustomer,
                  onRemove: (v) => c.removeFrom(c.customers, v),
                )),
                FilterFocusTarget(
                  filterKey: 'customer_group',
                  onActivate: _addCustomerGroup,
                  child: _MultiLinkSection(
                  label: 'Customer Groups',
                  values: c.customerGroups,
                  onAdd: _addCustomerGroup,
                  onRemove: (v) => c.removeFrom(c.customerGroups, v),
                )),
                FilterFocusTarget(
                  filterKey: 'item_group',
                  onActivate: _addItemGroup,
                  child: _MultiLinkSection(
                  label: 'Item Groups',
                  values: c.itemGroups,
                  onAdd: _addItemGroup,
                  onRemove: (v) => c.removeFrom(c.itemGroups, v),
                )),
                const SizedBox(height: 8),

                // ── Dates ───────────────────────────────────────────────
                FilterFocusTarget(
                  filterKey: 'from_date',
                  onActivate: () => _pickDate(c.fromDate),
                  child: Obx(() => _DateRow(
                      label: 'From Date',
                      value: c.fromDate.value,
                      onTap: () => _pickDate(c.fromDate),
                      onClear: () => c.fromDate.value = null,
                    ))),
                const SizedBox(height: 12),
                FilterFocusTarget(
                  filterKey: 'to_date',
                  onActivate: () => _pickDate(c.toDate),
                  child: Obx(() => _DateRow(
                      label: 'To Date',
                      value: c.toDate.value,
                      onTap: () => _pickDate(c.toDate),
                      onClear: () => c.toDate.value = null,
                    ))),
                const SizedBox(height: 8),

                // ── Switches ────────────────────────────────────────────
                // Each SwitchListTile gets a transparent Material so its ink +
                // background paint above the sheet's colour-painted Container
                // instead of being hidden by it.
                FilterFocusTarget(
                  filterKey: 'show_mapped',
                  child: Obx(() => Material(
                      color: Colors.transparent,
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Show already-mapped'),
                        value: c.showMapped.value,
                        onChanged: (v) => c.showMapped.value = v,
                      ),
                    ))),
                FilterFocusTarget(
                  filterKey: 'only_coded',
                  child: Obx(() => Material(
                      color: Colors.transparent,
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Only lines with a customer code'),
                        value: c.onlyCoded.value,
                        onChanged: (v) => c.onlyCoded.value = v,
                      ),
                    ))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Run Report'),
                onPressed: () {
                  Navigator.of(context).pop();
                  c.runReport();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Label + removable value chips + an "Add" affordance for one multi-select
/// link filter.
class _MultiLinkSection extends StatelessWidget {
  final String label;
  final RxList<String> values;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  const _MultiLinkSection({
    required this.label,
    required this.values,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Obx(() => Wrap(
                spacing: 6,
                runSpacing: 4,
                children: values
                    .map((v) => InputChip(
                          label: Text(v),
                          onDeleted: () => onRemove(v),
                        ))
                    .toList(),
              )),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text('Add ${label.toLowerCase()}'),
              onPressed: onAdd,
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only date field: tap to pick, clear icon to unset.
class _DateRow extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback onClear;
  const _DateRow({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: TextEditingController(text: value ?? ''),
      readOnly: true,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.calendar_today_outlined),
        suffixIcon: (value ?? '').isEmpty
            ? const Icon(Icons.edit_calendar_outlined, size: 18)
            : IconButton(
                icon: const Icon(Icons.clear, size: 18),
                tooltip: 'Clear',
                onPressed: onClear,
              ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}
