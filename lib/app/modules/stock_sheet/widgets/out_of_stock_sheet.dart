import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/stock_sheet/items_from_photos_controller.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/items_from_photos_choice_sheet.dart';

/// Asks how the sheet treats [count] out-of-stock items. Returns null when
/// dismissed, which goes back to the review.
Future<OutOfStockChoice?> showOutOfStockSheet(
  BuildContext context, {
  required int count,
}) {
  return showModalBottomSheet<OutOfStockChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => OutOfStockSheet(count: count),
  );
}

class OutOfStockSheet extends StatelessWidget {
  const OutOfStockSheet({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    Widget option(String label, OutOfStockChoice choice) => ListTile(
      title: Text(label, style: TextStyle(color: s.text)),
      onTap: () => Navigator.of(context).pop(choice),
    );

    return ItemsFromPhotosChoiceSheet(
      title: count == 1
          ? '1 item is out of stock'
          : '$count items are out of stock',
      subtitle: 'How should the file show them?',
      options: [
        option('Include, colour red', OutOfStockChoice.includeRed),
        option('Include, no colour', OutOfStockChoice.includePlain),
        option('Leave them out', OutOfStockChoice.leaveOut),
      ],
    );
  }
}
