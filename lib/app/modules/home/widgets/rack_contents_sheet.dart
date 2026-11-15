import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/item_image.dart'
    show showItemImagePreview;
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/home/rack_contents_logic.dart';

/// Dashboard rack scan result: every item on [rackId] with its Balance Qty
/// from the Stock Balance report and its Item master fields.
///
/// [itemDetailsFailed] is true when the Item fetch failed; the cards then
/// show the report data alone and the header says so quietly.
class RackContentsSheet extends StatelessWidget {
  const RackContentsSheet({
    super.key,
    required this.rackId,
    required this.entries,
    required this.baseUrl,
    this.itemDetailsFailed = false,
    this.onItemTap,
  });

  final String rackId;
  final List<RackContentsEntry> entries;

  /// Server origin that Item `image` paths are relative to.
  final String baseUrl;
  final bool itemDetailsFailed;

  /// Opens the tapped item; null leaves the cards inert.
  final ValueChanged<String>? onItemTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: scheme.fg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      // The list clears the system nav bar itself, so its last card can
      // scroll clear of the gesture bar rather than being cut off above it.
      child: SafeArea(
        bottom: false,
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Rack Contents',
                                style: TextStyle(
                                    color: scheme.textMuted, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(
                              rackId,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: scheme.text),
                            ),
                            if (itemDetailsFailed) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      size: 14, color: scheme.textMuted),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Item details could not be loaded.',
                                      style: TextStyle(
                                          color: scheme.textMuted,
                                          fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        style: IconButton.styleFrom(
                            backgroundColor: scheme.subtle),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Scrollbar(
                    controller: scrollController,
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      itemCount: entries.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        if (index == entries.length) {
                          return ListEndFooter(
                            hasMore: false,
                            bottomPadding: bottomInset,
                            label: rackContentsFooterLabel(entries),
                          );
                        }
                        final entry = entries[index];
                        return RackContentsCard(
                          entry: entry,
                          imageUrl: itemImageUrl(baseUrl, entry.image),
                          onTap: onItemTap == null
                              ? null
                              : () => onItemTap!(entry.itemCode),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "End of list" marker with the rack's item count and Balance Qty total.
/// The unit is named only when every row shares one.
String rackContentsFooterLabel(List<RackContentsEntry> entries) {
  final count = entries.length;
  final total = FormattingHelper.formatQtyGrouped(rackQtyTotal(entries));
  final uom = sharedStockUom(entries);
  final items = count == 1 ? '1 item' : '$count items';
  return 'End of list · $items · Balance Qty $total${uom == null ? '' : ' $uom'}';
}

/// One item on the rack. Balance Qty is the largest figure on the card;
/// Variant Of is the most prominent Item field, then the item's identity,
/// then the supporting fields under their Item DocType labels.
class RackContentsCard extends StatelessWidget {
  const RackContentsCard({
    super.key,
    required this.entry,
    required this.imageUrl,
    this.onTap,
  });

  final RackContentsEntry entry;

  /// Full image URL, or null for the placeholder.
  final String? imageUrl;
  final VoidCallback? onTap;

  static const double imageSize = 72;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final empty = entry.balanceQty == 0;

    final fields = <(String, String)>[
      if (entry.countryOfOrigin != null)
        ('Country of Origin', entry.countryOfOrigin!),
      if (entry.itemGroup != null) ('Item Group', entry.itemGroup!),
      if (entry.brand != null) ('Brand', entry.brand!),
      if (entry.batchNo != null) ('Batch No', entry.batchNo!),
    ];

    return Material(
      color: scheme.subtle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RackItemImage(
                    url: imageUrl,
                    size: imageSize,
                    itemCode: entry.itemCode,
                    itemName: entry.itemName,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (entry.variantOf != null) ...[
                          Text('Variant Of',
                              style: TextStyle(
                                  fontSize: 11, color: scheme.textMuted)),
                          Text(
                            entry.variantOf!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: scheme.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          entry.itemName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: scheme.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.itemCode,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: scheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 64),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          FormattingHelper.formatQtyGrouped(entry.balanceQty),
                          key: const ValueKey('rack-card-qty'),
                          style: TextStyle(
                            fontSize: 28,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: empty ? scheme.textMuted : scheme.text,
                          ),
                        ),
                        if (entry.stockUom != null)
                          Text(entry.stockUom!,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.textMuted)),
                        Text('Balance Qty',
                            style: TextStyle(
                                fontSize: 10, color: scheme.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              if (entry.disabled ||
                  fields.isNotEmpty ||
                  entry.description != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    if (entry.disabled)
                      _StatusTag(
                        label: 'Disabled',
                        base: AppColors.red500,
                        ink: isDark ? AppColors.red300 : AppColors.red700,
                      ),
                    for (final (label, value) in fields)
                      _LabelledValue(label: label, value: value),
                  ],
                ),
                if (entry.description != null) ...[
                  const SizedBox(height: 8),
                  _LabelledValue(
                    label: 'Description',
                    value: entry.description!,
                    maxLines: 2,
                    expand: true,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LabelledValue extends StatelessWidget {
  const _LabelledValue({
    required this.label,
    required this.value,
    this.maxLines = 1,
    this.expand = false,
  });

  final String label;
  final String value;
  final int maxLines;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: scheme.textMuted)),
        Text(
          value,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: scheme.text,
          ),
        ),
      ],
    );
    if (expand) return SizedBox(width: double.infinity, child: column);
    // A long value in the Wrap must ellipsise, not overflow the card.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: column,
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({
    required this.label,
    required this.base,
    required this.ink,
  });

  final String label;
  final Color base;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: base.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
    );
  }
}

/// Item image, or a neutral placeholder when there is none or it fails to
/// load. Tapping a real image enlarges it in place.
class _RackItemImage extends StatelessWidget {
  const _RackItemImage({
    required this.url,
    required this.size,
    required this.itemCode,
    required this.itemName,
  });

  final String? url;
  final double size;
  final String itemCode;
  final String itemName;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    Widget placeholder() => Container(
          key: const ValueKey('rack-card-image-placeholder'),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: scheme.fg,
            border: Border.all(color: scheme.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.inventory_2_outlined,
              size: size * 0.45, color: scheme.textSubtle),
        );

    final src = url;
    if (src == null) return placeholder();

    final cache =
        (size * MediaQuery.devicePixelRatioOf(context)).round();
    return GestureDetector(
      onTap: () => showItemImagePreview(context, src, itemCode, itemName),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          src,
          key: const ValueKey('rack-card-image'),
          width: size,
          height: size,
          cacheWidth: cache,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : Container(width: size, height: size, color: scheme.fg),
          errorBuilder: (_, __, ___) => placeholder(),
        ),
      ),
    );
  }
}
