import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/common/serial_batch_bundle/controllers/serial_batch_bundle_controller.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart'; // Assuming generic widget exists

class SerialBatchBundleSheet extends GetView<SerialBatchBundleController> {
  const SerialBatchBundleSheet({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.all(16.0),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Manage Batches', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Get.back()),
              ],
            ),
            const Divider(),

            // Summary
            Obx(() => Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total Qty: ${controller.totalQty.value.toStringAsFixed(2)}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                  if (controller.args.requiredQty != null)
                    Text('Target: ${controller.args.requiredQty}',
                        style: const TextStyle(color: Colors.grey)),
                ],
              ),
            )),
            const SizedBox(height: 12),

            // Autocomplete / Search
            _buildAutocomplete(context),

            const SizedBox(height: 12),

            // Validation Error
            Obx(() {
              if (controller.batchError.value != null) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  color: Colors.red.shade50,
                  child: Text(controller.batchError.value!, style: TextStyle(color: Colors.red.shade800)),
                );
              }
              return const SizedBox.shrink();
            }),

            // List
            Expanded(
              child: Obx(() {
                if (controller.currentEntries.isEmpty) {
                  return const Center(child: Text('No batches selected.', style: TextStyle(color: Colors.grey)));
                }
                return ListView.separated(
                  itemCount: controller.currentEntries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = controller.currentEntries[index];
                    return Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry.batchNo ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text(entry.warehouse ?? '', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              initialValue: entry.qty.abs().toString(),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (val) {
                                final q = double.tryParse(val);
                                if (q != null) controller.updateEntryQty(index, q);
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                            onPressed: () => controller.removeEntry(index),
                          )
                        ],
                      ),
                    );
                  },
                );
              }),
            ),

            const SizedBox(height: 12),

            // Submit
            Obx(() => SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: controller.isSubmitting.value ? null : controller.submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.blue,
                ),
                child: controller.isSubmitting.value
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Confirm & Save', style: TextStyle(color: Colors.white)),
              ),
            ))
          ],
        ),
      ),
    );
  }

  Widget _buildAutocomplete(BuildContext context) {
    return LayoutBuilder(
        builder: (context, constraints) {
          return RawAutocomplete<Map<String, dynamic>>(
            textEditingController: controller.batchInputController,
            focusNode: FocusNode(),
            optionsBuilder: (TextEditingValue textEditingValue) {
              return controller.searchBatches(textEditingValue.text);
            },
            displayStringForOption: (option) => option['batch'] ?? '',
            onSelected: (option) {
              if (option['batch'] != null) {
                controller.validateAndAddBatch(option['batch']);
              }
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4.0,
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: 200,
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          dense: true,
                          title: Text(option['batch'] ?? ''),
                          trailing: Text('Qty: ${option['qty']}'),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
            fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
              return Obx(() => TextField(
                controller: textController,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: 'Scan or Type Batch...',
                  prefixIcon: const Icon(Icons.qr_code_scanner),
                  suffixIcon: controller.isValidatingBatch.value
                      ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      if (textController.text.isNotEmpty) {
                        controller.validateAndAddBatch(textController.text);
                      }
                    },
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onSubmitted: (val) {
                  if(val.isNotEmpty) controller.validateAndAddBatch(val);
                },
              ));
            },
          );
        }
    );
  }
}