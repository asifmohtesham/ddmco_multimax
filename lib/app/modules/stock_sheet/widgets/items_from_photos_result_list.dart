import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/stock_sheet/model/items_from_photos_models.dart';

/// What a finished run found: the counts, the out-of-stock items, and the
/// photos (or codes) that produced no row. The last two are on screen only;
/// they are never written to the file.
class StockSheetResultList extends StatefulWidget {
  const StockSheetResultList({
    super.key,
    required this.result,
    required this.photoCount,
    required this.thumbnails,
  });

  final StockSheetResult result;
  final int photoCount;

  /// JPEG thumbnails: photos keyed by path, ERP images by
  /// [ItemInfo.thumbnailKey].
  final Map<String, Uint8List> thumbnails;

  /// The on-screen text for why a photo produced no row.
  static String reasonText(UnresolvedEntry entry) => switch (entry.reason) {
    UnresolvedReason.unreadable => 'Unreadable photo',
    UnresolvedReason.noRecognisedCode => 'No recognised code',
    UnresolvedReason.notInErp => 'Not in ERP: ${entry.barcode ?? ''}',
  };

  @override
  State<StockSheetResultList> createState() => _StockSheetResultListState();
}

class _StockSheetResultListState extends State<StockSheetResultList> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static String _count(int n, String one, [String? many]) =>
      '$n ${n == 1 ? one : (many ?? '${one}s')}';

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final outOfStockInk = isDark ? AppColors.red300 : AppColors.red700;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final result = widget.result;
    final outOfStock = result.rows.where((r) => r.outOfStock).toList();
    final counts = [
      _count(widget.photoCount, 'photo'),
      _count(result.rows.length, 'item'),
      '${result.outOfStockCount} out of stock',
    ].join(' · ');

    Widget sectionTitle(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: s.textMuted,
        ),
      ),
    );

    return Scrollbar(
      controller: _scroll,
      child: ListView(
        controller: _scroll,
        padding: EdgeInsets.only(top: 8, bottom: 16 + bottomInset),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              counts,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: s.text,
              ),
            ),
          ),
          if (outOfStock.isNotEmpty) ...[
            sectionTitle('Out of stock'),
            for (final row in outOfStock)
              ListTile(
                dense: true,
                leading: _Thumbnail(
                  bytes: row.imageKey == null
                      ? null
                      : widget.thumbnails[row.imageKey],
                ),
                title: Text(
                  row.itemName ?? row.barcode,
                  style: TextStyle(color: outOfStockInk),
                ),
                subtitle: Text(
                  '${row.barcode} · Photo ${row.photoIndex + 1}',
                  style: TextStyle(color: s.textMuted),
                ),
              ),
          ],
          if (result.unresolved.isNotEmpty) ...[
            sectionTitle("Couldn't use these photos"),
            for (final entry in result.unresolved)
              ListTile(
                dense: true,
                leading: _Thumbnail(bytes: widget.thumbnails[entry.photoPath]),
                title: Text(
                  'Photo ${entry.photoIndex + 1}',
                  style: TextStyle(color: s.text),
                ),
                subtitle: Text(
                  StockSheetResultList.reasonText(entry),
                  style: TextStyle(color: s.textMuted),
                ),
              ),
          ],
          const SizedBox(height: 16),
          _EndOfList(color: s.textMuted, divider: s.border),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final image = bytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 44,
        height: 44,
        child: image == null
            ? ColoredBox(
                color: s.subtle,
                child: Icon(
                  Icons.image_not_supported_outlined,
                  size: 20,
                  color: s.textSubtle,
                ),
              )
            : Image.memory(
                image,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => ColoredBox(color: s.subtle),
              ),
      ),
    );
  }
}

class _EndOfList extends StatelessWidget {
  const _EndOfList({required this.color, required this.divider});

  final Color color;
  final Color divider;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'End of list',
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
          Expanded(child: Divider(color: divider)),
        ],
      ),
    );
  }
}
