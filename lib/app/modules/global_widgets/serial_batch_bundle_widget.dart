import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/mixins/serial_batch_bundle_mixin.dart';
import 'package:multimax/app/data/models/batch_model.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';

class SerialBatchBundleWidget extends StatelessWidget {
  final SerialBatchBundleMixin mixin;

  const SerialBatchBundleWidget({Key? key, required this.mixin}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: Text("Serial and Batch Bundle", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),

        // List of Added Batches
        Obx(() => Container(
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: mixin.sabbEntries.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(16), child: Text("No batches added")))
              : ListView.separated(
            shrinkWrap: true,
            itemCount: mixin.sabbEntries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, index) {
              final entry = mixin.sabbEntries[index];
              final batchNo = entry.batchNo;

              final balance = mixin.batchBalances[batchNo] ?? 0.0;
              final isOverStock = entry.qty.abs() > balance;

              // Ensure controller exists (safety check for strict mode)
              if (!mixin.batchQtyControllers.containsKey(batchNo)) {
                mixin.initialiseBatchControl(batchNo, entry.qty);
              }

              return ListTile(
                key: ValueKey(batchNo),
                contentPadding: const EdgeInsets.only(left: 12, right: 4),
                dense: true,
                title: Text(
                    entry.batchNo,
                    style: const TextStyle(fontFamily: 'ShureTechMono', fontWeight: FontWeight.w500)
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 80,
                      child: TextFormField(
                        controller: mixin.batchQtyControllers[batchNo],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(),
                          labelText: 'Qty',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                        ),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        // Optional: Allow 'Enter' to commit as well
                        onFieldSubmitted: (_) => mixin.commitBatchQty(batchNo),
                      ),
                    ),
                    // The UX Improvement: Explicit Update Action
                    Obx(() {
                      final isDirty = mixin.batchEditStatus[batchNo]?.value ?? false;
                      if (!isDirty) return const SizedBox(width: 0); // Hide if clean

                      return IconButton(
                        icon: const Icon(Icons.check_circle, color: Colors.green, size: 28),
                        tooltip: 'Update Quantity',
                        onPressed: () => mixin.commitBatchQty(batchNo),
                      );
                    }),

                    if (mixin.batchQtyControllers.length > 1 && mixin.batchEditStatus[batchNo]?.value != true) // Hide delete if editing? Or keep it.
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                        onPressed: () => mixin.removeSabbEntry(index),
                      )
                  ],
                ),
              );
            },
          ),
        )),

        const SizedBox(height: 12),

        // Autocomplete Input for New Batch
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 2,
              child: GlobalItemFormSheet.buildInputGroup(
                label: 'Batch No',
                color: Colors.purple,
                child: LayoutBuilder(
                    builder: (context, constraints) {
                      return RawAutocomplete<Batch>(
                        focusNode: FocusNode(),
                        textEditingController: mixin.bsBatchController,
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          return mixin.searchBatches(textEditingValue.text);
                        },
                        displayStringForOption: (Batch option) => option.name ?? '',
                        onSelected: (Batch selection) {
                          // When selected from list, validate and add immediately or just set text
                          // Here we just validate and let user type qty
                          mixin.bsBatchController.text = selection.name ?? '';
                          mixin.validateAndAddBatch(selection.name ?? '', 0); // 0 qty just to fetch balance
                        },
                        fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: textController,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              hintText: 'Scan/Search',
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.qr_code_scanner, size: 20),
                            ),
                            onSubmitted: (val) {
                              // Use quantity from controller
                              final qty = double.tryParse(mixin.bsQtyController.text) ?? 1.0;
                              // On manual enter/scan without clicking option
                              mixin.validateAndAddBatch(val);
                            },
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4.0,
                              child: SizedBox(
                                width: constraints.maxWidth,
                                height: 200, // Limit height
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: options.length,
                                  itemBuilder: (BuildContext context, int index) {
                                    final Batch option = options.elementAt(index);
                                    return ListTile(
                                      title: Text(option.name ?? ''),
                                      subtitle: Text("MFG: ${option.manufacturingDate ?? ''}"),
                                      onTap: () => onSelected(option),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Add Button with Loading State
            Obx(() => mixin.isAddingBatch.value
                ? const Padding(
              padding: EdgeInsets.all(12.0),
              child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purple)
              ),
            )
                : IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.purple, size: 32),
              onPressed: () {
                mixin.addBatchFromInput();
              },
            )
            ),
          ],
        ),
      ],
    );
  }
}