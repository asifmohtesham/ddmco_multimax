import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/mixins/serial_batch_bundle_mixin.dart';
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
              return ListTile(
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
                        initialValue: entry.qty.abs().toString(),
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
                        onFieldSubmitted: (val) {
                          final q = double.tryParse(val) ?? 0;
                          mixin.updateSabbEntry(index, q);
                        },
                      ),
                    ),
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

        // Inline Input for New Batch
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 2,
              child: GlobalItemFormSheet.buildInputGroup(
                label: 'Batch No',
                color: Colors.purple,
                child: TextField(
                  controller: mixin.bsBatchController,
                  decoration: const InputDecoration(
                    hintText: 'Scan/Enter',
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: GlobalItemFormSheet.buildInputGroup(
                label: 'Qty',
                color: Colors.purple,
                child: TextField(
                  // Temporary text field for creating
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: '1.0',
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (val) {
                    final qty = double.tryParse(val) ?? 0;
                    mixin.addSabbEntry(mixin.bsBatchController.text, qty);
                  },
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.purple, size: 32),
              onPressed: () {
                // Default to 1.0 if no separate qty field logic is complex here,
                // or assume the user workflow is Scan -> Add.
                mixin.addSabbEntry(mixin.bsBatchController.text, 1.0);
              },
            )
          ],
        ),
      ],
    );
  }
}