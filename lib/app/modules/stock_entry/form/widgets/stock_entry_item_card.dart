import 'package:flutter/material.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';

class StockEntryItemCard extends StatelessWidget {
  final StockEntryItem item;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final double? maxQty;

  const StockEntryItemCard({
    super.key,
    required this.item,
    this.onTap,
    this.onDelete,
    this.maxQty,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate progress using passed maxQty
    final bool showProgress = maxQty != null && maxQty! > 0;
    final double progress = showProgress ? (item.qty / maxQty!).clamp(0.0, 1.0) : 0.0;
    final bool isComplete = progress >= 1.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        if (item.itemName != null)
                          Text(item.itemName!, style: TextStyle(color: Colors.grey.shade600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    InkWell(
                      onTap: onDelete,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(Icons.close, size: 20, color: Colors.grey.shade400),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              if (showProgress)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey.shade100,
                            valueColor: AlwaysStoppedAnimation<Color>(isComplete ? Colors.green : Colors.blue),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${item.qty.toStringAsFixed(0)} / ${maxQty!.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (item.qty > 0)
                    Text('Qty: ${item.qty}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (item.batchNo != null && item.batchNo!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                      child: Text(item.batchNo!, style: TextStyle(fontSize: 12, color: Colors.blue.shade800)),
                    ),
                ],
              ),
              if (item.rack != null || item.toRack != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      if (item.rack != null) ...[
                        const Icon(Icons.arrow_upward, size: 14, color: Colors.orange),
                        Text(' ${item.rack}  ', style: const TextStyle(fontSize: 12)),
                      ],
                      if (item.toRack != null) ...[
                        const Icon(Icons.arrow_downward, size: 14, color: Colors.green),
                        Text(' ${item.toRack}', style: const TextStyle(fontSize: 12)),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}