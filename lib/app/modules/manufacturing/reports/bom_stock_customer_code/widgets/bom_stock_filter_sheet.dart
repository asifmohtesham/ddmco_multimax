import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/link_field_widget.dart';
import 'package:multimax/app/modules/global_widgets/warehouse_picker_sheet.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';

/// Opens the BOM Stock with Customer Code filter editor as a scrollable
/// bottom sheet. Reads/writes the controller's reactive filter state.
void showBomStockFilterSheet(
    BuildContext context, BomStockCustomerCodeController c) {
  c.loadWarehouseOptions();
  Get.bottomSheet(
    _BomStockFilterSheet(c: c),
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
  );
}

class _BomStockFilterSheet extends StatefulWidget {
  final BomStockCustomerCodeController c;
  const _BomStockFilterSheet({required this.c});

  @override
  State<_BomStockFilterSheet> createState() => _BomStockFilterSheetState();
}

class _BomStockFilterSheetState extends State<_BomStockFilterSheet> {
  late final TextEditingController _customerCtrl;
  late final TextEditingController _posCtrl;
  final TextEditingController _codeInput = TextEditingController();

  BomStockCustomerCodeController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _customerCtrl = TextEditingController(text: c.customer.value ?? '');
    _posCtrl = TextEditingController(text: c.posUpload.value ?? '');
  }

  @override
  void dispose() {
    _customerCtrl.dispose();
    _posCtrl.dispose();
    _codeInput.dispose();
    super.dispose();
  }

  Future<void> _pickLink({
    required String doctype,
    required String title,
    required ValueChanged<String?> onSelected,
  }) async {
    await Get.bottomSheet(
      _LinkSearchSheet(
        title: title,
        onSearch: (q) => Get.find<ApiProvider>().searchLinkOptions(doctype, query: q),
        onSelected: onSelected,
      ),
      isScrollControlled: true,
    );
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
                  _customerCtrl.clear();
                  _posCtrl.clear();
                  setState(() {});
                },
                child: const Text('Clear Filters'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                // ── Customer ────────────────────────────────────────────
                LinkFieldWidget(
                  controller: _customerCtrl,
                  labelText: 'Customer',
                  hintText: 'Select Customer',
                  prefixIcon: Icons.person_outline,
                  onTap: () => _pickLink(
                    doctype: 'Customer',
                    title: 'Select Customer',
                    onSelected: (v) {
                      c.customer.value = v;
                      _customerCtrl.text = v ?? '';
                      setState(() {});
                    },
                  ),
                  onClear: () {
                    c.customer.value = null;
                    _customerCtrl.clear();
                    setState(() {});
                  },
                ),
                const SizedBox(height: 16),

                // ── Customer Codes (chips) ──────────────────────────────
                _label('Customer Codes'),
                Obx(() => Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: c.customerCodes
                          .map((code) => InputChip(
                                label: Text(code),
                                onDeleted: () => c.removeCustomerCode(code),
                              ))
                          .toList(),
                    )),
                TextField(
                  controller: _codeInput,
                  decoration: const InputDecoration(
                    hintText: 'Type a code, press Enter to add',
                    isDense: true,
                  ),
                  onSubmitted: (v) {
                    for (final part in v.split(',')) {
                      c.addCustomerCode(part);
                    }
                    _codeInput.clear();
                  },
                ),
                Obx(() => c.discoveredCodes.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _hint('From results — tap to add', context),
                            Wrap(
                              spacing: 6,
                              children: c.discoveredCodes
                                  .map((code) => ActionChip(
                                        label: Text(code),
                                        onPressed: () => c.addCustomerCode(code),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ),
                      )),
                const SizedBox(height: 16),

                // ── Warehouses (chips) ──────────────────────────────────
                _label('Warehouses'),
                Obx(() => Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: c.warehouses
                          .map((wh) => InputChip(
                                label: Text(wh),
                                onDeleted: () => c.removeWarehouse(wh),
                              ))
                          .toList(),
                    )),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add warehouse'),
                    onPressed: () => Get.bottomSheet(
                      Obx(() => WarehousePickerSheet(
                            warehouses: c.warehouseOptions.toList(),
                            isLoading: c.isLoadingWarehouses.value,
                            onSelected: c.addWarehouse,
                          )),
                      isScrollControlled: true,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── POS Upload ──────────────────────────────────────────
                LinkFieldWidget(
                  controller: _posCtrl,
                  labelText: 'POS Upload',
                  hintText: 'Select POS Upload',
                  prefixIcon: Icons.cloud_upload_outlined,
                  onTap: () => _pickLink(
                    doctype: 'POS Upload',
                    title: 'Select POS Upload',
                    onSelected: (v) async {
                      _posCtrl.text = v ?? '';
                      setState(() {});
                      await c.onPosUploadSelected(v);
                    },
                  ),
                  onClear: () async {
                    _posCtrl.clear();
                    setState(() {});
                    await c.onPosUploadSelected(null);
                  },
                ),
                const SizedBox(height: 8),

                // ── Switches ────────────────────────────────────────────
                Obx(() => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show Exploded View'),
                      value: c.showExplodedView.value,
                      onChanged: (v) => c.showExplodedView.value = v,
                    )),
                Obx(() => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Hide Out of Stock'),
                      value: c.hideOutOfStock.value,
                      onChanged: (v) => c.hideOutOfStock.value = v,
                    )),
              ],
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

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      );

  Widget _hint(String s, BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(s, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
      );
}

/// A searchable, debounced single-select picker backed by an async name search.
class _LinkSearchSheet extends StatefulWidget {
  final String title;
  final Future<List<String>> Function(String query) onSearch;
  final ValueChanged<String?> onSelected;
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
      _debounce = Timer(const Duration(milliseconds: 300),
          () => _run(_searchCtrl.text));
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
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
