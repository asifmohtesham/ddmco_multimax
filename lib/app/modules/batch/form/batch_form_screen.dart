// app/modules/batch/form/batch_form_screen.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/form/batch_form_controller.dart';

class BatchFormScreen extends GetView<BatchFormController> {
  const BatchFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(controller.batch.value?.name ?? 'Batch Details')),
        actions: [
          Obx(() => controller.isSaving.value
              ? const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))))
              : IconButton(
            icon: const Icon(Icons.save),
            onPressed: controller.saveBatch,
          )
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Primary Details'),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller.itemController,
                readOnly: controller.isEditMode, // Usually fixed once created
                decoration: InputDecoration(
                  labelText: 'Item Code *',
                  hintText: 'Scan or Enter Item Code',
                  border: const OutlineInputBorder(),
                  filled: controller.isEditMode,
                  fillColor: controller.isEditMode ? Colors.grey.shade100 : null,
                  prefixIcon: const Icon(Icons.inventory_2),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller.descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description_outlined),
                ),
              ),

              const SizedBox(height: 24),
              _buildSectionTitle('Dates & Quantity'),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: controller.mfgDateController,
                      readOnly: true,
                      onTap: () => controller.pickDate(controller.mfgDateController),
                      decoration: const InputDecoration(
                        labelText: 'Mfg Date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: controller.expDateController,
                      readOnly: true,
                      onTap: () => controller.pickDate(controller.expDateController),
                      decoration: const InputDecoration(
                        labelText: 'Expiry Date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.event_busy),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller.packagingQtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Packaging Qty (Custom)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.layers),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey),
    );
  }
}