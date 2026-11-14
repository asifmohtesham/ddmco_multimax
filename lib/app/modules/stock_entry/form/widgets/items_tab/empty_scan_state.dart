import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// Empty-state widget shown when no items have been scanned yet.
/// Step 6 — extracted from StockEntryFormScreen._buildEmptyState().
class EmptyScanState extends StatelessWidget {
  const EmptyScanState({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_scanner, size: 80, color: scheme.textSubtle),
          const SizedBox(height: 16),
          Text(
            'Ready to Scan',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: scheme.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan items, batches or racks to start.',
            style: TextStyle(color: scheme.textMuted),
          ),
        ],
      ),
    );
  }
}
