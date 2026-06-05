import 'package:flutter/material.dart';

/// Empty-state widget shown when no items have been scanned yet.
/// Step 6 — extracted from StockEntryFormScreen._buildEmptyState().
class EmptyScanState extends StatelessWidget {
  const EmptyScanState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_scanner,
              size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Ready to Scan',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scan items, batches or racks to start.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
