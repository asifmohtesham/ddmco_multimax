import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/material_request/form/material_request_form_controller.dart';
import 'package:multimax/app/modules/material_request/form/widgets/material_request_item_card.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class MaterialRequestFormScreen extends GetView<MaterialRequestFormController> {
  const MaterialRequestFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() => PopScope(
      canPop: !controller.isDirty.value,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await controller.confirmDiscard();
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(controller.materialRequest.value?.name ?? 'New Request',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (controller.materialRequest.value?.status != null)
                  StatusPill(status: controller.materialRequest.value!.status),
              ],
            ),
            actions: [
              if (controller.materialRequest.value?.docstatus == 0)
                IconButton(
                  icon: const Icon(Icons.save),
                  // Disable button if form is not dirty
                  onPressed: controller.isDirty.value ? controller.saveMaterialRequest : null,
                )
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Details'),
                Tab(text: 'Items'),
              ],
            ),
          ),
          body: controller.isLoading.value
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
            children: [
              _buildDetailsTab(context),
              _buildItemsTab(context),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _buildDetailsTab(BuildContext context) {
    final entry = controller.materialRequest.value;
    final isEditable = entry?.docstatus == 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Type Selector
          DropdownButtonFormField<String>(
            value: controller.selectedType.value,
            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
            items: controller.requestTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: isEditable ? controller.onTypeChanged : null,
          ),
          const SizedBox(height: 16),

          // Dates
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller.transactionDateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                      labelText: 'Date',
                      prefixIcon: Icon(Icons.calendar_today),
                      border: OutlineInputBorder()
                  ),
                  onTap: () => controller.setDate(controller.transactionDateController),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: controller.scheduleDateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                      labelText: 'Required By',
                      prefixIcon: Icon(Icons.event),
                      border: OutlineInputBorder()
                  ),
                  onTap: () => controller.setDate(controller.scheduleDateController),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemsTab(BuildContext context) {
    final items = controller.materialRequest.value?.items ?? [];
    final isEditable = controller.materialRequest.value?.docstatus == 0;

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.only(bottom: 80, top: 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (ctx, i) => MaterialRequestItemCard(
            item: items[i],
            onTap: isEditable ? () => controller.openItemSheet(item: items[i]) : null,
            onDelete: isEditable ? () => controller.deleteItem(items[i]) : null,
          ),
        ),
        if (isEditable)
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.only(bottom: 12),
              color: Colors.white,
              child: BarcodeInputWidget(
                controller: controller.barcodeController,
                onScan: controller.scanBarcode,
                activeRoute: AppRoutes.MATERIAL_REQUEST_FORM,
                hintText: 'Scan Item to Add...',
                isLoading: controller.isScanning.value,
              ),
            ),
          )
      ],
    );
  }
}