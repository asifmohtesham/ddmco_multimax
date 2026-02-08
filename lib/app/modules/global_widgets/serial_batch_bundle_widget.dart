import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/mixins/serial_batch_bundle_mixin.dart';
import 'package:multimax/app/data/models/batch_model.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

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
                subtitle: Text(
                  "Available Balance: ${FormattingHelper.formatQty(balance)}",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isOverStock ? Colors.red : Colors.green.shade700,
                  ),
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
                        onFieldSubmitted: (_) => mixin.commitBatchQty(batchNo),
                      ),
                    ),
                    Obx(() {
                      final isDirty = mixin.batchEditStatus[batchNo]?.value ?? false;
                      if (!isDirty) return const SizedBox(width: 0);

                      return IconButton(
                        icon: const Icon(Icons.check_circle, color: Colors.green, size: 28),
                        tooltip: 'Update Quantity',
                        onPressed: () => mixin.commitBatchQty(batchNo),
                      );
                    }),
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
                          // [UPDATED] Unify workflow: Set text and call the common add method
                          mixin.bsBatchController.text = selection.name ?? '';
                          mixin.addBatchFromInput();
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
                              // [UPDATED] Use common method for manual entry/scan
                              mixin.addBatchFromInput();
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
                                height: 200,
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
                // [UPDATED] Use common method
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