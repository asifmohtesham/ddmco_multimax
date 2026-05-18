import 'doctype_picker_column.dart';

// ────────────────────────────────────────────────────────────────────────────
// DocTypePickerConfig
// ────────────────────────────────────────────────────────────────────────────

/// Configuration for a generic DocType picker bottom sheet.
///
/// This class defines how a DocType should be displayed and queried
/// in the picker interface. It supports:
/// - Custom filters and search fields
/// - Multi-column layouts with flexible column definitions
/// - Subtitle metadata formatting
/// - Optional barcode scanning
/// - Cache-first loading with manual refresh
///
/// A single [DocTypePickerConfig] describes everything the picker needs to
/// display, search, and filter records for one ERPNext DocType. Business
/// logic (side-effects after selection) belongs in the calling controller,
/// not here.
///
/// ### Minimal example
/// ```dart
/// const itemPickerConfig = DocTypePickerConfig(
///   doctype: 'Item',
///   title: 'Select Item',
///   columns: [
///     DocTypePickerColumn(
///       fieldName: 'item_code',
///       label: 'Item Code',
///       isPrimary: true,
///     ),
///   ],
/// );
/// ```/// ```dart
/// const itemPickerConfig = DocTypePickerConfig(
///   doctype: 'Item',
///   title: 'Select Item',
///   columns: [
///     DocTypePickerColumn(
///       fieldname: 'item_code',
///       label: 'Item Code',
///       isPrimary: true,
///       flex: 2,
///     ),
///     DocTypePickerColumn(
///       fieldname: 'item_name',
///       label: 'Item Name',
///       isSecondary: true,
///       flex: 3,
///     ),
///   ],
///   subtitleFields: ['item_group', 'variant_of', 'country_of_origin'],
/// );
/// ```
class DocTypePickerConfig {
  /// ERPNext DocType name, e.g. `'Item'`, `'BOM'`, `'Warehouse'`.
  final String doctype;

  /// Title displayed at the top of the bottom sheet.
  final String title;

  /// Column definitions for the record rows.
  ///
  /// At least one column should have [DocTypePickerColumn.isPrimary] set to
  /// `true`, and one [DocTypePickerColumn.isSecondary] for the mobile layout.
  final List<DocTypePickerColumn> columns;

  /// Fieldnames whose values are joined as a subtitle line below the
  /// secondary column in the mobile stacked layout.
  ///
  /// Empty or null values are omitted automatically.
  /// Rendered as `value1 \u2022 value2 \u2022 value3`.
  final List<String> subtitleFields;

  /// Optional formatter applied to each subtitle field value before joining.
  ///
  /// Receives the fieldname and its raw value.  Return the formatted string
  /// or `null` to omit that field from the subtitle.
  ///
  /// Example — prefix `variant_of` with a label:
  /// ```dart
  /// subtitleFormatter: (field, value) {
  ///   if (field == 'variant_of') return 'Variant of $value';
  ///   return value;
  /// },
  /// ```
  final String? Function(String fieldname, String value)? subtitleFormatter;

  /// Frappe-style filter list passed to the API query.
  ///
  /// Each filter is a list of four elements:
  /// `[doctype, fieldname, operator, value]`
  ///
  /// Example:
  /// ```dart
  /// filters: [
  ///   ['Item', 'disabled', '=', 0],
  ///   ['Item', 'is_stock_item', '=', 1],
  /// ]
  /// ```
  final List<List<dynamic>> filters;

  /// Fields to include in the API `fields` parameter.
  ///
  /// Should include all [columns] fieldnames and all [subtitleFields].
  /// Defaults to an empty list; the datasource layer derives fields from
  /// [columns] and [subtitleFields] when this is empty.
  final List<String> extraFields;

  /// Fields searched when the user types in the search box.
  ///
  /// Passed as `search_field` / OR-filter to the API.  If empty the
  /// datasource falls back to the DocType's `search_fields` meta.
  final List<String> searchFields;

  /// Cache key used to store and retrieve results from local cache.
  ///
  /// Use a descriptive, unique key, e.g. `'item_picker_stock'`.
  /// When `null` caching is disabled for this picker.
  final String? cacheKey;

  /// Whether to show a refresh icon in the sheet header.
  ///
  /// Defaults to `true`.  When tapped the cache is bypassed and a live
  /// ERPNext API call is made.
  final bool allowRefresh;

  /// When `true` the sheet subscribes to the app-wide barcode scan stream
  /// and prefills the search box when a scan event is received.
  ///
  /// Defaults to `false`.  Enable only for DocTypes where barcode lookup
  /// makes sense (e.g. Item).
  final bool enableBarcodeScan;

  /// Optional row-level selectability resolver.
  ///
  /// Return `false` to render a row as disabled (visible but not tappable).
  /// Return `true` (default) to allow selection.
  ///
  /// Example — exclude Warehouse group nodes:
  /// ```dart
  /// selectabilityResolver: (row) => row['is_group'] != 1,
  /// ```
  final bool Function(Map<String, dynamic> row)? selectabilityResolver;

  /// Optional temporary loader used during development / UI testing before
  /// the real datasource is wired in.
  ///
  /// When non-null this overrides the cache/API fetch path entirely.
  /// Remove before shipping.
  final Future<List<Map<String, dynamic>>> Function(String search)? loader;

  const DocTypePickerConfig({
    required this.doctype,
    required this.title,
    required this.columns,
    this.subtitleFields = const [],
    this.subtitleFormatter,
    this.filters = const [],
    this.extraFields = const [],
    this.searchFields = const [],
    this.cacheKey,
    this.allowRefresh = true,
    this.enableBarcodeScan = false,
    this.selectabilityResolver,
    this.loader,
  });

  /// Returns the full list of fieldnames that should be requested from the
  /// API: column fieldnames + subtitle fieldnames + any extra fields,
  /// de-duplicated.
  List<String> get resolvedFields {
    final seen = <String>{};
    final result = <String>[];
    void add(String f) {
      if (seen.add(f)) result.add(f);
    }
    for (final c in columns) {
      add(c.fieldname);
    }
    for (final s in subtitleFields) {
      add(s);
    }
    for (final e in extraFields) {
      add(e);
    }
    return result;
  }

  /// Returns columns marked as [DocTypePickerColumn.visibleOnMobile],
  /// sorted so the primary column is always first.
  List<DocTypePickerColumn> get mobileColumns {
    final visible = columns.where((c) => c.visibleOnMobile).toList();
    visible.sort((a, b) {
      if (a.isPrimary) return -1;
      if (b.isPrimary) return 1;
      return 0;
    });
    return visible;
  }
}
