import 'dart:ui';
import 'package:flutter/material.dart';

/// A self-contained image widget for an ERPNext Item.
///
/// Renders the item's network image when [imageUrl] is non-null/non-empty,
/// otherwise falls back to a placeholder container with an icon.
/// Includes a shimmer-style loading indicator while the image is fetching.
class ItemImage extends StatelessWidget {
  final String? imageUrl;

  /// Square size for the widget when used in list or preview contexts.
  /// When null the widget expands to fill its parent (grid usage).
  final double? size;

  /// How the image should be inscribed into the space. Defaults to [BoxFit.contain].
  final BoxFit fit;

  const ItemImage({
    super.key,
    required this.imageUrl,
    this.size,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: fit,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              width: size,
              height: size,
              color: cs.surfaceContainerHighest,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                        : null,
                    color: cs.primary,
                  ),
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) => _placeholder(cs),
        ),
      );
    }
    return _placeholder(cs);
  }

  Widget _placeholder(ColorScheme cs) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.image_not_supported_outlined,
          color: cs.onSurfaceVariant.withValues(alpha: 0.4),
          // ignore: avoid-unsafe-collection-methods  (size is nullable by design)
          size: size != null ? size! * 0.5 : 30,
        ),
      );
}
