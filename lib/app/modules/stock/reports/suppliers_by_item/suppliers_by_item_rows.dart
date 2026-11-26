// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/data/utils/suppliers_by_item_labels.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/global_widgets/supplier_status_pill.dart';

import 'suppliers_by_item_fields.dart';
import 'suppliers_by_item_layout.dart';

typedef _Field = SuppliersByItemField;
typedef SuppliersByItemFieldCaption = String Function(SuppliersByItemField);
typedef SuppliersByItemColumnCaption = String Function(String, String);
String _defaultCaption(_Field field) => field.label;
typedef _Detail = ({String label, String value});
typedef _ItemPresentation = ({
  String? name,
  List<_Detail> metrics,
  List<String> qualifiers,
  List<SuppliersByItemBadge> badges,
  List<_Detail> details,
  List<String> warnings,
});
typedef _PurchasePresentation = ({
  String? lastBuy,
  String? spokenLastBuy,
  String? status,
  bool matched,
  bool filterMatch,
  List<SuppliersByItemBadge> badges,
  List<_Detail> details,
});

const _maxIndentDepth = 3;
const _indentStep = 14.0;
const _disclosureWidth = 24.0;
const _emptyCell = '–';
const _minSupplierNameWidth = 96.0;
const _columnGap = 10.0;
const _tabularFigures = [FontFeature.tabularFigures()];
const _nonBreakingSpace = '\u00a0';

// Keep a significant digit when two-decimal rounding would erase a quantity.
String _quantityLabel(num quantity) => quantity != 0 && quantity.abs() < 0.005
    ? quantity.toStringAsPrecision(1)
    : FormattingHelper.formatQtyGrouped(quantity.toDouble());

/// Where a row sits in its group's card: the group's first row rounds the top
/// corners, its last row the bottom ones, and every later row draws a hairline.
enum SuppliersByItemSegment {
  first,
  middle,
  last,
  only;

  static SuppliersByItemSegment of({required bool first, required bool last}) =>
      first
      ? (last ? only : SuppliersByItemSegment.first)
      : (last ? SuppliersByItemSegment.last : middle);

  bool get isFirst => this == first || this == only;
  bool get isLast => this == last || this == only;
}

bool _isComponent(SuppliersByItemRow row) =>
    row.kind == SuppliersByItemRowKind.component || row.isComponent;

/// Groups consecutive item or component siblings. Descendants interleaved in
/// the flat list leave their parents' sibling runs intact.
Map<SuppliersByItemRowKey, SuppliersByItemColumnRun> suppliersByItemColumnRuns(
  Iterable<SuppliersByItemLayoutRow> rows,
  bool Function(SuppliersByItemField) shows, [
  SuppliersByItemFieldCaption label = _defaultCaption,
  String? Function(SuppliersByItemLayoutRow)? groupUnit,
]) {
  final runs = <List<SuppliersByItemLayoutRow>>[];
  final active = <SuppliersByItemRowKey?, List<SuppliersByItemLayoutRow>>{};
  final suppliersByParent =
      <SuppliersByItemRowKey?, List<SuppliersByItemLayoutRow>>{};
  for (final row in rows) {
    final parent = row.parentKey;
    if (row.group != null || row.isPairOccurrence) {
      active.remove(parent);
      if (row.isPairOccurrence) {
        (suppliersByParent[parent] ??= []).add(row);
      }
      continue;
    }
    final kind = row.node.row.kind;
    if (kind == SuppliersByItemRowKind.supplier) {
      (suppliersByParent[parent] ??= []).add(row);
    }
    if (kind != SuppliersByItemRowKind.item &&
        kind != SuppliersByItemRowKind.component) {
      active.remove(parent);
      continue;
    }
    final current = active[parent];
    if (current != null &&
        current.first.node.row.kind == kind &&
        _isComponent(current.first.node.row) == _isComponent(row.node.row)) {
      current.add(row);
    } else {
      final next = [row];
      active[parent] = next;
      runs.add(next);
    }
  }
  final byRow = <SuppliersByItemRowKey, SuppliersByItemColumnRun>{};
  for (final siblings in [...runs, ...suppliersByParent.values]) {
    if (siblings.length < 2) continue;
    final run = SuppliersByItemColumnRun._(
      siblings,
      shows,
      label,
      groupUnit ?? _noGroupUnit,
    );
    for (final row in siblings) {
      byRow[row.key] = run;
    }
  }
  return byRow;
}

String? _noGroupUnit(SuppliersByItemLayoutRow _) => null;

class SuppliersByItemColumnRun {
  SuppliersByItemColumnRun._(
    this._rows,
    this._shows,
    this._label,
    this._groupUnit,
  );

  final List<SuppliersByItemLayoutRow> _rows;
  final bool Function(SuppliersByItemField) _shows;
  final SuppliersByItemFieldCaption _label;
  final String? Function(SuppliersByItemLayoutRow) _groupUnit;
  Object? _tableLayout;
  List<double>? _tableWidths;

  bool _startsWith(SuppliersByItemLayoutRow row) => _rows.first.key == row.key;

  List<double>? _supplierWidths(
    BuildContext context,
    double availableWidth,
    List<SuppliersByItemField> columns,
    TextStyle? captionStyle,
    TextStyle? valueStyle,
  ) {
    final layout = (
      availableWidth,
      Directionality.of(context),
      MediaQuery.textScalerOf(context),
      Object.hashAll(columns),
      captionStyle,
      valueStyle,
    );
    if (_tableLayout == layout) return _tableWidths;
    _tableLayout = layout;
    return _tableWidths = _supplierColumnWidths(
      context,
      availableWidth,
      [for (final row in _rows) (row.pairNode ?? row.node).row],
      columns,
      _shows,
      _label,
      captionStyle,
      valueStyle,
    );
  }

  ({
    double width,
    TextDirection direction,
    TextScaler scaler,
    TextStyle? captionStyle,
    TextStyle? valueStyle,
    TextStyle? codeStyle,
  })?
  _lastLayout;
  List<double>? _lastWidths;
  ({TextDirection direction, TextScaler scaler, TextStyle? style})?
  _lastBuyLayout;
  double _widestLastBuy = 0;

  double _lastBuyWidth(BuildContext context, TextStyle? style) {
    final layout = (
      direction: Directionality.of(context),
      scaler: MediaQuery.textScalerOf(context),
      style: style,
    );
    if (_lastBuyLayout != layout) {
      _lastBuyLayout = layout;
      _widestLastBuy = 0;
      final measured = <String, double>{};
      for (final row in _rows) {
        final label = _lastBuyLabel(
          strictReportDate((row.pairNode ?? row.node).row.lastPurchaseDate),
          _label(_Field.supplierLastBuyColumn),
        );
        final width = measured.putIfAbsent(
          label,
          () => _width(context, label, style),
        );
        if (width > _widestLastBuy) _widestLastBuy = width;
      }
    }
    return _widestLastBuy;
  }

  /// Null means the available width requires this run to use inline captions.
  List<double>? _widths(
    BuildContext context,
    double availableWidth,
    TextStyle? captionStyle,
    TextStyle? valueStyle,
    TextStyle? codeStyle,
    List<_Detail> metrics,
  ) {
    final layout = (
      width: availableWidth,
      direction: Directionality.of(context),
      scaler: MediaQuery.textScalerOf(context),
      captionStyle: captionStyle,
      valueStyle: valueStyle,
      codeStyle: codeStyle,
    );
    if (_lastLayout == layout) return _lastWidths;
    _lastLayout = layout;
    _lastWidths = null;
    if (metrics.isEmpty) return _lastWidths = const [];

    final maximum =
        availableWidth -
        _disclosureWidth -
        metrics.length * _columnGap -
        _width(context, '00000000', codeStyle);
    final widths = [
      for (final metric in metrics) _width(context, metric.label, captionStyle),
    ];
    var required = widths.fold(0.0, (total, width) => total + width);
    if (required > maximum) return null;
    final measured = <String, double>{};
    for (final row in _rows) {
      final values = _itemMetrics(row, _shows, _label, _groupUnit(row));
      for (var i = 0; i < values.length; i++) {
        final value = values[i].value;
        final width = measured.putIfAbsent(
          value,
          () => _width(context, value, valueStyle),
        );
        if (width <= widths[i]) continue;
        required += width - widths[i];
        if (required > maximum) return null;
        widths[i] = width;
      }
    }
    return _lastWidths = widths;
  }
}

class SuppliersByItemDisplayTile extends StatelessWidget {
  const SuppliersByItemDisplayTile({
    super.key,
    required this.entry,
    required this.shows,
    required this.includeDrafts,
    required this.supplierFilterActive,
    required this.expanded,
    required this.evidenceExpanded,
    this.onToggleBranch,
    this.onToggleEvidence,
    this.columnRun,
    this.parentOutputUom,
    this.fieldLabel = _defaultCaption,
    this.columnLabel,
    this.segment = SuppliersByItemSegment.only,
    this.groupUnit,
    this.supplierColumns = const [],
  });

  final SuppliersByItemLayoutRow entry;
  final bool Function(SuppliersByItemField) shows;
  final bool includeDrafts;
  final bool supplierFilterActive;
  final bool expanded;
  final bool evidenceExpanded;
  final VoidCallback? onToggleBranch;
  final VoidCallback? onToggleEvidence;
  final SuppliersByItemColumnRun? columnRun;
  final String? parentOutputUom;
  final SuppliersByItemFieldCaption fieldLabel;
  final SuppliersByItemColumnCaption? columnLabel;

  /// Position in the group's card.
  final SuppliersByItemSegment segment;

  /// The template's Stock UOM, shown once in its header. Rows in that unit
  /// leave it out.
  final String? groupUnit;

  /// Supplier table columns, in order. Empty shows the supplier name only.
  final List<SuppliersByItemField> supplierColumns;

  /// Card-coloured space closing every row of a group but its last.
  static const rowGap = 4.0;

  SuppliersByItemRow get _row => entry.node.row;

  bool get _sharesGroupUnit =>
      groupUnit != null &&
      _row.kind != SuppliersByItemRowKind.template &&
      _row.stockUom == groupUnit;

  bool get _supplierBand =>
      entry.group == null &&
      !entry.isPairOccurrence &&
      (_row.kind == SuppliersByItemRowKind.supplier ||
          _row.kind == SuppliersByItemRowKind.placeholder);

  String? get _depthLabel =>
      entry.depth > _maxIndentDepth ? 'Depth ${entry.depth}' : null;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    const radius = Radius.circular(AppRadius.lg);
    final shape = BorderRadius.vertical(
      top: segment.isFirst ? radius : Radius.zero,
      bottom: segment.isLast ? radius : Radius.zero,
    );
    final indent = (entry.depth - 1).clamp(0, _maxIndentDepth) * _indentStep;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: shape,
        child: ColoredBox(
          color: _supplierBand ? scheme.subtle : scheme.fg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!segment.isFirst) Container(height: 1, color: scheme.border),
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: 4 + indent,
                  end: 4,
                  bottom: segment.isLast ? 0 : rowGap,
                ),
                child: switch ((
                  entry.group,
                  entry.isPairOccurrence,
                  _row.kind,
                )) {
                  (final group?, _, _) => _group(context, group),
                  (_, true, _) => _pairOccurrence(context),
                  (_, _, SuppliersByItemRowKind.supplier) => _supplier(context),
                  (_, _, SuppliersByItemRowKind.bom) => _bom(context),
                  (_, _, SuppliersByItemRowKind.placeholder) => _placeholder(
                    context,
                  ),
                  _ => _item(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  _ItemPresentation _itemPresentation({bool pairOccurrence = false}) {
    final isComponent = _isComponent(_row);
    final isTemplate = _row.kind == SuppliersByItemRowKind.template;
    final unit = _stockUom(
      isComponent ? _Field.componentStockUom : _Field.itemStockUom,
      forceUnit: isTemplate,
    );
    final name = _row.distinctItemName;
    final hasComparableQuantities = !isTemplate || _row.stockUom != null;
    final componentPurchaseDate = pairOccurrence
        ? entry.pairNode?.row.lastPurchaseDate
        : _row.lastPurchaseDate;
    final metrics = _itemMetrics(entry, shows, fieldLabel, groupUnit);
    final showsPlaceholder =
        expanded &&
        entry.children.any(
          (child) => child.node.row.kind == SuppliersByItemRowKind.placeholder,
        );
    final badges = [
      if (!isTemplate && !entry.hasDirectSupplier && !showsPlaceholder)
        const SuppliersByItemBadge(
          SuppliersByItemColumnLabels.noSupplierRecorded,
          'Disabled',
        ),
      if (!pairOccurrence && !isComponent && !isTemplate)
        ..._poBadges(_row, supplier: false, detailsVisible: true),
      if (!isComponent && _row.isBelowReorderLevel)
        SuppliersByItemBadge(
          '${fieldLabel(_Field.itemProjected)} below ${fieldLabel(_Field.itemReorderLevel)}',
          'On Hold',
        ),
    ];
    final qualifiers = [
      if (isTemplate && shows(_Field.templateVariantCount))
        countLabel(entry.variantCount, 'variant'),
      ?_depthLabel,
    ];
    final details = <_Detail>[
      if (hasComparableQuantities) ...[
        if (shows(
          isComponent ? _Field.componentProjected : _Field.itemProjected,
        ))
          if (_amount(_row.projectedQty, unit) case final value?)
            (label: fieldLabel(_Field.itemProjected), value: value),
        if (!isComponent) ...[
          if (shows(_Field.itemReorderLevel))
            if (_amount(_row.reorderLevel, unit) case final value?)
              (label: fieldLabel(_Field.itemReorderLevel), value: value),
          if (shows(_Field.itemReorderQty))
            if (_amount(_row.reorderQty, unit) case final value?)
              (label: fieldLabel(_Field.itemReorderQty), value: value),
          if (shows(_Field.itemOpenOrders))
            if (_amount(_row.openOrderQty, unit) case final value?)
              (label: fieldLabel(_Field.itemOpenOrders), value: value),
          if (includeDrafts && shows(_Field.itemDraftOrders))
            if (_amount(_row.draftOrderQty, unit) case final value?)
              (label: fieldLabel(_Field.itemDraftOrders), value: value),
          if (shows(_Field.itemQtyReceived))
            if (_amount(_row.totalQtyReceived, unit) case final value?)
              (label: fieldLabel(_Field.itemQtyReceived), value: value),
        ],
      ],
      if (isComponent) ...[
        if (shows(_Field.componentQtyPerUnit))
          if (_amount(_row.bomQtyPerUnit, unit) case final value?)
            (
              label: fieldLabel(_Field.componentQtyPerUnit),
              value:
                  '$value per ${unit == null ? 'unit' : entry.parentOutputUom ?? parentOutputUom ?? 'unit'}',
            ),
        if (shows(_Field.componentLastPurchase))
          if (componentPurchaseDate case final value?)
            (label: fieldLabel(_Field.supplierLastPurchase), value: value),
        if (shows(_Field.componentUsedInBoms))
          if (_row.usedInBomCount case final count?)
            (label: 'Used in', value: countLabel(count, 'BOM')),
      ],
    ];
    final unavailableUnit = '${fieldLabel(_Field.itemStockUom)} unavailable';
    final unitSuffix = '($unavailableUnit)';
    final warnings = [
      if (!isComponent &&
          _row.stockUom == null &&
          _row.hasStockQuantities &&
          !metrics.any((metric) => metric.value.endsWith(unitSuffix)) &&
          !details.any((detail) => detail.value.endsWith(unitSuffix)) &&
          !badges.any((badge) => badge.label.endsWith(unitSuffix)))
        unavailableUnit,
      if (isComponent && _row.includeInManufacturing == false)
        'Not used in manufacturing',
      if (isComponent && _row.bomCycle) 'BOM cycle detected',
      if (isComponent && _row.bomDepthLimit) 'BOM depth limit reached',
    ];
    return (
      name: name,
      metrics: metrics,
      qualifiers: qualifiers,
      badges: badges,
      details: details,
      warnings: warnings,
    );
  }

  Widget _item() {
    final item = _itemPresentation();
    final isTemplate = _row.kind == SuppliersByItemRowKind.template;
    final role = _isComponent(_row) ? 'Component' : 'Item';
    if (isTemplate) {
      final variants = shows(_Field.templateVariantCount)
          ? countLabel(entry.variantCount, 'variant')
          : null;
      return _TileSurface(
        label: [
          '$role ${_row.itemTitle}',
          if (item.name case final name?)
            '${fieldLabel(_Field.itemName)} $name',
          for (final metric in item.metrics) _metricSemantics(metric),
          ...item.qualifiers,
          for (final badge in item.badges) badge.label,
          for (final detail in item.details) '${detail.label} ${detail.value}',
          ...item.warnings,
        ].join(', '),
        heading: true,
        onTap: onToggleBranch,
        expanded: entry.children.isEmpty ? null : expanded,
        child: _TemplateHeader(
          identity: _row.itemTitle,
          name: item.name,
          stats: [
            if (variants != null)
              (label: 'Variants', value: '${entry.variantCount}'),
            ...item.metrics,
          ],
          notes: [
            for (final qualifier in item.qualifiers)
              if (qualifier != variants) qualifier,
            for (final detail in item.details)
              '${detail.label} ${detail.value}',
            ...item.warnings,
          ],
          badges: item.badges,
          expanded: onToggleBranch == null ? null : expanded,
        ),
      );
    }
    return _TileSurface(
      label: [
        '$role ${_row.itemTitle}',
        if (item.name case final name?) '${fieldLabel(_Field.itemName)} $name',
        for (final metric in item.metrics) _metricSemantics(metric),
        ...item.qualifiers,
        for (final badge in item.badges) badge.label,
        for (final detail in item.details) '${detail.label} ${detail.value}',
        ...item.warnings,
      ].join(', '),
      heading: isTemplate,
      onTap: onToggleBranch,
      expanded: entry.children.isEmpty ? null : expanded,
      child: _ItemContent(
        identity: _row.itemTitle,
        name: item.name,
        metrics: item.metrics,
        qualifiers: item.qualifiers,
        badges: item.badges,
        details: item.details,
        warnings: item.warnings,
        expanded: expanded,
        hasDisclosure: onToggleBranch != null,
        columnRun: columnRun,
        showColumnHeadings: columnRun?._rows.first.key == entry.key,
      ),
    );
  }

  _PurchasePresentation _purchasePresentation(SuppliersByItemRow pair) {
    final date = strictReportDate(pair.lastPurchaseDate);
    final lastBuy = date == null || shows(_Field.supplierLastBuyColumn)
        ? _lastBuyLabel(date, fieldLabel(_Field.supplierLastBuyColumn))
        : null;
    final status = _visibleSupplierStatus(pair.supplierStatus);
    return (
      lastBuy: lastBuy,
      spokenLastBuy: lastBuy == null
          ? null
          : '${fieldLabel(_Field.supplierLastBuyColumn)} ${date == null ? 'unavailable' : DateFormat('d MMMM yyyy').format(date)}',
      status: status == entry.groupSupplierStatus ? null : status,
      matched: _highlightMatch(pair.matchedSupplier),
      filterMatch: supplierFilterActive && pair.matchedSupplier,
      badges: _poBadges(
        pair,
        supplier: true,
        detailsVisible: onToggleEvidence != null && evidenceExpanded,
      ),
      details: _supplierDetails(pair, shows, date, fieldLabel, includeDrafts),
    );
  }

  bool _highlightMatch(bool matched) =>
      shows(_Field.supplierMatchEmphasis) && supplierFilterActive && matched;

  String? _visibleSupplierStatus(String? status) =>
      (status == 'Disabled' ||
          status == 'On Hold' ||
          (status?.startsWith('On Hold ') ?? false))
      ? status
      : null;

  Widget _supplier(BuildContext context) {
    final purchase = _purchasePresentation(_row);
    final columns = supplierColumns;
    final shownLabels = {for (final field in columns) fieldLabel(field)};
    final details = [
      for (final detail in purchase.details)
        if (!shownLabels.contains(detail.label)) detail,
    ];
    final onTap = details.isEmpty ? null : onToggleEvidence;
    final cells = [
      for (final field in columns)
        (
          field: field,
          label: fieldLabel(field),
          value: _supplierColumnValue(_row, field, shows),
        ),
    ];
    final run = columnRun;
    final heading = cells.isNotEmpty && (run == null || run._startsWith(entry))
        ? columnLabel?.call('supplier_name', 'Supplier Name') ?? 'Supplier Name'
        : null;
    // A supplier never bought from stays marked even with the column hidden.
    final lastBuyLabel = fieldLabel(_Field.supplierLastBuyColumn);
    final undated =
        !columns.contains(_Field.supplierLastBuyColumn) &&
        strictReportDate(_row.lastPurchaseDate) == null;
    final notes = [
      if (undated) '$lastBuyLabel -',
      if (purchase.filterMatch && !purchase.matched) 'Matches Suppliers filter',
      ?_depthLabel,
    ];
    final spoken = [
      _spokenSupplier(entry.supplierLabel, entry.hasNamedSupplier),
      if (undated) '$lastBuyLabel unavailable',
      for (final cell in cells)
        cell.value == _emptyCell
            ? '${cell.label} unavailable'
            : cell.field == _Field.supplierLastBuyColumn
            ? '${cell.label} ${DateFormat('d MMMM yyyy').format(strictReportDate(_row.lastPurchaseDate)!)}'
            : '${cell.label} ${cell.value}',
      if (purchase.filterMatch) 'Matches Suppliers filter',
      if (purchase.status case final status?)
        '${fieldLabel(_Field.supplierStatus)} $status',
      ?_depthLabel,
    ].join(', ');

    return LayoutBuilder(
      builder: (context, constraints) {
        final caption = _captionStyle(context);
        final value = Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontFeatures: _tabularFigures);
        // The tile pads its content by 10 on each side.
        final available = constraints.maxWidth - 20 - _disclosureWidth;
        final widths = cells.isEmpty
            ? const <double>[]
            : run?._supplierWidths(
                    context,
                    available,
                    columns,
                    caption,
                    value,
                  ) ??
                  _supplierColumnWidths(
                    context,
                    available,
                    [_row],
                    columns,
                    shows,
                    fieldLabel,
                    caption,
                    value,
                  );
        final (_, draftColour) = StatusPill.colourForStatus(
          'On Hold',
          brightness: Theme.of(context).brightness,
        );
        Widget cell(int i, Widget child) => Padding(
          padding: const EdgeInsetsDirectional.only(start: _columnGap),
          child: SizedBox(width: widths![i], child: child),
        );
        TextStyle? cellStyle(_Field field, String text) =>
            field == _Field.supplierDraftPoBadge && text != _emptyCell
            ? value?.copyWith(color: draftColour, fontWeight: FontWeight.w600)
            : text == _emptyCell
            ? value?.copyWith(color: context.scheme.textSubtle)
            : value;
        final name = Wrap(
          spacing: 6,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              entry.supplierLabel,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.scheme.text,
                fontWeight: purchase.matched
                    ? FontWeight.w800
                    : FontWeight.w600,
              ),
            ),
            if (purchase.status case final status?)
              SupplierStatusPill(
                status: status,
                compact: true,
                wrapLabel: true,
              ),
          ],
        );
        final disclosure = onTap == null
            ? const SizedBox(width: _disclosureWidth)
            : _disclosure(context, evidenceExpanded);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TileSurface(
              label: spoken,
              onTap: onTap,
              expanded: onTap == null ? null : evidenceExpanded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (heading != null && widths != null)
                    ExcludeSemantics(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(child: Text(heading, style: caption)),
                            for (var i = 0; i < cells.length; i++)
                              cell(
                                i,
                                Text(
                                  cells[i].label,
                                  style: caption,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            const SizedBox(width: _disclosureWidth),
                          ],
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: name),
                      if (widths != null)
                        for (var i = 0; i < cells.length; i++)
                          cell(
                            i,
                            Text(
                              cells[i].value,
                              style: cellStyle(cells[i].field, cells[i].value),
                              textAlign: TextAlign.end,
                            ),
                          ),
                      disclosure,
                    ],
                  ),
                  if (widths == null && cells.isNotEmpty)
                    _RowWrap(
                      children: [
                        for (final item in cells)
                          _MetricText(
                            (label: item.label, value: item.value),
                            labelStyle: _mutedStyle(context),
                            valueStyle: cellStyle(item.field, item.value),
                          ),
                      ],
                    ),
                  if (notes.isNotEmpty)
                    _RowWrap(
                      children: [
                        for (final note in notes)
                          Text(note, style: _mutedStyle(context)),
                      ],
                    ),
                ],
              ),
            ),
            if (onTap != null && evidenceExpanded)
              _SupplierDetailPanel(details: details),
          ],
        );
      },
    );
  }

  Widget _group(BuildContext context, SuppliersByItemSupplierGroup group) {
    final matched = _highlightMatch(group.matchedSupplier);
    final filterMatch = supplierFilterActive && group.matchedSupplier;
    final status = _visibleSupplierStatus(group.supplierStatus);
    final counts = [
      if ((shows(_Field.supplierGroupItemCount) ||
              group.retainedDirectItemCount != null) &&
          group.directItemCount > 0)
        _groupCount(
          fieldLabel(_Field.supplierGroupItemCount),
          group.directItemCount,
          group.retainedDirectItemCount,
        ),
      if ((shows(_Field.supplierGroupComponentCount) ||
              group.retainedComponentMatchCount != null) &&
          group.componentMatchCount > 0)
        _groupCount(
          fieldLabel(_Field.supplierGroupComponentCount),
          group.componentMatchCount,
          group.retainedComponentMatchCount,
        ),
    ];
    return _TileSurface(
      label: [
        group.isNoDirect || group.isOther
            ? group.label
            : _spokenSupplier(group.label, group.hasNamedSupplier),
        ...counts,
        if (filterMatch) 'Matches Suppliers filter',
        if (status != null) '${fieldLabel(_Field.supplierStatus)} $status',
      ].join(', '),
      heading: true,
      onTap: onToggleBranch,
      expanded: entry.children.isEmpty ? null : expanded,
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(group.label, style: _pairTitle(context, matched)),
                for (final count in counts)
                  Text(count, style: _mutedStyle(context)),
                if (filterMatch && !matched)
                  Text('Matches Suppliers filter', style: _mutedStyle(context)),
                if (status != null)
                  SupplierStatusPill(
                    status: status,
                    compact: true,
                    wrapLabel: true,
                  ),
              ],
            ),
          ),
          if (onToggleBranch != null) _disclosure(context, expanded),
        ],
      ),
    );
  }

  Widget _pairOccurrence(BuildContext context) {
    final purchase = _purchasePresentation(entry.pairNode!.row);
    final item = _itemPresentation(pairOccurrence: true);
    final owner = entry.ownerNode!.row.itemTitle;
    final path = entry.componentPath;
    final identity = entry.isComponentMatch
        ? 'Component ${_row.itemTitle} for $owner'
        : _row.itemTitle;
    final spokenIdentity = entry.isComponentMatch
        ? 'Component ${_row.itemTitle} for item $owner'
        : 'Item $identity';
    final hasBranch = entry.children.isNotEmpty;
    final forcedBranch = hasBranch && onToggleBranch == null;
    final evidenceAction = purchase.details.isNotEmpty
        ? onToggleEvidence
        : null;
    final rowAction = hasBranch ? null : evidenceAction;
    final detailsLabel = evidenceExpanded
        ? 'Hide supplier details'
        : 'Show supplier details';
    final purchaseBadges = _purchaseBadges(purchase);
    final itemSection = !entry.isComponentMatch && item.details.isNotEmpty;
    final supplierBadgeSection = itemSection && purchase.badges.isNotEmpty;
    final badges = [
      if (!supplierBadgeSection) ...purchaseBadges,
      ...item.badges,
    ];
    final qualifiers = [?path, ...item.qualifiers];
    final actions = [
      if (onToggleBranch case final toggle?)
        _PairAction(
          label: expanded ? 'Hide BOM components' : 'Show BOM components',
          expanded: expanded,
          onTap: toggle,
        ),
      if (hasBranch && evidenceAction != null)
        _PairAction(
          label: detailsLabel,
          expanded: evidenceExpanded,
          onTap: evidenceAction,
        ),
    ];
    final muted = _mutedStyle(context);
    final valueStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontFeatures: _tabularFigures);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TileSurface(
          label: [
            spokenIdentity,
            if (item.name case final name?)
              '${fieldLabel(_Field.itemName)} $name',
            ...qualifiers,
            _spokenSupplier(entry.supplierLabel, entry.hasNamedSupplier),
            ?purchase.spokenLastBuy,
            if (purchase.filterMatch) 'Matches Suppliers filter',
            if (purchase.status case final status?)
              '${fieldLabel(_Field.supplierStatus)} $status',
            for (final badge in purchase.badges) badge.label,
            if (itemSection) 'Item',
            for (final metric in item.metrics) _metricSemantics(metric),
            for (final badge in item.badges) badge.label,
            for (final detail in item.details)
              '${detail.label} ${detail.value}',
            ...item.warnings,
            if (forcedBranch) 'BOM components',
            if (rowAction != null) detailsLabel,
          ].join(', '),
          onTap: rowAction,
          expanded: forcedBranch
              ? expanded
              : rowAction == null
              ? null
              : evidenceExpanded,
          controls: actions.isEmpty ? null : Wrap(children: actions),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LastBuyLine(
                identity: identity,
                matched: purchase.matched,
                lastBuy: purchase.lastBuy,
                disclosure: rowAction == null ? null : evidenceExpanded,
                columnRun: columnRun,
              ),
              if (item.name case final name?)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(name, style: muted),
                ),
              if (qualifiers.isNotEmpty)
                _RowWrap(
                  children: [
                    for (final label in qualifiers) Text(label, style: muted),
                  ],
                ),
              if (purchase.filterMatch && !purchase.matched)
                Text('Matches Suppliers filter', style: muted),
              if (supplierBadgeSection) ...[
                _SectionTitle(label: entry.supplierLabel),
                _RowWrap(children: purchaseBadges),
              ],
              if (itemSection) const _SectionTitle(label: 'Item'),
              if (item.metrics.isNotEmpty)
                _RowWrap(
                  children: [
                    for (final metric in item.metrics)
                      _MetricText(
                        metric,
                        labelStyle: muted,
                        valueStyle: valueStyle,
                      ),
                  ],
                ),
              if (badges.isNotEmpty) _RowWrap(children: badges),
              if (item.details.isNotEmpty || item.warnings.isNotEmpty)
                _RowWrap(
                  children: [
                    for (final detail in item.details)
                      _MetricText(
                        detail,
                        labelStyle: muted,
                        valueStyle: valueStyle,
                      ),
                    for (final warning in item.warnings)
                      Text(warning, style: muted),
                  ],
                ),
            ],
          ),
        ),
        if (evidenceAction != null && evidenceExpanded)
          _SupplierDetailPanel(
            title: entry.supplierLabel,
            details: purchase.details,
          ),
      ],
    );
  }

  Widget _bom(BuildContext context) {
    final draft = _row.bomStatus == 'Draft';
    final showDraft = draft;
    final labels = [
      if (_row.bomIsDefault && !draft) 'Default BOM',
      if (shows(_Field.bomComponentCount))
        if (_row.componentCount case final count?)
          countLabel(count, 'component'),
      ?_depthLabel,
    ];
    return _TileSurface(
      label: [entry.bomLabel, ...labels, if (showDraft) 'Draft BOM'].join(', '),
      heading: true,
      onTap: onToggleBranch,
      expanded: entry.children.isEmpty ? null : expanded,
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  entry.bomLabel,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final label in labels)
                  Text(label, style: _mutedStyle(context)),
                if (showDraft) const SuppliersByItemBadge('Draft BOM', 'Draft'),
              ],
            ),
          ),
          if (onToggleBranch != null) _disclosure(context, expanded),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(
          SuppliersByItemColumnLabels.noSupplierRecorded,
          style: _mutedStyle(context),
        ),
        if (_depthLabel case final label?)
          Text(label, style: _mutedStyle(context)),
      ],
    ),
  );

  String _spokenSupplier(String identity, bool hasName) {
    final column = hasName ? 'supplier_name' : 'tree_label';
    final fallback = hasName ? 'Supplier Name' : 'Item / Supplier';
    final label = columnLabel?.call(column, fallback) ?? fallback;
    return '$label $identity';
  }

  String? _stockUom(_Field field, {bool forceUnit = false}) => _displayUnit(
    _row,
    !_sharesGroupUnit && (forceUnit || shows(field)),
    fieldLabel(field),
  );

  List<SuppliersByItemBadge> _poBadges(
    SuppliersByItemRow row, {
    required bool supplier,
    required bool detailsVisible,
  }) {
    final unit = _displayUnit(
      row,
      !(!supplier && _sharesGroupUnit) &&
          shows(supplier ? _Field.supplierStockUom : _Field.itemStockUom),
      fieldLabel(_Field.itemStockUom),
    );
    return [
      if (shows(
            supplier ? _Field.supplierOpenPoBadge : _Field.itemOpenPoBadge,
          ) &&
          !(detailsVisible &&
              shows(
                supplier ? _Field.supplierOpenOrders : _Field.itemOpenOrders,
              )) &&
          (row.openOrderQty ?? 0) > 0)
        if (_amount(row.openOrderQty, unit) case final value?)
          SuppliersByItemBadge.quantity(
            fieldLabel(_Field.itemOpenOrders),
            value,
            'Submitted',
          ),
      if (includeDrafts &&
          shows(
            supplier ? _Field.supplierDraftPoBadge : _Field.itemDraftPoBadge,
          ) &&
          !(detailsVisible &&
              shows(
                supplier ? _Field.supplierDraftOrders : _Field.itemDraftOrders,
              )) &&
          (row.draftOrderQty ?? 0) > 0)
        if (_amount(row.draftOrderQty, unit) case final value?)
          SuppliersByItemBadge.quantity(
            fieldLabel(_Field.itemDraftOrders),
            value,
            'On Hold',
          ),
    ];
  }
}

List<_Detail> _itemMetrics(
  SuppliersByItemLayoutRow entry,
  bool Function(SuppliersByItemField) shows,
  SuppliersByItemFieldCaption fieldLabel, [
  String? groupUnit,
]) {
  final row = entry.node.row;
  final component = _isComponent(row);
  final template = row.kind == SuppliersByItemRowKind.template;
  final sharedUnit =
      !template && groupUnit != null && row.stockUom == groupUnit;
  return [
    if (template
        ? row.stockUom != null
        : shows(component ? _Field.componentBalance : _Field.itemBalance))
      (
        label: fieldLabel(_Field.itemBalance),
        value:
            _amount(
              row.balanceQty,
              _displayUnit(
                row,
                template ||
                    (!sharedUnit &&
                        shows(
                          component
                              ? _Field.componentStockUom
                              : _Field.itemStockUom,
                        )),
                fieldLabel(_Field.itemStockUom),
              ),
            ) ??
            '-',
      ),
    if ((template && entry.directSupplierCount != null) ||
        shows(
          component ? _Field.componentSupplierCount : _Field.itemSupplierCount,
        ))
      (
        label: fieldLabel(_Field.itemSupplierCount),
        value: entry.directSupplierCount?.toString() ?? '-',
      ),
  ];
}

String? _displayUnit(SuppliersByItemRow row, bool showsUnit, String label) =>
    row.stockUom == null
    ? '($label unavailable)'
    : showsUnit
    ? row.stockUom
    : null;

bool suppliersByItemHasDetails(
  SuppliersByItemRow row,
  bool Function(SuppliersByItemField) shows,
) => _supplierDetails(
  row,
  shows,
  strictReportDate(row.lastPurchaseDate),
  _defaultCaption,
  true,
).isNotEmpty;

String _supplierColumnValue(
  SuppliersByItemRow row,
  SuppliersByItemField field,
  bool Function(SuppliersByItemField) shows,
) {
  String quantity(num? value) => value == null || !value.isFinite || value == 0
      ? _emptyCell
      : _quantityLabel(value);
  switch (field) {
    case _Field.supplierLastBuyColumn:
      final date = strictReportDate(row.lastPurchaseDate);
      return date == null ? _emptyCell : DateFormat('d MMM yy').format(date);
    case _Field.supplierOpenPoBadge:
      return quantity(row.openOrderQty);
    case _Field.supplierDraftPoBadge:
      return quantity(row.draftOrderQty);
    case _Field.supplierRateColumn:
      final rate = row.lastRate;
      if (rate == null || !rate.isFinite) return _emptyCell;
      return [
        if (shows(_Field.supplierRateCurrency)) ?row.currency,
        FormattingHelper.formatAmount(rate.toDouble()),
      ].join(_nonBreakingSpace);
    case _Field.supplierLeadTimeColumn:
      return row.leadTimeDays?.toStringAsFixed(1) ?? _emptyCell;
    case _Field.supplierQtyReceivedColumn:
      return quantity(row.totalQtyReceived);
    default:
      return _emptyCell;
  }
}

/// Shared supplier column widths, or null when the columns leave the supplier
/// name too little room and the row should list its values instead.
List<double>? _supplierColumnWidths(
  BuildContext context,
  double availableWidth,
  Iterable<SuppliersByItemRow> rows,
  List<SuppliersByItemField> columns,
  bool Function(SuppliersByItemField) shows,
  SuppliersByItemFieldCaption label,
  TextStyle? captionStyle,
  TextStyle? valueStyle,
) {
  final values = List.filled(columns.length, 0.0);
  final measured = <String, double>{};
  for (final row in rows) {
    for (var i = 0; i < columns.length; i++) {
      final text = _supplierColumnValue(row, columns[i], shows);
      final width = measured.putIfAbsent(
        text,
        () => _width(context, text, valueStyle),
      );
      if (width > values[i]) values[i] = width;
    }
  }
  double widest(double a, double b) => a > b ? a : b;
  // Prefer headings on one line, then on two, then one word per line.
  final words = [
    for (final field in columns)
      label(
        field,
      ).split(' ').map((word) => _width(context, word, captionStyle)).toList(),
  ];
  List<double> layout(double Function(List<double> words) heading) => [
    for (var i = 0; i < columns.length; i++)
      widest(values[i], widest(32, heading(words[i]))),
  ];
  final space = _width(context, ' ', captionStyle);
  double line(List<double> words) =>
      words.fold(0.0, (sum, word) => sum + word) + space * (words.length - 1);
  double twoLines(List<double> words) {
    var best = double.infinity;
    for (var split = 1; split < words.length; split++) {
      final width = widest(
        line(words.sublist(0, split)),
        line(words.sublist(split)),
      );
      if (width < best) best = width;
    }
    return best.isFinite ? best : line(words);
  }

  for (final widths in [
    layout(line),
    layout(twoLines),
    layout((words) => words.fold(0.0, widest)),
  ]) {
    final total = widths.fold(0.0, (sum, width) => sum + width + _columnGap);
    if (availableWidth - total >= _minSupplierNameWidth) return widths;
  }
  return null;
}

String _lastBuyLabel(DateTime? date, String label) =>
    '$label ${date == null ? '-' : DateFormat('d MMM yy').format(date)}';

String? _supplierAmount(num? quantity, String? unit) {
  if (quantity == null || !quantity.isFinite) return null;
  return [
    _quantityLabel(quantity),
    ?unit?.replaceAll(' ', _nonBreakingSpace),
  ].join(_nonBreakingSpace);
}

List<_Detail> _supplierDetails(
  SuppliersByItemRow row,
  bool Function(SuppliersByItemField) shows,
  DateTime? purchaseDate,
  SuppliersByItemFieldCaption fieldLabel,
  bool includeDrafts,
) {
  final unit = _displayUnit(
    row,
    shows(_Field.supplierStockUom),
    fieldLabel(_Field.supplierStockUom),
  );
  final rate = row.lastRate;
  final days = row.leadTimeDays?.toStringAsFixed(1);
  return [
    if (shows(_Field.supplierOpenOrders))
      if (_supplierAmount(row.openOrderQty, unit) case final value?)
        (label: fieldLabel(_Field.supplierOpenOrders), value: value),
    if (includeDrafts && shows(_Field.supplierDraftOrders))
      if (_supplierAmount(row.draftOrderQty, unit) case final value?)
        (label: fieldLabel(_Field.supplierDraftOrders), value: value),
    if (shows(_Field.supplierPartNumber))
      if (row.supplierPartNumber case final value?)
        (label: fieldLabel(_Field.supplierPartNumber), value: value),
    if (shows(_Field.supplierSources))
      if (row.sources case final value?)
        (label: fieldLabel(_Field.supplierSources), value: value),
    if (shows(_Field.supplierLastPurchase) && purchaseDate != null)
      (
        label: fieldLabel(_Field.supplierLastPurchase),
        value: DateFormat('d MMM yyyy').format(purchaseDate),
      ),
    if (shows(_Field.supplierLastPurchaseReceipt))
      if (row.lastPurchaseReceipt case final value?)
        (label: fieldLabel(_Field.supplierLastPurchaseReceipt), value: value),
    if (shows(_Field.supplierQtyReceived))
      if (_supplierAmount(row.totalQtyReceived, unit) case final value?)
        (label: fieldLabel(_Field.supplierQtyReceived), value: value),
    if (shows(_Field.supplierLastPo))
      if (row.lastPoDate case final value?)
        (label: fieldLabel(_Field.supplierLastPo), value: value),
    if (rate != null) ...[
      if (shows(_Field.supplierRate))
        (
          label: fieldLabel(_Field.supplierRate),
          value: [
            if (shows(_Field.supplierRateCurrency)) ?row.currency,
            FormattingHelper.formatAmount(rate.toDouble()),
            if (shows(_Field.supplierRateUom))
              if (row.rateUom case final unit?) '/ $unit',
          ].join(' '),
        ),
      if (shows(_Field.supplierRateSource))
        if (row.rateSource case final value?)
          (label: fieldLabel(_Field.supplierRateSource), value: value),
      if (shows(_Field.supplierRateDate))
        if (row.rateDate case final value?)
          (label: fieldLabel(_Field.supplierRateDate), value: value),
      if (shows(_Field.supplierRateDocument))
        if (row.rateDocument case final value?)
          (label: fieldLabel(_Field.supplierRateDocument), value: value),
    ],
    if (shows(_Field.supplierLeadTime) && days != null)
      (
        label: fieldLabel(_Field.supplierLeadTime),
        value: '$days ${days == '1.0' ? 'day' : 'days'}',
      ),
    if (shows(_Field.supplierLeadTimeReceipts))
      if (row.leadTimeReceipts case final count?)
        (label: fieldLabel(_Field.supplierLeadTimeReceipts), value: '$count'),
    if (shows(_Field.supplierPoCount))
      if (row.poCount case final count?)
        (label: fieldLabel(_Field.supplierPoCount), value: '$count'),
    if (shows(_Field.supplierReceiptCount))
      if (row.receiptCount case final count?)
        (label: fieldLabel(_Field.supplierReceiptCount), value: '$count'),
  ];
}

class _ItemContent extends StatelessWidget {
  const _ItemContent({
    required this.identity,
    required this.name,
    required this.metrics,
    required this.qualifiers,
    required this.badges,
    required this.details,
    required this.warnings,
    required this.expanded,
    required this.hasDisclosure,
    required this.columnRun,
    required this.showColumnHeadings,
  });

  final String identity;
  final String? name;
  final List<_Detail> metrics;
  final List<String> qualifiers;
  final List<SuppliersByItemBadge> badges;
  final List<_Detail> details;
  final List<String> warnings;
  final bool expanded;
  final bool hasDisclosure;
  final SuppliersByItemColumnRun? columnRun;
  final bool showColumnHeadings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codeStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final muted = _mutedStyle(context);
    final values = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: _tabularFigures,
    );
    final hasSecondLine = name != null || qualifiers.isNotEmpty;
    final hasDetails = details.isNotEmpty || warnings.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final disclosureWidth = hasDisclosure || metrics.isNotEmpty
            ? _disclosureWidth
            : 0.0;
        final sharedWidths = columnRun?._widths(
          context,
          constraints.maxWidth,
          muted,
          values,
          codeStyle,
          metrics,
        );
        final widths =
            sharedWidths ??
            [
              if (columnRun == null)
                for (final metric in metrics)
                  _width(context, '${metric.label} ', muted) +
                      _width(context, metric.value, values),
            ];
        final metricWidth = widths.fold(
          0.0,
          (total, width) => total + width + _columnGap,
        );
        final fitsTogether =
            metrics.isEmpty ||
            sharedWidths != null ||
            (columnRun == null &&
                constraints.maxWidth >=
                    metricWidth +
                        disclosureWidth +
                        _width(context, '00000000', codeStyle));
        final useCaptions = sharedWidths != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (useCaptions && showColumnHeadings && metrics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    const Spacer(),
                    for (var i = 0; i < metrics.length; i++)
                      _metricColumn(
                        widths[i],
                        Text(
                          metrics[i].label,
                          style: _captionStyle(context),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    SizedBox(width: disclosureWidth),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(child: Text(identity, style: codeStyle)),
                if (fitsTogether)
                  for (var i = 0; i < metrics.length; i++)
                    _metricColumn(
                      widths[i],
                      useCaptions
                          ? Text(
                              metrics[i].value,
                              style: values,
                              textAlign: TextAlign.end,
                            )
                          : _MetricText(
                              metrics[i],
                              labelStyle: muted,
                              valueStyle: values,
                              alignment: TextAlign.end,
                            ),
                    ),
                if (hasDisclosure)
                  _disclosure(context, expanded)
                else if (fitsTogether && metrics.isNotEmpty)
                  SizedBox(width: disclosureWidth),
              ],
            ),
            if (!fitsTogether && name != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(name!, style: muted),
              ),
            if (hasSecondLine || !fitsTogether)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (fitsTogether && name != null) Text(name!, style: muted),
                    for (final qualifier in qualifiers)
                      Text(qualifier, style: muted),
                    if (!fitsTogether)
                      for (final metric in metrics)
                        _MetricText(
                          metric,
                          labelStyle: muted,
                          valueStyle: values,
                        ),
                  ],
                ),
              ),
            if (badges.isNotEmpty) _RowWrap(children: badges),
            if (hasDetails)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (final detail in details)
                      _MetricText(
                        detail,
                        labelStyle: muted,
                        valueStyle: values,
                      ),
                    for (final warning in warnings) Text(warning, style: muted),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _metricColumn(double width, Widget child) => Padding(
    padding: const EdgeInsetsDirectional.only(start: _columnGap),
    child: SizedBox(width: width, child: child),
  );
}

class _MetricText extends StatelessWidget {
  const _MetricText(
    this.detail, {
    required this.labelStyle,
    required this.valueStyle,
    this.alignment,
  });

  final _Detail detail;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;
  final TextAlign? alignment;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '${detail.label} ', style: labelStyle),
        TextSpan(text: detail.value, style: valueStyle),
      ],
    ),
    textAlign: alignment,
  );
}

TextStyle? _pairTitle(BuildContext context, bool matched) =>
    Theme.of(context).textTheme.titleSmall?.copyWith(
      color: context.scheme.text,
      fontWeight: matched ? FontWeight.w800 : FontWeight.w600,
    );

List<Widget> _purchaseBadges(_PurchasePresentation purchase) => [
  if (purchase.status case final status?)
    SupplierStatusPill(status: status, compact: true, wrapLabel: true),
  ...purchase.badges,
];

class _RowWrap extends StatelessWidget {
  const _RowWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    ),
  );
}

class _LastBuyLine extends StatelessWidget {
  const _LastBuyLine({
    required this.identity,
    required this.matched,
    required this.lastBuy,
    required this.disclosure,
    required this.columnRun,
  });

  final String identity;
  final bool matched;
  final String? lastBuy;
  final bool? disclosure;
  final SuppliersByItemColumnRun? columnRun;

  @override
  Widget build(BuildContext context) {
    final title = _pairTitle(context, matched);
    final dateStyle = _mutedStyle(
      context,
    )?.copyWith(fontFeatures: _tabularFigures);
    final label = lastBuy;
    return LayoutBuilder(
      builder: (context, constraints) {
        final date = label == null
            ? null
            : Text(label, style: dateStyle, textAlign: TextAlign.end);
        final dateWidth = label == null
            ? 0.0
            : columnRun?._lastBuyWidth(context, dateStyle) ??
                  _width(context, label, dateStyle);
        final fitsTogether =
            date == null ||
            constraints.maxWidth >=
                dateWidth +
                    _columnGap +
                    _disclosureWidth +
                    _width(
                      context,
                      'MMMMMMMM',
                      title?.copyWith(fontWeight: FontWeight.w800),
                    );
        final identityLine = Row(
          children: [
            Expanded(child: Text(identity, style: title)),
            if (date != null && fitsTogether)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: _columnGap),
                child: date,
              ),
            if (disclosure case final expanded?)
              _disclosure(context, expanded)
            else if (date != null && fitsTogether)
              const SizedBox(width: _disclosureWidth),
          ],
        );
        if (fitsTogether) return identityLine;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            identityLine,
            Padding(
              padding: const EdgeInsetsDirectional.only(end: _disclosureWidth),
              child: date,
            ),
          ],
        );
      },
    );
  }
}

class _PairAction extends StatelessWidget {
  const _PairAction({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    button: true,
    expanded: expanded,
    onTap: onTap,
    excludeSemantics: true,
    child: TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: context.scheme.text,
        minimumSize: const Size(48, 48),
        visualDensity: VisualDensity.standard,
      ),
      icon: _disclosure(context, expanded),
      label: Text(label),
    ),
  );
}

class _TileSurface extends StatelessWidget {
  const _TileSurface({
    required this.label,
    required this.child,
    this.heading = false,
    this.onTap,
    this.expanded,
    this.controls,
  });

  final String label;
  final Widget child;
  final bool heading;
  final VoidCallback? onTap;
  final bool? expanded;
  final Widget? controls;

  @override
  Widget build(BuildContext context) {
    final interactive = onTap != null;
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: interactive ? 48 : 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Center(child: child),
      ),
    );
    final summary = Semantics(
      container: controls != null,
      label: label,
      excludeSemantics: true,
      header: heading,
      button: interactive ? true : null,
      expanded: expanded,
      onTap: onTap,
      child: interactive
          ? InkWell(onTap: onTap, excludeFromSemantics: true, child: content)
          : content,
    );
    final actions = controls;
    return Material(
      type: MaterialType.transparency,
      child: actions == null
          ? summary
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [summary, actions],
            ),
    );
  }
}

/// A row badge: a status pill, or a quiet quantity note with a status dot.
class SuppliersByItemBadge extends StatelessWidget {
  const SuppliersByItemBadge(this.label, this.colorStatus, {super.key})
    : caption = null,
      value = null;

  /// A quiet quantity note: a status dot, a muted caption and the value.
  const SuppliersByItemBadge.quantity(
    String this.caption,
    String this.value,
    this.colorStatus, {
    super.key,
  }) : label = '$caption $value';

  final String label;
  final String colorStatus;
  final String? caption;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final caption = this.caption;
    if (caption == null) {
      return StatusPill(
        status: label,
        colorStatus: colorStatus,
        compact: true,
        wrapLabel: true,
      );
    }
    final (_, valueColour) = StatusPill.colourForStatus(
      colorStatus,
      brightness: Theme.of(context).brightness,
    );
    final muted = _mutedStyle(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: StatusPill.dotColorForStatus(colorStatus),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$caption ', style: muted),
                TextSpan(
                  text: value,
                  style: muted?.copyWith(
                    color: valueColour,
                    fontWeight: FontWeight.w600,
                    fontFeatures: _tabularFigures,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One figure in a template header: a caption above its value.
class SuppliersByItemStat extends StatelessWidget {
  const SuppliersByItemStat({
    super.key,
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: _captionStyle(context)),
      const SizedBox(height: 2),
      Text(value, style: valueStyle),
    ],
  );
}

class _TemplateHeader extends StatelessWidget {
  const _TemplateHeader({
    required this.identity,
    required this.name,
    required this.stats,
    required this.notes,
    required this.badges,
    required this.expanded,
  });

  final String identity;
  final String? name;
  final List<_Detail> stats;
  final List<String> notes;
  final List<SuppliersByItemBadge> badges;
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _mutedStyle(context);
    final title = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final value = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: _tabularFigures,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  Text(identity, style: title),
                  if (name case final name?)
                    Text(
                      '· $name',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: context.scheme.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            if (expanded case final open?) _disclosure(context, open),
          ],
        ),
        if (stats.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.only(top: 7),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.scheme.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final stat in stats)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: SuppliersByItemStat(
                        label: stat.label,
                        value: stat.value,
                        valueStyle: value,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (notes.isNotEmpty)
          _RowWrap(
            children: [for (final note in notes) Text(note, style: muted)],
          ),
        if (badges.isNotEmpty) _RowWrap(children: badges),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Semantics(
      container: true,
      header: true,
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    ),
  );
}

class _SupplierDetailPanel extends StatelessWidget {
  const _SupplierDetailPanel({this.title, required this.details});

  final String? title;
  final List<_Detail> details;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.scheme.subtle,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final trailingWidth = (constraints.maxWidth - gap) / 2;
        final valueStyle = Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontFeatures: _tabularFigures);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title case final label?) _SectionTitle(label: label),
            for (final detail in details)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _detailLayout(
                  context,
                  detail,
                  valueStyle,
                  trailingWidth,
                  gap,
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _detailLayout(
    BuildContext context,
    _Detail detail,
    TextStyle? valueStyle,
    double trailingWidth,
    double gap,
  ) {
    final label = Text(detail.label, style: _mutedStyle(context));
    final value = Text(
      detail.value,
      textAlign: TextAlign.end,
      style: valueStyle,
    );
    if (detail.value.contains(_nonBreakingSpace) &&
        _width(context, detail.value, valueStyle) > trailingWidth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [label, value],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: label),
        SizedBox(width: gap),
        Expanded(child: value),
      ],
    );
  }
}

Widget _disclosure(BuildContext context, bool expanded) => SizedBox(
  width: _disclosureWidth,
  child: Icon(
    expanded ? Icons.expand_less : Icons.expand_more,
    size: 20,
    color: context.scheme.textSubtle,
  ),
);

TextStyle? _mutedStyle(BuildContext context) => Theme.of(
  context,
).textTheme.bodySmall?.copyWith(color: context.scheme.textMuted);

/// Column and stat captions: small, medium weight, subtle.
TextStyle? _captionStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .labelSmall
    ?.copyWith(color: context.scheme.textSubtle, fontWeight: FontWeight.w500);

String? _amount(num? quantity, String? unit) =>
    quantity == null || !quantity.isFinite
    ? null
    : [_quantityLabel(quantity), ?unit].join(' ');

String _groupCount(String label, int total, int? retained) =>
    retained == null ? '$label $total' : '$label $retained of $total';

double _width(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}

String _metricSemantics(_Detail metric) => switch (metric) {
  (label: _, value: '-') => '${metric.label} unavailable',
  _ => '${metric.label} ${metric.value}',
};
