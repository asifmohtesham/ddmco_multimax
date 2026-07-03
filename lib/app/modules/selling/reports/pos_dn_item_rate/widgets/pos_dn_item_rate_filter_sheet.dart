import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';

/// Opens the POS & DN Item Rate filter editor as a scrollable bottom sheet.
/// Reads/writes the controller's reactive filter state; multi-select link
/// filters render as removable chips fed by a searchable picker.
void showPosDnItemRateFilterSheet(
    BuildContext context, PosDnItemRateController c) {
  Get.bottomSheet(
    _PosDnFilterSheet(c: c),
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
      _LinkSearchSheet(
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
                _MultiLinkSection(
                  label: 'POS Uploads',
                  values: c.posUploads,
                  onAdd: () => _pickLink(
                    doctype: 'POS Upload',
                    title: 'Select POS Upload',
                    onSelected: (v) => c.addTo(c.posUploads, v),
                  ),
                  onRemove: (v) => c.removeFrom(c.posUploads, v),
                ),
                _MultiLinkSection(
                  label: 'Customers',
                  values: c.customers,
                  onAdd: () => _pickLink(
                    doctype: 'Customer',
                    title: 'Select Customer',
                    onSelected: (v) => c.addTo(c.customers, v),
                  ),
                  onRemove: (v) => c.removeFrom(c.customers, v),
                ),
                _MultiLinkSection(
                  label: 'Customer Groups',
                  values: c.customerGroups,
                  onAdd: () => _pickLink(
                    doctype: 'Customer Group',
                    title: 'Select Customer Group',
                    onSelected: (v) => c.addTo(c.customerGroups, v),
                  ),
                  onRemove: (v) => c.removeFrom(c.customerGroups, v),
                ),
                _MultiLinkSection(
                  label: 'Item Groups',
                  values: c.itemGroups,
                  onAdd: () => _pickLink(
                    doctype: 'Item Group',
                    title: 'Select Item Group',
                    onSelected: (v) => c.addTo(c.itemGroups, v),
                  ),
                  onRemove: (v) => c.removeFrom(c.itemGroups, v),
                ),
                const SizedBox(height: 8),

                // ── Dates ───────────────────────────────────────────────
                Obx(() => _DateRow(
                      label: 'From Date',
                      value: c.fromDate.value,
                      onTap: () => _pickDate(c.fromDate),
                      onClear: () => c.fromDate.value = null,
                    )),
                const SizedBox(height: 12),
                Obx(() => _DateRow(
                      label: 'To Date',
                      value: c.toDate.value,
                      onTap: () => _pickDate(c.toDate),
                      onClear: () => c.toDate.value = null,
                    )),
                const SizedBox(height: 8),

                // ── Switches ────────────────────────────────────────────
                Obx(() => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show already-mapped'),
                      value: c.showMapped.value,
                      onChanged: (v) => c.showMapped.value = v,
                    )),
                Obx(() => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Only lines with a customer code'),
                      value: c.onlyCoded.value,
                      onChanged: (v) => c.onlyCoded.value = v,
                    )),
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

/// A searchable, debounced single-select picker backed by an async name
/// search (same pattern as the BOM Stock filter sheet).
class _LinkSearchSheet extends StatefulWidget {
  final String title;
  final Future<List<String>> Function(String query) onSearch;
  final ValueChanged<String> onSelected;
  const _LinkSearchSheet({
    required this.title,
    required this.onSearch,
    required this.onSelected,
  });

  @override
  State<_LinkSearchSheet> createState() => _LinkSearchSheetState();
}

class _LinkSearchSheetState extends State<_LinkSearchSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<String> _options = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run('');
    _searchCtrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(
          const Duration(milliseconds: 300), () => _run(_searchCtrl.text));
    });
  }

  Future<void> _run(String q) async {
    setState(() => _loading = true);
    final results = await widget.onSearch(q);
    if (!mounted) return;
    setState(() {
      _options = results;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Text(widget.title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _options.isEmpty
                    ? const Center(child: Text('No matches'))
                    : ListView.separated(
                        itemCount: _options.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) => ListTile(
                          title: Text(_options[i]),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            widget.onSelected(_options[i]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
