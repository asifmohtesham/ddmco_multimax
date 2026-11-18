import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/stock_sheet/model/review_models.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/rack_chips.dart';

/// The review list: one row per item read from a photo (a photo of several
/// items gives several rows), and one per photo or code that resolved to no
/// item. Drag to reorder, a switch to leave the item off the sheet.
class ReviewList extends StatefulWidget {
  const ReviewList({
    super.key,
    required this.entries,
    required this.thumbnails,
    required this.onReorder,
    required this.onToggle,
    required this.onFix,
    required this.onRetryCheck,
    required this.onRemove,
    this.removeEnabled = true,
    this.recheckBusy,
  });

  final List<ReviewEntry> entries;

  /// JPEG thumbnails: photos keyed by path, ERP images by
  /// [ItemInfo.thumbnailKey]. An item's row shows its ERP image (a
  /// placeholder when it has none); a row with no item shows its photo.
  final Map<String, Uint8List> thumbnails;

  Uint8List? _thumbnailFor(ReviewEntry entry) => entry.resolved
      ? thumbnails[ItemInfo.thumbnailKey(entry.items.first.info.itemCode)]
      : thumbnails[entry.path];

  /// Receives the raw `ReorderableListView` indices (not adjusted).
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index, bool included) onToggle;

  /// "Type or scan code" was tapped on an unresolved row.
  final void Function(int index) onFix;
  final void Function(int index) onRetryCheck;

  /// A row was swiped away (end to start), or the screen reader's
  /// "Remove item" / "Remove photo" action was used. The owner removes the photo and returns
  /// whether it did; a row that was not removed springs back.
  final bool Function(int index) onRemove;

  /// False while the list is changing: rows then do not swipe.
  final bool removeEnabled;

  /// Drives the `Retry check` buttons' spinner (the controller's `rechecking`).
  final RxBool? recheckBusy;

  @override
  State<ReviewList> createState() => _ReviewListState();
}

class _ReviewListState extends State<ReviewList> {
  final _scroll = ScrollController();
  final _idle = false.obs;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final entries = widget.entries;
    return Scrollbar(
      controller: _scroll,
      child: ReorderableListView.builder(
        scrollController: _scroll,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        itemCount: entries.length,
        // Raw indices (not adjusted) are what the controller expects.
        // ignore: deprecated_member_use
        onReorder: widget.onReorder,
        footer: Padding(
          padding: EdgeInsets.fromLTRB(0, 16, 0, 24 + bottomInset),
          child: Center(
            child: Text(
              'End of list',
              style: TextStyle(fontSize: 12, color: s.textMuted),
            ),
          ),
        ),
        itemBuilder: (context, i) => KeyedSubtree(
          // The reorderable list keys its children by this outer key.
          key: ValueKey(entries[i].id),
          child: Dismissible(
            key: ValueKey('dismiss-${entries[i].id}'),
            direction: widget.removeEnabled
                ? DismissDirection.endToStart
                : DismissDirection.none,
            background: const _RemoveBackground(),
            secondaryBackground: const _RemoveBackground(),
            // Removing here (not in onDismissed, ~300 ms later) means a
            // refusal keeps the row on the sheet.
            confirmDismiss: (_) async => widget.onRemove(i),
            child: Semantics(
              // The swipe has no screen-reader equivalent; this is it.
              customSemanticsActions: widget.removeEnabled
                  ? {
                      CustomSemanticsAction(
                        label: entries[i].resolved
                            ? 'Remove item'
                            : 'Remove photo',
                      ): () => widget.onRemove(i),
                    }
                  : null,
              child: _ReviewRow(
                index: i,
                entry: entries[i],
                thumbnail: widget._thumbnailFor(entries[i]),
                recheckBusy: widget.recheckBusy ?? _idle,
                onToggle: widget.onToggle,
                onFix: widget.onFix,
                onRetryCheck: widget.onRetryCheck,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The red strip under a row being swiped away.
class _RemoveBackground extends StatelessWidget {
  const _RemoveBackground();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.red700,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.index,
    required this.entry,
    required this.thumbnail,
    required this.recheckBusy,
    required this.onToggle,
    required this.onFix,
    required this.onRetryCheck,
  });

  final int index;
  final ReviewEntry entry;
  final Uint8List? thumbnail;
  final RxBool recheckBusy;
  final void Function(int, bool) onToggle;
  final void Function(int) onFix;
  final void Function(int) onRetryCheck;

  static const _mono = 'ShureTechMono';

  String get _reason {
    if (entry.decodeFailed) return 'Unreadable photo';
    if (entry.notInErp.isNotEmpty) {
      return 'Not in ERP: ${entry.notInErp.join(', ')}';
    }
    if (entry.unchecked) return 'Stock not checked';
    return 'No recognised code';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final resolved = entry.resolved;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 10, 8, 10),
        decoration: BoxDecoration(
          color: s.fg,
          border: Border.all(color: s.border),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 14,
                ),
                child: Icon(
                  Icons.drag_indicator,
                  size: 20,
                  color: s.textSubtle,
                ),
              ),
            ),
            _Thumb(bytes: thumbnail),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.typed) _tag(context, 'Typed'),
                  if (resolved)
                    _item(context, entry.items.single)
                  else ...[
                    Text(
                      _reason,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: s.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _fixPill(context),
                  ],
                  if (entry.unchecked) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AsyncFilledButton(
                        busy: recheckBusy,
                        onPressed: () => onRetryCheck(index),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: 'Retry check',
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Switch(
              value: resolved && entry.included,
              onChanged: resolved ? (v) => onToggle(index, v) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(BuildContext context, String text) {
    final s = context.scheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: s.subtle,
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: s.textMuted)),
    );
  }

  Widget _item(BuildContext context, ReviewItem item) {
    final s = context.scheme;
    final variantOf = item.info.variantOf;
    final sub = [
      item.code.barcode,
      if (variantOf != null && variantOf.isNotEmpty) variantOf,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.info.itemName ?? item.info.itemCode,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: s.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          sub,
          style: TextStyle(fontFamily: _mono, fontSize: 12, color: s.textMuted),
        ),
        // A null stock means no Stock Balance row: the pill says out of stock.
        const SizedBox(height: 4),
        RackChips(stock: item.stock),
      ],
    );
  }

  Widget _fixPill(BuildContext context) {
    final s = context.scheme;
    return OutlinedButton(
      onPressed: () => onFix(index),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: s.text,
        side: BorderSide(color: s.borderStrong),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 12),
      ),
      child: const Text('✎ Type or scan code'),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final placeholder = Icon(Icons.image_outlined, color: s.textSubtle);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: 54,
        height: 54,
        color: s.subtle,
        alignment: Alignment.center,
        child: bytes == null
            ? placeholder
            : Image.memory(
                bytes!,
                width: 54,
                height: 54,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}
