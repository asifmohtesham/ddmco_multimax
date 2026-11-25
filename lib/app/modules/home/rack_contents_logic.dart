/// Pure helpers behind the Dashboard rack-contents sheet: which Item master
/// fields to ask for, how to read the Item list reply, and how to merge it
/// with the Stock Balance rows of the scanned rack.
///
/// Free of Flutter/GetX so the merge unit-tests without a binding. The rows
/// themselves come from `rackRowsFromStockBalance` in `rack_scan_logic.dart`.
library;

import 'package:multimax/app/core/utils/html_text.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';

/// Item fields the rack card shows that the Stock Balance report does not
/// carry. Item Name, Item Group and the stock UOM already arrive with the
/// report rows, so they are not asked for again.
///
/// Every field is a standard ERPNext Item field on v15 and v16.
const rackItemFields = <String>[
  'name',
  'image',
  'variant_of',
  'country_of_origin',
  'brand',
  'description',
  'disabled',
];

/// Distinct, non-empty item codes of [rows], in first-seen order — the
/// `name in [...]` list for the one Item request.
List<String> rackItemCodes(List<Map<String, dynamic>> rows) {
  final seen = <String>{};
  return [
    for (final row in rows)
      if (_text(row['item_code']) case final code? when seen.add(code)) code,
  ];
}

/// Item list reply (`/api/resource/Item`, `{"data": [...]}`) keyed by Item
/// `name`.
///
/// Throws [FormatException] when the body has no `data` list, so a reply the
/// app does not recognise is treated like a failed fetch.
Map<String, Map<String, dynamic>> itemFieldsByCode(Object? body) {
  final data = body is Map ? body['data'] : null;
  if (data is! List) {
    throw const FormatException('Item list response has no data list');
  }
  return {
    for (final entry in data)
      if (entry is Map && _text(entry['name']) != null)
        _text(entry['name'])!: Map<String, dynamic>.from(entry),
  };
}

/// One card of the rack-contents sheet: a Stock Balance row plus, when the
/// Item fetch worked, that item's master fields.
class RackContentsEntry {
  const RackContentsEntry({
    required this.itemCode,
    required this.itemName,
    required this.balanceQty,
    this.stockUom,
    this.itemGroup,
    this.batchNo,
    this.image,
    this.variantOf,
    this.countryOfOrigin,
    this.brand,
    this.description,
    this.disabled = false,
  });

  // From the Stock Balance row.
  final String itemCode;
  final String itemName;
  final double? balanceQty;
  final String? stockUom;
  final String? itemGroup;
  final String? batchNo;

  // From the Item master (null when the fetch failed or the field is empty).
  /// Server-relative path such as `/files/3000247-SGPU-14.jpg`, or a full URL.
  final String? image;
  final String? variantOf;
  final String? countryOfOrigin;
  final String? brand;

  /// Plain text, and only when it says more than the item name or code does.
  final String? description;
  final bool disabled;
}

/// One load of the rack-contents sheet: its entries on a given date, and
/// whether the Item master fetch behind them failed.
class RackContentsSnapshot {
  const RackContentsSnapshot({
    required this.entries,
    this.itemDetailsFailed = false,
    this.columns,
    this.baseUrl,
    this.isCurrentOwner,
  });

  final List<RackContentsEntry> entries;
  final bool itemDetailsFailed;
  final List<DeskColumn>? columns;
  final String? baseUrl;

  /// Checks the app session captured when the scan started, including changes
  /// before a deferred modal builder has mounted.
  final bool Function()? isCurrentOwner;
}

/// Merges the rack's Stock Balance [rows] with [itemFields] (from
/// [itemFieldsByCode]), one entry per row, in report order.
///
/// [itemFields] is null when the Item fetch failed; the entries then carry
/// the report data alone. A row whose item is missing from [itemFields]
/// (no read permission on that Item, say) does too. `variant_of` falls back
/// to the row's own value, which some Stock Balance versions include.
List<RackContentsEntry> mergeRackContents(
  List<Map<String, dynamic>> rows,
  Map<String, Map<String, dynamic>>? itemFields,
) {
  return [
    for (final row in rows) _entry(row, itemFields?[_text(row['item_code'])]),
  ];
}

RackContentsEntry _entry(Map<String, dynamic> row, Map<String, dynamic>? item) {
  final code = _text(row['item_code']) ?? 'Unknown';
  final name = _text(row['item_name']) ?? code;
  final quantity = row['bal_qty'] ?? row['balance_qty'];
  final balance = quantity is num
      ? quantity.toDouble()
      : double.tryParse(quantity?.toString() ?? '');
  return RackContentsEntry(
    itemCode: code,
    itemName: name,
    balanceQty: balance?.isFinite == true ? balance : null,
    stockUom: _text(row['stock_uom']),
    itemGroup: _text(row['item_group']),
    batchNo: _text(row['batch_no']),
    image: _text(item?['image']),
    variantOf: _text(item?['variant_of']) ?? _text(row['variant_of']),
    countryOfOrigin: _text(item?['country_of_origin']),
    brand: _text(item?['brand']),
    description: _usefulDescription(item?['description'], code, name),
    disabled: _truthy(item?['disabled']),
  );
}

/// The description as one line of plain text, or null when it is empty or
/// only repeats the item code or name — ERPNext copies the item name into
/// the description by default, so most items would otherwise say it twice.
String? _usefulDescription(Object? raw, String code, String name) {
  final html = _text(raw);
  if (html == null) return null;
  final plain = htmlToSingleLine(html);
  if (plain.isEmpty) return null;
  final lower = plain.toLowerCase();
  if (lower == code.toLowerCase() || lower == name.toLowerCase()) return null;
  return plain;
}

/// Entries matching the sheet's search [query], in their original order.
///
/// The query is split on whitespace and every word must appear (case-
/// insensitive) in at least one of the card's text fields, so "focus belt"
/// finds a FOCUS-brand belt whatever order the words are typed in. A blank
/// query returns [entries] unchanged.
List<RackContentsEntry> filterRackContents(
  List<RackContentsEntry> entries,
  String query,
) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return entries;
  return [
    for (final e in entries)
      if (_matchesAll(_searchText(e), words)) e,
  ];
}

String _searchText(RackContentsEntry e) => [
  e.itemCode,
  e.itemName,
  e.variantOf,
  e.brand,
  e.itemGroup,
  e.batchNo,
  e.countryOfOrigin,
  e.description,
].whereType<String>().join('\n').toLowerCase();

bool _matchesAll(String haystack, List<String> words) =>
    words.every(haystack.contains);

/// Whether [date] falls on the same calendar day as [today].
bool isSameDay(DateTime date, DateTime today) =>
    date.year == today.year &&
    date.month == today.month &&
    date.day == today.day;

/// Sum of the measured balances. The footer marks missing terms separately.
double rackQtyTotal(List<RackContentsEntry> entries) =>
    entries.fold(0.0, (sum, e) => sum + (e.balanceQty ?? 0));

/// The one stock UOM every entry shares, or null when they differ (or none
/// has one) — a total across mixed units must not be labelled with one.
String? sharedStockUom(List<RackContentsEntry> entries) {
  final uoms = {for (final e in entries) e.stockUom};
  return uoms.length == 1 ? uoms.single : null;
}

/// Full URL for an Item `image` value: server-relative paths are joined to
/// [baseUrl]; absolute URLs are kept. Null for an empty value.
String? itemImageUrl(String baseUrl, String? image) {
  final path = image?.trim() ?? '';
  if (path.isEmpty) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  final base = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  return path.startsWith('/') ? '$base$path' : '$base/$path';
}

String? _text(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

bool _truthy(Object? value) =>
    value == true || value == 1 || value == '1' || value == 1.0;
