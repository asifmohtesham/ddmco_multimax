import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A rounded item thumbnail. Shows the network image when [imageUrl] is
/// non-empty, otherwise a 2-letter initials fallback derived from the item
/// name (or code). Tapping an actual image opens [showItemImagePreview]
/// without leaving the current screen.
class ItemThumbnail extends StatelessWidget {
  final String? imageUrl;
  final String itemCode;
  final String itemName;
  final double size;

  const ItemThumbnail({
    super.key,
    required this.imageUrl,
    required this.itemCode,
    required this.itemName,
    this.size = 46,
  });

  String get _initials {
    final source = itemName.trim().isNotEmpty ? itemName : itemCode;
    final words = source
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '·';
    final letters = words.take(2).map((w) => w[0]).join();
    return letters.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget fallback() => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          color: cs.secondaryContainer,
          child: Text(
            _initials,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSecondaryContainer,
            ),
          ),
        );

    final url = imageUrl?.trim() ?? '';
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? fallback()
            : CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, __) => fallback(),
                errorWidget: (_, __, ___) => fallback(),
              ),
      ),
    );

    if (url.isEmpty) return thumb;
    return GestureDetector(
      onTap: () => showItemImagePreview(context, url, itemCode, itemName),
      child: Hero(
        tag: 'item-image-$itemCode',
        child: thumb,
      ),
    );
  }
}

/// Shows the item image enlarged in an in-screen, dismissible dialog with
/// pinch/drag zoom. Stays on the current screen — no navigation.
void showItemImagePreview(
  BuildContext context,
  String url,
  String itemCode,
  String itemName,
) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    useSafeArea: false, // let the preview fill the whole screen
    builder: (ctx) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      clipBehavior: Clip.hardEdge,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Hero(
                    tag: 'item-image-$itemCode',
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      ),
                      errorWidget: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    itemName.isNotEmpty ? '$itemCode · $itemName' : itemCode,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
