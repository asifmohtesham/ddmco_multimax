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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.description != null && item.description != item.itemCode)
              Text(item.description!, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('Qty: ${item.qty} ${item.uom ?? ''}',
                style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.w600)),
          ],
        ),
        trailing: onDelete != null
            ? IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: onDelete)
            : null,
      ),
    );
  }
}