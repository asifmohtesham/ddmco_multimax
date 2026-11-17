import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/stock_sheet/stock_sheet_controller.dart';

/// Asks which file to make for [photoCount] shared photos. Returns null when
/// dismissed.
Future<SheetFormat?> showFormatSheet(
  BuildContext context, {
  required int photoCount,
}) {
  return showModalBottomSheet<SheetFormat>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => FormatSheet(photoCount: photoCount),
  );
}

class FormatSheet extends StatelessWidget {
  const FormatSheet({super.key, required this.photoCount});

  final int photoCount;

  @override
  Widget build(BuildContext context) {
    return StockSheetChoiceSheet(
      title: 'Make a stock sheet',
      subtitle: photoCount == 1 ? '1 photo' : '$photoCount photos',
      options: [
        _option(
          context,
          Icons.table_chart_outlined,
          'Excel',
          SheetFormat.excel,
        ),
        _option(context, Icons.picture_as_pdf_outlined, 'PDF', SheetFormat.pdf),
        _option(
          context,
          Icons.library_books_outlined,
          'Excel and PDF',
          SheetFormat.both,
        ),
      ],
    );
  }

  Widget _option(
    BuildContext context,
    IconData icon,
    String label,
    SheetFormat format,
  ) {
    final s = context.scheme;
    return ListTile(
      leading: Icon(icon, color: s.textMuted),
      title: Text(label, style: TextStyle(color: s.text)),
      onTap: () => Navigator.of(context).pop(format),
    );
  }
}

/// The themed bottom-sheet frame shared by the format and out-of-stock
/// questions: handle, title, muted subtitle, then the options.
class StockSheetChoiceSheet extends StatelessWidget {
  const StockSheetChoiceSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.options,
  });

  final String title;
  final String subtitle;
  final List<Widget> options;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    // A Material (not a decorated Container) so the options' ink shows.
    return Material(
      color: s.fg,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: s.borderStrong,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: s.text,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: s.textMuted),
                ),
              ),
              ...options,
            ],
          ),
        ),
      ),
    );
  }
}
