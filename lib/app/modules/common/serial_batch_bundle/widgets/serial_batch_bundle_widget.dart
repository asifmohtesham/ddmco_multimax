import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/common/serial_batch_bundle/controllers/serial_batch_bundle_controller.dart';

// CHANGED: Extend StatelessWidget instead of GetWidget
class SerialBatchBundleWidget extends StatelessWidget {
  // CHANGED: Store controller directly
  final SerialBatchBundleController controller;

  const SerialBatchBundleWidget({
    Key? key,
    required this.controller, // CHANGED: Require controller instance
  }) : super(key: key);

  // REMOVED: tag override is no longer needed

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Total Qty Display
        Obx(() => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.blue.shade50,
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                'Total Selected: ${controller.totalQty.value.toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900, fontSize: 12),
              ),
            ],
          ),
        )),

        const SizedBox(height: 12),

        // 2. Autocomplete Input
        _buildAutocomplete(context),

        const SizedBox(height: 8),

        // 3. Error Messages
        Obx(() {
          if (controller.batchError.value != null) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                controller.batchError.value!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            );
          }
          return const SizedBox.shrink();
        }),

        // 4. Compact List of Scanned Items
        Obx(() {
          if (controller.currentEntries.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: Text("No batches scanned yet.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
              ),
            );
          }

          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: controller.currentEntries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = controller.currentEntries[index];
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(entry.batchNo ?? '-', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: Text(entry.warehouse ?? '', style: const TextStyle(fontSize: 10)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 60,
                      height: 30,
                      child: TextFormField(
                        initialValue: entry.qty.toString(),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) => controller.updateEntryQty(index, double.tryParse(val) ?? 0),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.red),
                      onPressed: () => controller.removeEntry(index),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              );
            },
          );
        }),
      ],
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
              return TextField(
                controller: textController,
                focusNode: focusNode,
                decoration: InputDecoration(
                  labelText: 'Scan Batch / Serial',
                  isDense: true,
                  prefixIcon: const Icon(Icons.qr_code),
                  suffixIcon: Obx(() => controller.isValidatingBatch.value
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width:10, height:10, child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      if (textController.text.isNotEmpty) {
                        controller.validateAndAddBatch(textController.text);
                      }
                    },
                  )
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onSubmitted: (val) {
                  if(val.isNotEmpty) controller.validateAndAddBatch(val);
                },
              );
            },
          );
        }
    );
  }
}