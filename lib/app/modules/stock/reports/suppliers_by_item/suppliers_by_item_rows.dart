import 'dart:math' show max;

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
typedef _Detail = ({String label, String value});
typedef _ItemPresentation = ({
  String? name,
  List<_Detail> metrics,
  List<String> qualifiers,
  List<_Badge> badges,
  List<_Detail> details,
  List<String> warnings,
});
typedef _PurchasePresentation = ({
  String? lastBuy,
  String? spokenLastBuy,
  String? status,
  bool matched,
  List<_Badge> badges,
  List<_Detail> details,
});

const _maxIndentDepth = 3;
const _disclosureWidth = 24.0;
const _columnGap = 10.0;
const _tabularFigures = [FontFeature.tabularFigures()];
const _nonBreakingSpace = '\u00a0';

String suppliersByItemQuantity(num quantity, [String? unit]) =>
    [_quantityLabel(quantity), ?unit].join(' ');

// Keep a significant digit when two-decimal rounding would erase a quantity.
String _quantityLabel(num quantity) => quantity != 0 && quantity.abs() < 0.005
    ? quantity.toStringAsPrecision(1)
    : FormattingHelper.formatQtyGrouped(quantity.toDouble());

bool _isComponent(SuppliersByItemRow row) =>
    row.kind == SuppliersByItemRowKind.component || row.isComponent;

/// Groups consecutive item or component siblings. Descendants interleaved in
/// the flat list leave their parents' sibling runs intact.
Map<SuppliersByItemRowKey, SuppliersByItemColumnRun> suppliersByItemColumnRuns(
  Iterable<SuppliersByItemLayoutRow> rows,
  bool Function(SuppliersByItemField) shows,
) {
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
    final run = SuppliersByItemColumnRun._(siblings, shows);
    for (final row in siblings) {
      byRow[row.key] = run;
    }
  }
  return byRow;
}

class SuppliersByItemColumnRun {
  SuppliersByItemColumnRun._(this._rows, this._shows);

  final List<SuppliersByItemLayoutRow> _rows;
  final bool Function(SuppliersByItemField) _shows;
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
      final values = _itemMetrics(row, _shows);
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

  SuppliersByItemRow get _row => entry.node.row;

  String? get _depthLabel =>
      entry.depth > _maxIndentDepth && shows(_Field.treeDepthLabel)
      ? 'Depth ${entry.depth}'
      : null;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(
      start: 12.0 + entry.depth.clamp(0, _maxIndentDepth) * 16.0,
      end: 12,
    ),
    child: switch ((entry.group, entry.isPairOccurrence, _row.kind)) {
      (final group?, _, _) => _group(context, group),
      (_, true, _) => _pairOccurrence(context),
      (_, _, SuppliersByItemRowKind.supplier) => _supplier(context),
      (_, _, SuppliersByItemRowKind.bom) => _bom(context),
      (_, _, SuppliersByItemRowKind.placeholder) => _placeholder(context),
      _ => _item(),
    },
  );

  _ItemPresentation _itemPresentation({bool pairOccurrence = false}) {
    final isComponent = _isComponent(_row);
    final isTemplate = _row.kind == SuppliersByItemRowKind.template;
    final unit = _stockUom(
      isComponent ? _Field.componentStockUom : _Field.itemStockUom,
    );
    final name = shows(isComponent ? _Field.componentName : _Field.itemName)
        ? _row.distinctItemName
        : null;
    final hasComparableQuantities = !isTemplate || _row.stockUom != null;
    final componentPurchaseDate = pairOccurrence
        ? entry.pairNode?.row.lastPurchaseDate
        : _row.lastPurchaseDate;
    final metrics = _itemMetrics(entry, shows);
    final showsPlaceholder =
        expanded &&
        entry.children.any(
          (child) => child.node.row.kind == SuppliersByItemRowKind.placeholder,
        );
    final badges = [
      if (!isTemplate && !entry.hasDirectSupplier && !showsPlaceholder)
        _Badge(_Field.summaryNoDirectCount.label, 'Disabled'),
      if (!pairOccurrence && !isComponent && !isTemplate)
        ..._poBadges(_row, supplier: false, detailsVisible: true),
      if (!isComponent &&
          shows(_Field.itemBelowReorder) &&
          _row.isBelowReorderLevel)
        _Badge(_Field.itemBelowReorder.label, 'On Hold'),
    ];
    final qualifiers = [
      if (shows(_Field.itemTemplateContext) && entry.templateContext != null)
        '${_Field.itemTemplateContext.label} ${entry.templateContext}',
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
            (label: _Field.itemProjected.label, value: value),
        if (!isComponent) ...[
          if (shows(_Field.itemReorderLevel))
            if (_amount(_row.reorderLevel, unit) case final value?)
              (label: _Field.itemReorderLevel.label, value: value),
          if (shows(_Field.itemReorderQty))
            if (_amount(_row.reorderQty, unit) case final value?)
              (label: _Field.itemReorderQty.label, value: value),
          if (shows(_Field.itemOpenOrders))
            if (_amount(_row.openOrderQty, unit) case final value?)
              (label: _Field.itemOpenOrders.label, value: value),
          if (shows(_Field.itemDraftOrders))
            if (_amount(_row.draftOrderQty, unit) case final value?)
              (label: _Field.itemDraftOrders.label, value: value),
          if (shows(_Field.itemQtyReceived))
            if (_amount(_row.totalQtyReceived, unit) case final value?)
              (label: _Field.itemQtyReceived.label, value: value),
        ],
      ],
      if (isComponent) ...[
        if (shows(_Field.componentQtyPerUnit))
          if (_amount(_row.bomQtyPerUnit, unit) case final value?)
            (
              label: _Field.componentQtyPerUnit.label,
              value:
                  '$value per ${unit == null ? 'unit' : entry.parentOutputUom ?? parentOutputUom ?? 'unit'}',
            ),
        if (shows(_Field.componentLastPurchase))
          if (componentPurchaseDate case final value?)
            (label: _Field.supplierLastPurchase.label, value: value),
        if (shows(_Field.componentUsedInBoms))
          if (_row.usedInBomCount case final count?)
            (label: 'Used in', value: countLabel(count, 'BOM')),
      ],
    ];
    final warnings = [
      if (isComponent &&
          shows(_Field.componentManufacturing) &&
          _row.includeInManufacturing == false)
        'Not used in manufacturing',
      if (isComponent && shows(_Field.componentCycle) && _row.bomCycle)
        'BOM cycle detected',
      if (isComponent &&
          shows(_Field.componentDepthLimit) &&
          _row.bomDepthLimit)
        'BOM depth limit reached',
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
    return _TileSurface(
      label: [
        '$role ${_row.itemTitle}',
        if (item.name case final name?) '${_Field.itemName.label} $name',
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
    final lastBuy = shows(_Field.supplierLastBuyColumn)
        ? _lastBuyLabel(date)
        : null;
    final status = _visibleSupplierStatus(pair.supplierStatus);
    return (
      lastBuy: lastBuy,
      spokenLastBuy: lastBuy == null
          ? null
          : '${_Field.supplierLastBuyColumn.label} ${date == null ? 'unavailable' : DateFormat('d MMMM yyyy').format(date)}',
      status: status == entry.groupSupplierStatus ? null : status,
      matched: _highlightMatch(pair.matchedSupplier),
      badges: _poBadges(
        pair,
        supplier: true,
        detailsVisible: onToggleEvidence != null && evidenceExpanded,
      ),
      details: _supplierDetails(pair, shows, date),
    );
  }

  bool _highlightMatch(bool matched) =>
      shows(_Field.supplierMatchEmphasis) && supplierFilterActive && matched;

  String? _visibleSupplierStatus(String? status) =>
      shows(_Field.supplierStatus) &&
          (status == 'Disabled' ||
              status == 'On Hold' ||
              (status?.startsWith('On Hold ') ?? false))
      ? status
      : null;

  Widget _supplier(BuildContext context) {
    final purchase = _purchasePresentation(_row);
    final onTap = purchase.details.isEmpty ? null : onToggleEvidence;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TileSurface(
          label: [
            _spokenSupplier(entry.supplierLabel, entry.hasNamedSupplier),
            ?purchase.spokenLastBuy,
            if (purchase.matched) 'Matches Suppliers filter',
            if (purchase.status case final status?)
              '${_Field.supplierStatus.label} $status',
            for (final badge in purchase.badges) badge.label,
            ?_depthLabel,
          ].join(', '),
          onTap: onTap,
          expanded: onTap == null ? null : evidenceExpanded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LastBuyLine(
                identity: entry.supplierLabel,
                matched: purchase.matched,
                lastBuy: purchase.lastBuy,
                disclosure: onTap == null ? null : evidenceExpanded,
                columnRun: columnRun,
              ),
              if (purchase.status != null ||
                  purchase.badges.isNotEmpty ||
                  _depthLabel != null)
                _RowWrap(
                  children: [
                    ..._purchaseBadges(purchase),
                    if (_depthLabel case final label?)
                      Text(label, style: _mutedStyle(context)),
                  ],
                ),
            ],
          ),
        ),
        if (onTap != null && evidenceExpanded)
          _SupplierDetailPanel(details: purchase.details),
      ],
    );
  }

  Widget _group(BuildContext context, SuppliersByItemSupplierGroup group) {
    final matched = _highlightMatch(group.matchedSupplier);
    final status = _visibleSupplierStatus(group.supplierStatus);
    final counts = [
      if (shows(_Field.supplierGroupItemCount) && group.directItemCount > 0)
        _groupCount(
          _Field.supplierGroupItemCount.label,
          group.directItemCount,
          group.retainedDirectItemCount,
        ),
      if (shows(_Field.supplierGroupComponentCount) &&
          group.componentMatchCount > 0)
        _groupCount(
          _Field.supplierGroupComponentCount.label,
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
        if (matched) 'Matches Suppliers filter',
        if (status != null) '${_Field.supplierStatus.label} $status',
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
    final path = shows(_Field.componentMatchPath) ? entry.componentPath : null;
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
            if (item.name case final name?) '${_Field.itemName.label} $name',
            ...qualifiers,
            _spokenSupplier(entry.supplierLabel, entry.hasNamedSupplier),
            ?purchase.spokenLastBuy,
            if (purchase.matched) 'Matches Suppliers filter',
            if (purchase.status case final status?)
              '${_Field.supplierStatus.label} $status',
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
    final showDraft = shows(_Field.bomDraftBadge) && draft;
    final labels = [
      if (shows(_Field.bomDefaultMarker) && _row.bomIsDefault && !draft)
        'Default BOM',
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
                if (showDraft) const _Badge('Draft BOM', 'Draft'),
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
        Text(_Field.summaryNoDirectCount.label, style: _mutedStyle(context)),
        if (_depthLabel case final label?)
          Text(label, style: _mutedStyle(context)),
      ],
    ),
  );

  String? _stockUom(_Field field) => _displayUnit(_row, shows(field));

  List<_Badge> _poBadges(
    SuppliersByItemRow row, {
    required bool supplier,
    required bool detailsVisible,
  }) {
    final unit = _displayUnit(
      row,
      shows(supplier ? _Field.supplierStockUom : _Field.itemStockUom),
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
          _Badge('${_Field.itemOpenOrders.label} $value', 'Submitted'),
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
          _Badge('${_Field.itemDraftOrders.label} $value', 'On Hold'),
    ];
  }
}

String _spokenSupplier(String label, bool hasName) =>
    '${hasName ? 'Supplier Name' : 'Item / Supplier'} $label';

List<_Detail> _itemMetrics(
  SuppliersByItemLayoutRow entry,
  bool Function(SuppliersByItemField) shows,
) {
  final row = entry.node.row;
  final component = _isComponent(row);
  return [
    if ((row.kind != SuppliersByItemRowKind.template || row.stockUom != null) &&
        shows(component ? _Field.componentBalance : _Field.itemBalance))
      (
        label: _Field.itemBalance.label,
        value:
            _amount(
              row.balanceQty,
              _displayUnit(
                row,
                shows(
                  component ? _Field.componentStockUom : _Field.itemStockUom,
                ),
              ),
            ) ??
            '-',
      ),
    if (shows(
      component ? _Field.componentSupplierCount : _Field.itemSupplierCount,
    ))
      (
        label: _Field.itemSupplierCount.label,
        value: entry.directSupplierCount?.toString() ?? '-',
      ),
  ];
}

String? _displayUnit(SuppliersByItemRow row, bool showsUnit) => showsUnit
    ? row.stockUom ?? '(${_Field.itemStockUom.label} unavailable)'
    : null;

bool suppliersByItemHasDetails(
  SuppliersByItemRow row,
  bool Function(SuppliersByItemField) shows,
) => _supplierDetails(
  row,
  shows,
  strictReportDate(row.lastPurchaseDate),
).isNotEmpty;

String _lastBuyLabel(DateTime? date) =>
    '${_Field.supplierLastBuyColumn.label} ${date == null ? '-' : DateFormat('d MMM yy').format(date)}';

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
) {
  final unit = _displayUnit(row, shows(_Field.supplierStockUom));
  final rate = row.lastRate;
  final days = row.leadTimeDays?.toStringAsFixed(1);
  return [
    if (shows(_Field.supplierOpenOrders))
      if (_supplierAmount(row.openOrderQty, unit) case final value?)
        (label: _Field.supplierOpenOrders.label, value: value),
    if (shows(_Field.supplierDraftOrders))
      if (_supplierAmount(row.draftOrderQty, unit) case final value?)
        (label: _Field.supplierDraftOrders.label, value: value),
    if (shows(_Field.supplierPartNumber))
      if (row.supplierPartNumber case final value?)
        (label: _Field.supplierPartNumber.label, value: value),
    if (shows(_Field.supplierSources))
      if (row.sources case final value?)
        (label: _Field.supplierSources.label, value: value),
    if (shows(_Field.supplierLastPurchase) && purchaseDate != null)
      (
        label: _Field.supplierLastPurchase.label,
        value: DateFormat('d MMM yyyy').format(purchaseDate),
      ),
    if (shows(_Field.supplierLastPurchaseReceipt))
      if (row.lastPurchaseReceipt case final value?)
        (label: _Field.supplierLastPurchaseReceipt.label, value: value),
    if (shows(_Field.supplierQtyReceived))
      if (_supplierAmount(row.totalQtyReceived, unit) case final value?)
        (label: _Field.supplierQtyReceived.label, value: value),
    if (shows(_Field.supplierLastPo))
      if (row.lastPoDate case final value?)
        (label: _Field.supplierLastPo.label, value: value),
    if (rate != null) ...[
      if (shows(_Field.supplierRate))
        (
          label: _Field.supplierRate.label,
          value: [
            if (shows(_Field.supplierRateCurrency)) ?row.currency,
            FormattingHelper.formatAmount(rate.toDouble()),
            if (shows(_Field.supplierRateUom))
              if (row.rateUom case final unit?) '/ $unit',
          ].join(' '),
        ),
      if (shows(_Field.supplierRateSource))
        if (row.rateSource case final value?)
          (label: _Field.supplierRateSource.label, value: value),
      if (shows(_Field.supplierRateDate))
        if (row.rateDate case final value?)
          (label: _Field.supplierRateDate.label, value: value),
      if (shows(_Field.supplierRateDocument))
        if (row.rateDocument case final value?)
          (label: _Field.supplierRateDocument.label, value: value),
    ],
    if (shows(_Field.supplierLeadTime) && days != null)
      (
        label: _Field.supplierLeadTime.label,
        value: '$days ${days == '1.0' ? 'day' : 'days'}',
      ),
    if (shows(_Field.supplierLeadTimeReceipts))
      if (row.leadTimeReceipts case final count?)
        (label: _Field.supplierLeadTimeReceipts.label, value: '$count'),
    if (shows(_Field.supplierPoCount))
      if (row.poCount case final count?)
        (label: _Field.supplierPoCount.label, value: '$count'),
    if (shows(_Field.supplierReceiptCount))
      if (row.receiptCount case final count?)
        (label: _Field.supplierReceiptCount.label, value: '$count'),
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
  final List<_Badge> badges;
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
    final hasSecondLine =
        name != null || badges.isNotEmpty || qualifiers.isNotEmpty;
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
                          style: muted,
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
                    ...badges,
                  ],
                ),
              ),
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
      color: heading ? context.scheme.subtle : context.scheme.fg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: actions == null
          ? summary
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [summary, actions],
            ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.colorStatus);

  final String label;
  final String colorStatus;

  @override
  Widget build(BuildContext context) => StatusPill(
    status: label,
    colorStatus: colorStatus,
    compact: true,
    wrapLabel: true,
  );
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

String? _amount(num? quantity, String? unit) =>
    quantity == null || !quantity.isFinite
    ? null
    : suppliersByItemQuantity(quantity, unit);

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

class SuppliersByItemFooter extends StatelessWidget {
  const SuppliersByItemFooter({
    super.key,
    required this.totals,
    required this.hasResults,
    required this.excludesUnknownUom,
    required this.bottomPadding,
  });

  final Map<String, SuppliersByItemQuantityTotals> totals;
  final bool hasResults;
  final bool excludesUnknownUom;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final units = totals.keys.toList()
      ..sort((a, b) {
        final foldedOrder = a.toLowerCase().compareTo(b.toLowerCase());
        return foldedOrder == 0 ? a.compareTo(b) : foldedOrder;
      });
    final quantities = <String, num? Function(SuppliersByItemQuantityTotals)>{
      _Field.itemBalance.label: (total) => total.balanceQty,
      _Field.itemProjected.label: (total) => total.projectedQty,
      _Field.itemOpenOrders.label: (total) => total.openOrderQty,
      _Field.itemReorderQty.label: (total) => total.reorderQty,
      _Field.itemDraftOrders.label: (total) => total.draftOrderQty,
      _Field.itemQtyReceived.label: (total) => total.totalQtyReceived,
    };
    final metrics = {
      for (final metric in quantities.entries)
        if ([
              for (final unit in units)
                if (metric.value(totals[unit]!) case final quantity?)
                  (
                    text: suppliersByItemQuantity(quantity, unit),
                    zero: quantity == 0,
                  ),
            ]
            case final values when values.isNotEmpty)
          metric.key: values,
    };
    final style = _mutedStyle(context);
    final valueStyle = style?.copyWith(fontFeatures: _tabularFigures);
    final textSize = style?.fontSize ?? 12;
    final largeText =
        MediaQuery.textScalerOf(context).scale(textSize) >= 2 * textSize;
    final labelWidth = metrics.keys.fold(
      0.0,
      (widest, label) => max(widest, _width(context, label, style)),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPadding + 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              hasResults
                  ? 'End of list · Totals for all loaded items'
                  : 'End of list',
              style: style,
            ),
          ),
          if (hasResults) ...[
            const SizedBox(height: 8),
            if (totals.isEmpty)
              Text('No quantities with a known Stock UOM', style: style),
            LayoutBuilder(
              builder: (context, constraints) {
                final valueWidth =
                    constraints.maxWidth - labelWidth - _columnGap;
                final stack =
                    largeText ||
                    metrics.values.any(
                      (values) => values.any(
                        (value) =>
                            _width(context, value.text, valueStyle) >
                            valueWidth,
                      ),
                    );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final metric in metrics.entries)
                      _metric(
                        context,
                        label: metric.key,
                        values: metric.value,
                        labelWidth: labelWidth,
                        labelStyle: style,
                        valueStyle: valueStyle,
                        stack: stack,
                      ),
                  ],
                );
              },
            ),
            if (excludesUnknownUom)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Quantities without a Stock UOM are excluded',
                  style: style,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _metric(
    BuildContext context, {
    required String label,
    required List<({String text, bool zero})> values,
    required double labelWidth,
    required TextStyle? labelStyle,
    required TextStyle? valueStyle,
    required bool stack,
  }) {
    final caption = Text(label, style: labelStyle);
    final amounts = Wrap(
      alignment: WrapAlignment.end,
      spacing: 12,
      children: [
        for (final value in values)
          Text(
            value.text,
            textAlign: TextAlign.end,
            style: valueStyle?.copyWith(
              color: value.zero
                  ? context.scheme.textMuted
                  : context.scheme.text,
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: stack
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [caption, amounts],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: labelWidth, child: caption),
                const SizedBox(width: _columnGap),
                Expanded(child: amounts),
              ],
            ),
    );
  }
}
