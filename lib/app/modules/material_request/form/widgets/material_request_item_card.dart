import 'package:flutter/material.dart';
import 'package:multimax/app/data/models/material_request_model.dart';

class MaterialRequestItemCard extends StatelessWidget {
  final MaterialRequestItem item;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const MaterialRequestItemCard({
    super.key,
    required this.item,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate progress (Ordered vs Qty)
    final double progress = (item.qty > 0) ? (item.orderedQty / item.qty).clamp(0.0, 1.0) : 0.0;
    final bool isComplete = progress >= 1.0;
    final bool hasStarted = progress > 0;

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
              // Header Row: Item Code and Delete Button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.itemCode,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        if (item.itemName != null && item.itemName!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              item.itemName!,
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    InkWell(
                      onTap: onDelete,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),
              Divider(height: 1, color: Colors.grey.shade100),
              const SizedBox(height: 12),

              // Progress Indicator (Only show if relevant)
              if (item.qty > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey.shade100,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                isComplete ? Colors.green : (hasStarted ? Colors.orange : Colors.blue)
                            ),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isComplete ? Colors.green : (hasStarted ? Colors.orange : Colors.blue)
                        ),
                      ),
                    ],
                  ),
                ),

              // Stats Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStat(context, 'Qty', '${item.qty} ${item.uom ?? ''}', isPrimary: true),
                  // Highlight Ordered Qty if progress exists
                  _buildStat(context, 'Ordered', '${item.orderedQty}',
                      color: hasStarted ? (isComplete ? Colors.green : Colors.orange) : null),

                  if (item.receivedQty > 0)
                    _buildStat(context, 'Received', '${item.receivedQty}'),
                  if (item.actualQty > 0)
                    _buildStat(context, 'Actual', '${item.actualQty}'),
                ],
              ),

              if (item.warehouse != null && item.warehouse!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.store_outlined, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      item.warehouse!,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStat(BuildContext context, String label, String value, {bool isPrimary = false, Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color ?? (isPrimary ? Theme.of(context).primaryColor : Colors.black87),
          ),
        ),
      ],
    );
  }
}