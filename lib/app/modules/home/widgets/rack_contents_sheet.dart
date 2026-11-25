import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/item_image.dart'
    show showItemImagePreview;
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_anchor.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_controller.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_sheet.dart';
import 'package:multimax/app/modules/home/rack_contents_fields.dart';
import 'package:multimax/app/modules/home/rack_contents_logic.dart';
import 'package:multimax/app/modules/home/rack_scan_logic.dart'
    show rackLookupFailure;

/// Loads the rack's contents as on a date; throws when the Stock Balance
/// request fails.
typedef RackContentsLoader =
    Future<RackContentsSnapshot> Function(DateTime asOf);

/// Dashboard rack scan result: every item on [rackId] with its Balance Qty
/// from the Stock Balance report and its Item master fields.
///
/// The header's date button re-runs the report for another day through
/// [loadAsOf] (stock as it stood at the end of that day), and the search
/// field narrows the cards on the phone without another request.
///
/// [itemDetailsFailed] is true when the Item fetch failed; the cards then
/// show the report data alone and the header says so quietly.
class RackContentsSheet extends StatefulWidget {
  const RackContentsSheet({
    super.key,
    required this.rackId,
    required this.entries,
    required this.baseUrl,
    this.warehouse,
    this.columns,
    this.itemDetailsFailed = false,
    this.initialOwnerIsCurrent,
    this.asOf,
    this.loadAsOf,
    this.onItemTap,
  });

  final String rackId;
  final String? warehouse;
  final List<DeskColumn>? columns;

  /// The contents as on [asOf], already loaded when the sheet opens.
  final List<RackContentsEntry> entries;

  /// Server origin that Item `image` paths are relative to.
  final String baseUrl;
  final bool itemDetailsFailed;
  final bool Function()? initialOwnerIsCurrent;

  /// The day [entries] were taken at; null means today.
  final DateTime? asOf;

  /// Reloads the rack for a picked date; null leaves the date fixed.
  final RackContentsLoader? loadAsOf;

  /// Opens the tapped item; null leaves the cards inert.
  final ValueChanged<String>? onItemTap;

  @override
  State<RackContentsSheet> createState() => _RackContentsSheetState();
}

class _RackContentsSheetState extends State<RackContentsSheet> {
  late DateTime _asOf;
  List<RackContentsEntry> _entries = const [];
  bool _itemDetailsFailed = false;
  String _baseUrl = '';
  List<DeskColumn>? _columns;
  late final _fields = ScopedReportFieldsController.forReport(
    rackContentsFields(),
  );
  late final Worker _ownerWorker;
  int _ownerGeneration = 0;
  bool _hasResult = false;
  bool _loading = false;
  String? _loadError;

  final _search = TextEditingController();
  String _query = '';

  static final _dateLabel = DateFormat('d MMM yyyy');

  @override
  void initState() {
    super.initState();
    _asOf = widget.asOf ?? DateTime.now();
    _ownerGeneration = _fields.ownerGeneration;
    _ownerWorker = ever(_fields.state, (_) {
      final owner = _fields.ownerGeneration;
      if (owner == _ownerGeneration) return;
      _ownerGeneration = owner;
      setState(() {
        _entries = const [];
        _hasResult = false;
        _itemDetailsFailed = false;
        _baseUrl = '';
        _loadError = null;
        _columns = null;
        _loading = false;
      });
    });
    unawaited(_fields.bind());
    if (widget.initialOwnerIsCurrent?.call() ?? true) {
      _entries = widget.entries;
      _hasResult = true;
      _itemDetailsFailed = widget.itemDetailsFailed;
      _baseUrl = widget.baseUrl;
      _columns = widget.columns;
      _fields.replaceDefinition(rackContentsFields(widget.columns));
    }
  }

  @override
  void dispose() {
    _ownerWorker.dispose();
    _fields.dispose();
    _search.dispose();
    super.dispose();
  }

  bool get _isToday => isSameDay(_asOf, DateTime.now());

  Future<void> _pickDate() async {
    if (_loading || widget.loadAsOf == null) return;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _asOf.isAfter(now) ? now : _asOf,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: 'Stock as on',
    );
    if (picked == null || !mounted) return;
    await _load(picked);
  }

  /// Re-runs the report for [date]. The shown date only changes once the new
  /// rows are in, so a failed load leaves the previous day's list and its
  /// date together.
  Future<void> _load(DateTime date) async {
    final loader = widget.loadAsOf;
    if (loader == null || _loading) return;
    final owner = _fields.ownerGeneration;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final snapshot = await loader(date);
      if (!mounted ||
          owner != _fields.ownerGeneration ||
          snapshot.isCurrentOwner?.call() == false) {
        return;
      }
      _fields.replaceDefinition(rackContentsFields(snapshot.columns));
      setState(() {
        _asOf = date;
        _entries = snapshot.entries;
        _hasResult = true;
        _itemDetailsFailed = snapshot.itemDetailsFailed;
        _baseUrl = snapshot.baseUrl ?? _baseUrl;
        _columns = snapshot.columns;
      });
    } catch (e) {
      if (!mounted || owner != _fields.ownerGeneration) return;
      final failure = rackLookupFailure(e);
      setState(
        () => _loadError =
            'Could not load stock as on ${_dateLabel.format(date)}. '
            '${failure.message}',
      );
    } finally {
      if (mounted && owner == _fields.ownerGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final shown = filterRackContents(_entries, _query);
    final ids = rackContentsOccurrenceIds(widget.rackId, shown);

    return Container(
      decoration: BoxDecoration(
        color: scheme.fg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        bottom: false,
        child: DraggableScrollableSheet(
          initialChildSize: .7,
          minChildSize: .5,
          maxChildSize: .95,
          expand: false,
          builder: (context, scroll) => Obx(() {
            final fields = _fields.state.value;
            return ReportFieldsResults(
              controller: _fields,
              scrollController: scroll,
              result: (_entries, _query, _asOf),
              occurrenceIds: ids,
              builder: (context, anchors) => CustomScrollView(
                controller: scroll,
                slivers: [
                  anchors.header(
                    DocTypeListHeader(
                      title: 'Rack Contents',
                      extraActions: [ReportFieldsAction(controller: _fields)],
                    ),
                  ),
                  SliverToBoxAdapter(child: _rackControls(context)),
                  if (shown.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: bottomInset),
                        child: _emptyState(context),
                      ),
                    )
                  else ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      sliver: SliverList.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, index) {
                          final entry = shown[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: anchors.row(
                              ids[index],
                              index,
                              RackContentsCard(
                                entry: entry,
                                fields: fields,
                                columns: _columns,
                                imageUrl: itemImageUrl(_baseUrl, entry.image),
                                onTap: widget.onItemTap == null
                                    ? null
                                    : () => widget.onItemTap!(entry.itemCode),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ListEndFooter(
                          hasMore: false,
                          bottomPadding: bottomInset,
                          label: rackContentsFooterLabel(
                            shown,
                            outOf: _entries.length,
                            balanceLabel: _rackLabel(fields, 'bal_qty'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _rackControls(BuildContext context) {
    final scheme = context.scheme;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final warehouse = widget.warehouse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.rackId,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.text,
                ),
              ),
              if (warehouse != null && warehouse.isNotEmpty)
                Text(
                  warehouse,
                  semanticsLabel:
                      '${rackContentsIdentityLabel(_columns, 'warehouse')} $warehouse',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.textMuted,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('rack-as-of'),
                onPressed: widget.loadAsOf == null || _loading
                    ? null
                    : _pickDate,
                icon: _loading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.textMuted,
                        ),
                      )
                    : const Icon(Icons.calendar_today, size: 16),
                label: Text(
                  'As on ${_dateLabel.format(_asOf)}'
                  '${_isToday ? ' · Today' : ''}',
                ),
              ),
              if (!_isToday && widget.loadAsOf != null)
                TextButton(
                  onPressed: _loading ? null : () => _load(DateTime.now()),
                  child: const Text('Today'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: _RackSearchField(
            controller: _search,
            onChanged: (query) => setState(() => _query = query),
            onClear: _clearSearch,
          ),
        ),
        if (_loadError != null)
          _HeaderNote(
            key: const ValueKey('rack-load-error'),
            icon: Icons.error_outline,
            text: _loadError!,
            color: isDark ? AppColors.red300 : AppColors.red700,
          ),
        if (_itemDetailsFailed)
          _HeaderNote(
            icon: Icons.info_outline,
            text: 'Item details could not be loaded.',
            color: scheme.textMuted,
          ),
        if (_loading)
          const LinearProgressIndicator(minHeight: 2)
        else
          const Divider(height: 2, thickness: 1),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    final date = _dateLabel.format(_asOf);
    return ListEmptyState(
      hasActiveFilters: _entries.isNotEmpty,
      emptyIcon: Icons.inventory_2_outlined,
      emptyTitle: _hasResult ? 'Rack was empty' : 'Reload rack contents',
      emptyMessage: _hasResult
          ? 'Nothing was on ${widget.rackId} on $date.'
          : 'Load stock for this account.',
      filteredTitle: 'No matching items',
      filteredMessage:
          'Nothing on ${widget.rackId} on $date matches "${_query.trim()}".',
      onClearFilters: _clearSearch,
      onReload: () => _load(_asOf),
      emptyAction: !_hasResult && widget.loadAsOf != null
          ? FilledButton.tonalIcon(
              onPressed: _loading ? null : () => _load(_asOf),
              icon: const Icon(Icons.refresh),
              label: const Text('Reload'),
            )
          : _isToday || widget.loadAsOf == null
          ? null
          : FilledButton.tonalIcon(
              onPressed: _loading ? null : () => _load(DateTime.now()),
              icon: const Icon(Icons.today),
              label: const Text('Back to Today'),
            ),
    );
  }
}

/// The sheet's search box; filters the loaded cards on the phone.
class _RackSearchField extends StatelessWidget {
  const _RackSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        key: const ValueKey('rack-search'),
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search code, name, variant, brand',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close),
                  onPressed: onClear,
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

/// One quiet line under the sheet header.
class _HeaderNote extends StatelessWidget {
  const _HeaderNote({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// "End of list" marker with the item count and Balance Qty total of the
/// cards shown. While a search narrows the list, [outOf] (the rack's full
/// count) is named too. The unit is named only when every row shares one.
String rackContentsFooterLabel(
  List<RackContentsEntry> entries, {
  int? outOf,
  String balanceLabel = 'Balance Qty',
}) {
  final count = entries.length;
  final total = FormattingHelper.formatQtyGrouped(rackQtyTotal(entries));
  final uom = sharedStockUom(entries);
  final missing = entries.where((entry) => entry.balanceQty == null).length;
  final amount = switch (missing) {
    0 => '$total${uom == null ? '' : ' $uom'}',
    _ when missing == count => 'unavailable',
    _ => '$total${uom == null ? '' : ' $uom'} (incomplete)',
  };
  final items = outOf != null && outOf != count
      ? '$count of $outOf items'
      : count == 1
      ? '1 item'
      : '$count items';
  return 'End of list · $items · $balanceLabel $amount';
}

String _rackLabel(FieldsState? fields, String key) =>
    fields?.label(key) ?? rackContentsLabels[key]!;

/// One item on the rack. Balance Qty is the largest figure on the card;
/// Variant Of is the most prominent Item field, then the item's identity,
/// then the supporting fields under their Item DocType labels.
class RackContentsCard extends StatelessWidget {
  const RackContentsCard({
    super.key,
    required this.entry,
    required this.imageUrl,
    this.onTap,
    this.fields,
    this.columns,
  });

  final RackContentsEntry entry;
  final FieldsState? fields;
  final List<DeskColumn>? columns;

  /// Full image URL, or null for the placeholder.
  final String? imageUrl;
  final VoidCallback? onTap;

  static const double imageSize = 72;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final balance = entry.balanceQty;
    final balanceLabel = _rackLabel(fields, 'bal_qty');
    final visibleQuantity = fields?.shows('bal_qty') ?? true;

    final details = <(String, String)>[
      if (entry.countryOfOrigin != null)
        ('Country of Origin', entry.countryOfOrigin!),
      if (entry.itemGroup != null && (fields?.shows('item_group') ?? true))
        (_rackLabel(fields, 'item_group'), entry.itemGroup!),
      if (entry.brand != null) ('Brand', entry.brand!),
      if (entry.batchNo != null)
        (rackContentsIdentityLabel(columns, 'batch_no'), entry.batchNo!),
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
                          Text(
                            'Variant Of',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.textMuted,
                            ),
                          ),
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
                          semanticsLabel:
                              '${rackContentsIdentityLabel(columns, 'item_name')} ${entry.itemName}',
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
                          semanticsLabel:
                              '${rackContentsIdentityLabel(columns, 'item_code')} ${entry.itemCode}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: scheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (balance != null && visibleQuantity) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: 64,
                        maxWidth: (MediaQuery.sizeOf(context).width * .30)
                            .clamp(64.0, 160.0),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            FormattingHelper.formatQtyGrouped(balance),
                            key: const ValueKey('rack-card-qty'),
                            style: TextStyle(
                              fontSize: 28,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              color: balance == 0
                                  ? scheme.textMuted
                                  : scheme.text,
                            ),
                          ),
                          if (entry.stockUom != null &&
                              (fields?.shows('stock_uom') ?? true))
                            Text(
                              entry.stockUom!,
                              semanticsLabel:
                                  '${_rackLabel(fields, 'stock_uom')} ${entry.stockUom}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: scheme.textMuted,
                              ),
                            ),
                          Text(
                            balanceLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              if (balance == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '$balanceLabel unavailable',
                    style: TextStyle(color: scheme.textMuted),
                  ),
                ),
              if (entry.disabled ||
                  details.isNotEmpty ||
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
                    for (final (label, value) in details)
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
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink),
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
      child: Icon(
        Icons.inventory_2_outlined,
        size: size * 0.45,
        color: scheme.textSubtle,
      ),
    );

    final src = url;
    if (src == null) return placeholder();

    final cache = (size * MediaQuery.devicePixelRatioOf(context)).round();
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
