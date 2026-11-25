import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/filter_focus.dart';
import 'package:multimax/app/modules/global_widgets/link_field_widget.dart';
import 'package:multimax/app/modules/global_widgets/link_search_sheet.dart';
import 'package:multimax/app/modules/global_widgets/warehouse_picker_sheet.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';

/// Opens the BOM Stock with Customer Code filter editor as a scrollable
/// bottom sheet. Reads/writes the controller's reactive filter state.
/// [focusKey] (an `activeFilters` key) opens the sheet on that filter, ready
/// to edit: a link opens its picker, the codes field takes focus, a switch
/// scrolls into view.
void showBomStockFilterSheet(
    BuildContext context, BomStockCustomerCodeController c,
    {String? focusKey}) {
  c.loadWarehouseOptions();
  Get.bottomSheet(
    FilterFocusScope.wrap(_BomStockFilterSheet(c: c), focusKey: focusKey),
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
      LinkSearchSheet(
        title: title,
        onSearch: (q) => Get.find<ApiProvider>().searchLinkOptions(doctype, query: q),
        onSelected: onSelected,
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _pickCustomer() => _pickLink(
        doctype: 'Customer',
        title: 'Select Customer',
        onSelected: (v) {
          c.customer.value = v;
          _customerCtrl.text = v ?? '';
          setState(() {});
        },
      );

  Future<void> _addWarehouse() async {
    c.loadWarehouseOptions();
    await Get.bottomSheet(
      Obx(() => WarehousePickerSheet(
            warehouses: c.warehouseOptions.toList(),
            isLoading: c.isLoadingWarehouses.value,
            onSelected: (warehouse) {
              if (c.warehouseOptions.contains(warehouse)) {
                c.addWarehouse(warehouse);
              }
            },
          )),
      isScrollControlled: true,
    );
  }

  Future<void> _pickPosUpload() => _pickLink(
        doctype: 'POS Upload',
        title: 'Select POS Upload',
        onSelected: (v) async {
          _posCtrl.text = v ?? '';
          setState(() {});
          await c.onPosUploadSelected(v);
        },
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
                  _customerCtrl.clear();
                  _posCtrl.clear();
                  setState(() {});
                },
                child: const Text('Clear Filters'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Built eagerly (not a lazy ListView) so a filter lower down exists
          // to be scrolled to when its chip asks for it.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Customer ────────────────────────────────────────────
                FilterFocusTarget(
                  filterKey: 'customer',
                  onActivate: _pickCustomer,
                  child: LinkFieldWidget(
                  controller: _customerCtrl,
                  labelText: 'Customer',
                  hintText: 'Select Customer',
                  prefixIcon: Icons.person_outline,
                  onTap: _pickCustomer,
                  onClear: () {
                    c.customer.value = null;
                    _customerCtrl.clear();
                    setState(() {});
                  },
                )),
                const SizedBox(height: 16),

                // ── Customer Codes (chips) ──────────────────────────────
                FilterFocusTarget(
                  filterKey: 'customer_code',
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                  ],
                )),
                const SizedBox(height: 16),

                // ── Warehouses (chips) ──────────────────────────────────
                FilterFocusTarget(
                  filterKey: 'warehouse',
                  onActivate: _addWarehouse,
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                    onPressed: _addWarehouse,
                  ),
                ),
                  ],
                )),
                const SizedBox(height: 16),

                // ── POS Upload ──────────────────────────────────────────
                FilterFocusTarget(
                  filterKey: 'pos_upload',
                  onActivate: _pickPosUpload,
                  child: LinkFieldWidget(
                  controller: _posCtrl,
                  labelText: 'POS Upload',
                  hintText: 'Select POS Upload',
                  prefixIcon: Icons.cloud_upload_outlined,
                  onTap: _pickPosUpload,
                  onClear: () async {
                    _posCtrl.clear();
                    setState(() {});
                    await c.onPosUploadSelected(null);
                  },
                )),
                const SizedBox(height: 8),

                // ── Switches ────────────────────────────────────────────
                FilterFocusTarget(
                  filterKey: 'show_exploded_view',
                  child: Material(
                    type: MaterialType.transparency,
                    child: Obx(() => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show Exploded View'),
                      value: c.showExplodedView.value,
                      onChanged: (v) => c.showExplodedView.value = v,
                    )),
                  ),
                ),
                FilterFocusTarget(
                  filterKey: 'hide_out_of_stock',
                  child: Material(
                    type: MaterialType.transparency,
                    child: Obx(() => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Hide Out of Stock'),
                      value: c.hideOutOfStock.value,
                      onChanged: (v) => c.hideOutOfStock.value = v,
                    )),
                  ),
                ),
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
