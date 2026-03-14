import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/material_request/form/material_request_form_controller.dart';
import 'package:multimax/app/modules/material_request/form/widgets/material_request_item_card.dart';

/// M3-upgraded Form View for Material Request.
/// Design language matches StockEntryFormScreen and DeliveryNoteFormScreen:
///   • Shared MainAppBar (title + StatusPill + save/reload actions)
///   • PopScope dirty-state guard
///   • DefaultTabController with Details / Items tabs
///   • Section cards layout (same _buildSectionCard helper as DeliveryNote)
///   • Warehouse banner (_buildWarehouseBanner, mirrors StockEntry FROM→TO)
///   • _buildCompactField for read-only date/time chips
///   • Summary card at bottom of Details tab
///   • Obx-reactive BarcodeInputWidget at bottom of Items tab
class MaterialRequestFormScreen extends GetView<MaterialRequestFormController> {
  const MaterialRequestFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final entry = controller.materialRequest.value;
      final bool isEditable = entry?.docstatus == 0;

      final String title = entry == null
          ? 'Loading...'
          : (entry.name == 'New Material Request'
              ? 'New Material Request'
              : entry.name);

      return PopScope(
        canPop: !controller.isDirty.value,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await controller.confirmDiscard();
        },
        child: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: MainAppBar(
              title: title,
              status: entry?.status,
              isDirty: controller.isDirty.value,
              isSaving: controller.isSaving.value,
              // Save is available only on editable, dirty documents
              onSave: (isEditable && controller.isDirty.value)
                  ? controller.saveMaterialRequest
                  : null,
              // Reload: only for persisted docs without unsaved changes
              onReload: (controller.mode != 'new' && !controller.isDirty.value)
                  ? controller.reloadDocument
                  : null,
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Details'),
                  Tab(text: 'Items'),
                ],
              ),
            ),
            body: Builder(builder: (context) {
              if (controller.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }
              if (entry == null) {
                return const Center(
                    child: Text('Material request not found.'));
              }
              return TabBarView(
                children: [
                  _buildDetailsTab(context, entry, isEditable),
                  _buildItemsTab(context, entry, isEditable),
                ],
              );
            }),
          ),
        ),
      );
    });
  }

  // ── Details Tab ─────────────────────────────────────────────────────────

  Widget _buildDetailsTab(
      BuildContext context, dynamic entry, bool isEditable) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Type + Warehouse banner ────────────────────────────────────
          _buildTypeBanner(context, isEditable),

          const SizedBox(height: 16),

          // ── Schedule section ─────────────────────────────────────────
          _buildSectionCard(
            title: 'Schedule',
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildCompactField(
                      label: 'Date',
                      value: controller.transactionDateController.text,
                      icon: Icons.calendar_today_outlined,
                      onTap: isEditable
                          ? () => controller
                              .setDate(controller.transactionDateController)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCompactField(
                      label: 'Required By',
                      value: controller.scheduleDateController.text,
                      icon: Icons.event_outlined,
                      onTap: isEditable
                          ? () => controller
                              .setDate(controller.scheduleDateController)
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Summary ────────────────────────────────────────────────────
          _buildSectionCard(
            title: 'Summary',
            children: [
              Obx(() {
                final items =
                    controller.materialRequest.value?.items ?? [];
                final totalQty =
                    items.fold(0.0, (sum, i) => sum + i.qty);
                final fulfilledCount =
                    items.where((i) => i.orderedQty >= i.qty).length;
                return Column(
                  children: [
                    _buildSummaryRow('Total Lines',
                        '${items.length}'),
                    const Divider(),
                    _buildSummaryRow('Total Qty',
                        totalQty.toStringAsFixed(2)),
                    const Divider(),
                    _buildSummaryRow('Ordered Lines',
                        '$fulfilledCount / ${items.length}',
                        isBold: true),
                  ],
                );
              }),
            ],
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  /// Gradient banner: type row + warehouse picker.
  /// Mirrors the FROM→TO card in StockEntryFormScreen.
  Widget _buildTypeBanner(BuildContext context, bool isEditable) {
    return Obx(() {
      final type = controller.selectedType.value;
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepPurple.shade50, Colors.teal.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.teal.shade100),
        ),
        child: Column(
          children: [
            // ── Type row ──────────────────────────────────────────────
            InkWell(
              onTap: isEditable ? () => _showTypePicker(context) : null,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Icon(Icons.category_outlined,
                      size: 20, color: Colors.deepPurple.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      type,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple.shade900,
                          fontSize: 16),
                    ),
                  ),
                  if (isEditable)
                    const Icon(Icons.arrow_drop_down,
                        color: Colors.blueGrey),
                ],
              ),
            ),

            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _typeHelperText(type),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.blueGrey.shade700),
              ),
            ),

            const Divider(height: 24),

            // ── Target Warehouse ──────────────────────────────────────
            InkWell(
              onTap: isEditable
                  ? () => controller.showWarehousePicker(forItem: false)
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 4, horizontal: 2),
                child: Row(
                  children: [
                    Icon(Icons.warehouse_outlined,
                        size: 18, color: Colors.teal.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'TARGET WAREHOUSE',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.bold),
                              ),
                              if (isEditable) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.edit,
                                    size: 10,
                                    color: Colors.grey.shade500),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            controller.setWarehouseController.text
                                    .isNotEmpty
                                ? controller.setWarehouseController.text
                                : 'Select Warehouse',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: controller
                                      .setWarehouseController.text
                                      .isNotEmpty
                                  ? Colors.black87
                                  : Colors.grey,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  // ── Items Tab ────────────────────────────────────────────────────────────

  Widget _buildItemsTab(
      BuildContext context, dynamic entry, bool isEditable) {
    return Stack(
      children: [
        Obx(() {
          final items = controller.materialRequest.value?.items ?? [];
          if (items.isEmpty && !isEditable) {
            return _buildEmptyState();
          }
          if (items.isEmpty) {
            return _buildEmptyState();
          }
          return ListView.separated(
            controller: controller.scrollController,
            padding:
                const EdgeInsets.only(top: 8, bottom: 100),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 0),
            itemBuilder: (ctx, i) => MaterialRequestItemCard(
              item: items[i],
              onTap: isEditable
                  ? () => controller.openItemSheet(item: items[i])
                  : null,
              onDelete: (isEditable && items.length > 1)
                  ? () => controller.deleteItem(items[i])
                  : null,
            ),
          );
        }),
        // ── Barcode scan bar (editable documents only) ────────────────
        if (isEditable)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, -4))
                ],
              ),
              padding: const EdgeInsets.only(bottom: 0),
              child: Obx(() => BarcodeInputWidget(
                    onScan: controller.scanBarcode,
                    isLoading: controller.isScanning.value,
                    controller: controller.barcodeController,
                    activeRoute: AppRoutes.MATERIAL_REQUEST_FORM,
                    hintText: 'Scan Item to Add...',
                  )),
            ),
          ),
      ],
    );
  }

  // ── Shared helpers (DRY — identical contract to StockEntry / DeliveryNote) ─

  /// Section card — same as DeliveryNoteFormScreen._buildSectionCard.
  Widget _buildSectionCard(
      {required String title, required List<Widget> children}) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  /// Compact date/time field — same contract as StockEntryFormScreen._buildCompactField.
  Widget _buildCompactField({
    required String label,
    required String? value,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      const TextStyle(fontSize: 10, color: Colors.grey)),
              Text(value ?? '—',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
        borderRadius: BorderRadius.circular(12), onTap: onTap, child: content);
  }

  /// Summary row — same as StockEntryFormScreen._buildSummaryRow.
  Widget _buildSummaryRow(String label, String value,
      {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Text(
            value,
            style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                fontSize: isBold ? 16 : 14,
                color: isBold ? Colors.black87 : Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_scanner, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No Items',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          const Text('Scan an item or tap + to add.',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  // ── Type Picker (bottom-sheet) ────────────────────────────────────────────

  void _showTypePicker(BuildContext context) {
    final RxList<String> filtered =
        RxList<String>(controller.requestTypes);
    final searchCtrl = TextEditingController();

    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
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
                      Text('Select Request Type',
                          style: Theme.of(context).textTheme.titleLarge),
                      IconButton(
                          onPressed: () => Get.back(),
                          icon: const Icon(Icons.close)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Search Types',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (val) {
                      if (val.isEmpty) {
                        filtered.assignAll(controller.requestTypes);
                      } else {
                        filtered.assignAll(controller.requestTypes.where(
                            (t) => t
                                .toLowerCase()
                                .contains(val.toLowerCase())));
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Obx(() => ListView.separated(
                          controller: scrollController,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final t = filtered[index];
                            final isSelected =
                                t == controller.selectedType.value;
                            return ListTile(
                              title: Text(t,
                                  style: TextStyle(
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal)),
                              subtitle: Text(
                                _typeHelperText(t),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: Colors.grey.shade700),
                              ),
                              isThreeLine: true,
                              trailing: isSelected
                                  ? Icon(Icons.check_circle,
                                      color:
                                          Theme.of(context).primaryColor)
                                  : null,
                              onTap: () {
                                controller.onTypeChanged(t);
                                Get.back();
                              },
                            );
                          },
                        )),
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

  String _typeHelperText(String type) {
    switch (type) {
      case 'Purchase':
        return 'Request items to be purchased from a supplier.';
      case 'Material Transfer':
        return 'Move stock between warehouses.';
      case 'Material Issue':
        return 'Issue materials out of a warehouse.';
      case 'Manufacture':
        return 'Request materials for a production order.';
      case 'Customer Provided':
        return 'Materials provided by the customer for processing.';
      default:
        return 'Configure how this request should behave.';
    }
  }
}
