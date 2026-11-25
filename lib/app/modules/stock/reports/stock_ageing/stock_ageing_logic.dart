import 'package:intl/intl.dart';
import '../../../global_widgets/report_fields/report_field.dart';

/// One age bucket of the Stock Ageing report, read from the returned columns
/// (`range1` / `range1value`, labelled e.g. "Age (0 - 90)").
class AgeBucket {
  final String qtyKey;
  final String valueKey;
  final String label;
  final String? reportLabel;
  final String? rangeHint;

  const AgeBucket({
    required this.qtyKey,
    required this.valueKey,
    required this.label,
    this.reportLabel,
    this.rangeHint,
  });

  String get displayLabel => reportLabel ?? label;

  String get qualifiedLabel =>
      rangeHint == null ? displayLabel : '$displayLabel · $rangeHint';
}

/// One column of the report, exactly as the server describes it. Cards and
/// the row sheet take their labels from here so they read as the Desk does.
class ReportColumn {
  final String fieldname;

  /// The column title, verbatim (e.g. "Variant Of", "Age (0 - 90)").
  final String label;
  final String fieldtype;
  final bool listed;
  final String? interval;
  final String? rangeHint;

  const ReportColumn({
    required this.fieldname,
    required this.label,
    required this.fieldtype,
    this.listed = true,
    this.interval,
    this.rangeHint,
  });

  bool get isImage => fieldtype == 'Attach Image' || fieldtype == 'Attach';
}

/// Totals over a set of report rows.
class StockAgeingTotals {
  final double qty;
  final double value;

  /// Quantity per bucket, in bucket order.
  final List<double> bucketQty;
  final int qtyCount;
  final int valueCount;
  final List<int> bucketQtyCount;

  const StockAgeingTotals({
    required this.qty,
    required this.value,
    required this.bucketQty,
    required this.qtyCount,
    required this.valueCount,
    required this.bucketQtyCount,
  });
}

/// Pure logic for the Stock Ageing - Custom report, kept free of GetX and
/// widgets so every rule is unit-testable.
abstract final class StockAgeingLogic {
  static final _rangeField = RegExp(r'^range\d+$');
  static final _ageLabel = RegExp(r'^Age \((.*)\)$');
  static final _labelInterval = RegExp(r'\(([^()]*)\)\s*$');
  static final _rangeLimit = RegExp(r'^\d+$');

  static const fixedLabels = {
    'item_code': 'Item Code',
    'item_name': 'Item Name',
    'warehouse': 'Warehouse',
    'qty': 'Available Qty',
    'uom': 'UOM',
    'variant_of': 'Variant Of',
    'average_age': 'Average Age',
    'image': 'Item Image',
    'country_of_origin': 'Country of Origin',
    'description': 'Description',
    'item_group': 'Item Group',
    'brand': 'Brand',
    'earliest': 'Earliest',
    'latest': 'Latest',
    'range1': 'Age (0 - 90)',
    'range1value': 'Value (0 - 90)',
    'range2': 'Age (91 - 180)',
    'range2value': 'Value (91 - 180)',
    'range3': 'Age (181 - 360)',
    'range3value': 'Value (181 - 360)',
    'range4': 'Age (361 - 720)',
    'range4value': 'Value (361 - 720)',
    'range5': 'Age (721 - Above)',
    'range5value': 'Value (721 - Above)',
  };

  /// Coerces a report cell to a number; null and non-numeric cells are 0.
  static double num_(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? 0;
    return 0;
  }

  static double? measurement(Object? cell) {
    final value = cell is num
        ? cell.toDouble()
        : double.tryParse(cell?.toString().trim() ?? '');
    return value?.isFinite == true ? value : null;
  }

  static final _bucketField = RegExp(r'^range\d+(value)?$');
  static final _legacyBucket = RegExp(
    r'^(Age|Value) \(\s*\d+\s*[-–—]\s*(?:\d+|Above)\s*\)$',
  );

  static List<DeskColumn> deskColumns(List<dynamic> rawColumns) {
    final columns = decodeDeskColumns(rawColumns);
    var ages = 0;
    var values = 0;
    return List.unmodifiable([
      for (final (index, column) in columns.indexed)
        if (rawColumns[index] is String)
          if (_legacyBucket.firstMatch(column.label)?.group(1) == 'Age')
            (fieldname: 'range${++ages}', label: column.label)
          else if (_legacyBucket.firstMatch(column.label)?.group(1) == 'Value')
            (fieldname: 'range${++values}value', label: column.label)
          else if (column.fieldname == 'available_qty')
            (fieldname: 'qty', label: column.label)
          else if (column.fieldname == 'item_image')
            (fieldname: 'image', label: column.label)
          else
            column
        else
          column,
    ]);
  }

  /// Rebuilds the bucket columns of [columns] for the ageing [range] the
  /// data was calculated with (e.g. "360, 720").
  ///
  /// "Stock Ageing - Custom" is a Frappe Custom Report, whose column list is
  /// frozen at the titles it was saved with: the server returns
  /// "Age (0 - 90)"… even when the rows were calculated for another range,
  /// and omits columns for buckets the saved list never had. Core Stock
  /// Ageing names buckets `range1`, `range1value`, … titled
  /// "Age (0 - 360)" / "Value (0 - 360)", ending "(N+1 - Above)"; this
  /// reproduces that, in place of the frozen bucket columns.
  ///
  /// A blank or unreadable [range] returns [columns] unchanged.
  static List<dynamic> applyRange(List<dynamic> columns, String? range) {
    final limits = <int>[];
    for (final part in (range ?? '').split(',')) {
      final token = part.trim();
      final limit = _rangeLimit.hasMatch(token) ? int.tryParse(token) : null;
      if (limit != null) limits.add(limit);
    }
    if (limits.isEmpty) return columns;
    limits.sort();

    final titles = [
      '0 - ${limits.first}',
      for (var i = 1; i < limits.length; i++)
        '${limits[i - 1] + 1} - ${limits[i]}',
      '${limits.last + 1} - Above',
    ];
    final generated = <Map<String, dynamic>>[
      for (var i = 0; i < titles.length; i++) ...[
        {
          'fieldname': 'range${i + 1}',
          'label': 'Age (${titles[i]})',
          'fieldtype': 'Float',
        },
        {
          'fieldname': 'range${i + 1}value',
          'label': 'Value (${titles[i]})',
          'fieldtype': 'Float',
        },
      ],
    ];

    // Keep the buckets where the report has them; append if it has none.
    final out = <dynamic>[];
    final descriptors = deskColumns(columns);
    var placed = false;
    for (final (index, c) in columns.indexed) {
      if (!_bucketField.hasMatch(descriptors[index].fieldname)) {
        out.add(c);
      } else if (!placed) {
        out.addAll(generated);
        placed = true;
      }
    }
    if (!placed) out.addAll(generated);
    return out;
  }

  /// Keeps the returned header apart from the interval the server calculated.
  /// Additional calculated buckets remain readable without a Fields tile.
  static List<ReportColumn> effectiveColumns(
    List<dynamic> columns,
    String? range,
  ) {
    final raw = parseColumns(columns);
    final ranged = applyRange(columns, range);
    if (identical(ranged, columns)) return raw;
    final byKey = {for (final column in raw) column.fieldname: column};
    return [
      for (final generated in parseColumns(ranged))
        if (_bucketField.hasMatch(generated.fieldname))
          _effectiveBucketColumn(generated, byKey[generated.fieldname])
        else
          generated,
    ];
  }

  static ReportColumn _effectiveBucketColumn(
    ReportColumn generated,
    ReportColumn? raw,
  ) {
    final interval = _labelInterval.firstMatch(generated.label)!.group(1)!;
    final rawInterval = _labelInterval.firstMatch(raw?.label ?? '')?.group(1);
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('–', '-')
        .replaceAll('—', '-');
    final differs =
        raw?.listed == true &&
        (rawInterval == null || normalize(rawInterval) != normalize(interval));
    return ReportColumn(
      fieldname: generated.fieldname,
      label: raw?.listed == true ? raw!.label : generated.label,
      fieldtype: raw?.fieldtype == 'Currency'
          ? 'Currency'
          : generated.fieldtype,
      listed: raw?.listed == true,
      interval: interval,
      rangeHint: differs
          ? 'Range for this run: ${interval.replaceAll(' - ', '–')}'
          : null,
    );
  }

  /// Reads the age buckets from `message.columns`, so the ranges are defined
  /// only on the Desk and never hard-coded here.
  static List<AgeBucket> parseBuckets(List<dynamic> columns) {
    final out = <AgeBucket>[];
    for (final raw in columns) {
      final column = raw is ReportColumn
          ? raw
          : parseColumns([raw]).firstOrNull;
      if (column == null || !_rangeField.hasMatch(column.fieldname)) continue;
      out.add(
        AgeBucket(
          qtyKey: column.fieldname,
          valueKey: '${column.fieldname}value',
          label:
              column.interval ??
              _ageLabel.firstMatch(column.label)?.group(1) ??
              column.label,
          reportLabel: column.listed ? column.label : null,
          rangeHint: column.rangeHint,
        ),
      );
    }
    return out;
  }

  static List<Map<String, dynamic>> parseRows(
    dynamic result, {
    List<DeskColumn> columns = const [],
    bool addTotalRow = false,
  }) {
    if (result is! List) return [];
    final rows = <Map<String, dynamic>>[];
    for (final (index, raw) in result.indexed) {
      if (raw is List &&
          (columns.isEmpty || (addTotalRow && index == result.length - 1))) {
        continue;
      }
      final row = decodeDeskRow(raw, columns);
      if (row == null ||
          row['_is_total_row'] == true ||
          row['is_total_row'] == true ||
          (row['item_code']?.toString().trim().isEmpty ?? true)) {
        continue;
      }
      rows.add(row);
    }
    return rows;
  }

  /// Applies the on-phone search and sort and returns a new list.
  ///
  /// [sort]: `age` (average age, oldest first) | `qty` (largest first) |
  /// `old` (quantity in the last bucket, largest first) | `code`.
  static List<Map<String, dynamic>> filterAndSort(
    List<Map<String, dynamic>> rows, {
    String search = '',
    String sort = 'age',
    List<AgeBucket> buckets = const [],
  }) {
    final q = search.trim().toLowerCase();
    bool hit(Map<String, dynamic> r, String key) =>
        (r[key]?.toString().toLowerCase() ?? '').contains(q);

    final out = q.isEmpty
        ? List<Map<String, dynamic>>.of(rows)
        : rows
              .where(
                (r) =>
                    hit(r, 'item_code') ||
                    hit(r, 'item_name') ||
                    hit(r, 'variant_of') ||
                    hit(r, 'warehouse'),
              )
              .toList();

    String code(Map<String, dynamic> r) => r['item_code']?.toString() ?? '';
    double metric(Map<String, dynamic> r) => switch (sort) {
      'qty' => num_(r['qty']),
      'old' => buckets.isEmpty ? 0 : num_(r[buckets.last.qtyKey]),
      'code' => 0,
      _ => num_(r['average_age']),
    };

    out.sort((a, b) {
      final byMetric = metric(b).compareTo(metric(a));
      return byMetric != 0 ? byMetric : code(a).compareTo(code(b));
    });
    return out;
  }

  static StockAgeingTotals totals(
    List<Map<String, dynamic>> rows,
    List<AgeBucket> buckets,
  ) {
    var qty = 0.0;
    var value = 0.0;
    final bucketQty = List<double>.filled(buckets.length, 0);
    var qtyCount = 0;
    var valueCount = 0;
    final bucketQtyCount = List<int>.filled(buckets.length, 0);
    for (final r in rows) {
      if (measurement(r['qty']) case final measured?) {
        qty += measured;
        qtyCount++;
      }
      for (var i = 0; i < buckets.length; i++) {
        if (measurement(r[buckets[i].qtyKey]) case final measured?) {
          bucketQty[i] += measured;
          bucketQtyCount[i]++;
        }
        if (measurement(r[buckets[i].valueKey]) case final measured?) {
          value += measured;
          valueCount++;
        }
      }
    }
    return StockAgeingTotals(
      qty: qty,
      value: value,
      bucketQty: bucketQty,
      qtyCount: qtyCount,
      valueCount: valueCount,
      bucketQtyCount: bucketQtyCount,
    );
  }

  /// Whether two filter maps mean the same thing to the server: blank, null
  /// and `0` entries are "unset", and values compare as trimmed strings.
  /// This is the app's version of the Desk's "are these still the default
  /// filters?" check.
  static bool sameFilters(Map<String, dynamic> a, Map<String, dynamic> b) {
    Map<String, String> norm(Map<String, dynamic> m) => {
      for (final e in m.entries)
        if (e.value != null &&
            e.value.toString().trim().isNotEmpty &&
            e.value.toString().trim() != '0')
          e.key: e.value.toString().trim(),
    };
    final x = norm(a), y = norm(b);
    return x.length == y.length && x.entries.every((e) => y[e.key] == e.value);
  }

  /// Absolute URL for a row's `image` cell: relative Frappe paths
  /// ("/files/x.jpg") are prefixed with [baseUrl]; absolute URLs are kept;
  /// blank or null is null.
  static String? imageUrl(dynamic image, String baseUrl) {
    final path = image?.toString().trim() ?? '';
    if (path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.encodeFull('$base${path.startsWith('/') ? '' : '/'}$path');
  }

  /// Card-field key for the stacked age bar, the one card element that is
  /// not a report column.
  static const ageBarField = '_age_bar';

  /// Columns that are always on the card and so are not offered as choices.
  static const fixedCardFields = {
    'item_code',
    'item_name',
    'warehouse',
    'qty',
    'uom',
  };

  /// The card before the user changes anything.
  static const defaultCardFields = {
    'variant_of',
    'item_name',
    'warehouse',
    'average_age',
    ageBarField,
  };

  static List<ReportColumn> parseColumns(List<dynamic> columns) {
    final parsed = <ReportColumn>[];
    for (final (index, column) in deskColumns(columns).indexed) {
      if (column.fieldname.isEmpty) continue;
      final raw = columns[index];
      final listed = column.label.trim().isNotEmpty;
      final parts = raw is String ? raw.split(':') : const <String>[];
      parsed.add(
        ReportColumn(
          fieldname: column.fieldname,
          label: listed ? column.label : fixedLabels[column.fieldname] ?? '',
          fieldtype: raw is Map
              ? raw['fieldtype']?.toString() ?? 'Data'
              : parts.length > 1
              ? parts[1].split('/').first
              : 'Data',
          listed: listed,
        ),
      );
    }
    return parsed;
  }

  static final _floatFormat = NumberFormat('#,##0.##', 'en_GB');
  static final _valueFormat = NumberFormat('#,##0.00', 'en_GB');
  static final _intFormat = NumberFormat('#,##0', 'en_GB');

  /// Formats one cell for display by its column type. Blank and null are
  /// "—"; value columns (`…value`) keep two decimals.
  static String formatCell(ReportColumn column, dynamic v) {
    if (v == null || v.toString().trim().isEmpty) return '—';
    switch (column.fieldtype) {
      case 'Float':
      case 'Currency':
      case 'Percent':
        final f =
            column.fieldtype == 'Currency' || column.fieldname.endsWith('value')
            ? _valueFormat
            : _floatFormat;
        final number = measurement(v);
        return number == null ? '—' : f.format(number);
      case 'Int':
        final number = measurement(v);
        return number == null ? '—' : _intFormat.format(number);
      default:
        return v.toString().trim();
    }
  }

  /// Columns whose cells are ages in whole days, counted back from the
  /// report's "as on" date.
  static const ageFields = {'average_age', 'earliest', 'latest'};

  /// Age columns that belong to a real batch, so the age maps to the year it
  /// arrived. Average Age is a qty-weighted mean over batches; its "year"
  /// could be one in which nothing arrived, so it gets none.
  static const datedAgeFields = {'earliest', 'latest'};

  /// The date the report's ages are counted from: [asOn] (yyyy-MM-dd), else
  /// the day of [fetchedAt] (a run without a date is as on the server's
  /// today), else null.
  static DateTime? reportDate(String asOn, DateTime? fetchedAt) {
    final d = DateTime.tryParse(asOn.trim());
    if (d != null) return DateTime(d.year, d.month, d.day);
    if (fetchedAt == null) return null;
    return DateTime(fetchedAt.year, fetchedAt.month, fetchedAt.day);
  }

  /// Formats a cell for the detail sheet: as [formatCell], except that age
  /// columns read "1,612 days", and batch ages add the year the batch
  /// arrived, counted back from [asOn] ("1,612 days · since 2022").
  static String formatDetailCell(
    ReportColumn column,
    dynamic v, {
    DateTime? asOn,
  }) {
    final text = formatCell(column, v);
    if (text == '—' || !ageFields.contains(column.fieldname)) return text;
    final days = num_(v);
    final withUnit = '$text ${days == 1 ? 'day' : 'days'}';
    if (asOn == null || !datedAgeFields.contains(column.fieldname)) {
      return withUnit;
    }
    final since = DateTime(asOn.year, asOn.month, asOn.day - days.round());
    return '$withUnit · since ${since.year}';
  }

  /// Reads a stored card-field selection (column fieldnames, plus
  /// [ageBarField]). Null (never saved) or a value of the wrong shape gives
  /// the defaults; an empty saved list is a valid choice. Names are kept even
  /// if the report no longer has that column, so a choice survives a column
  /// being removed and re-added on the Desk.
  static Set<String> decodeCardFields(dynamic stored) => stored is List
      ? {for (final name in stored) name.toString()}
      : {...defaultCardFields};

  /// How long a same-day cached run is shown without a background refetch.
  static const maxCacheAge = Duration(hours: 4);

  /// Whether the cached default run, fetched at [fetchedAt], is stale enough
  /// that opening the screen at [now] should refetch it in the background
  /// (the cached rows stay on screen meanwhile; a refetch costs ~20 s of
  /// server time).
  static bool shouldAutoRefresh({
    required DateTime fetchedAt,
    required DateTime now,
  }) {
    // A fetch time ahead of the clock means the device time changed.
    if (fetchedAt.isAfter(now)) return true;
    // Ages are whole days as on a date, so a new day shifts every row.
    final newDay =
        fetchedAt.year != now.year ||
        fetchedAt.month != now.month ||
        fetchedAt.day != now.day;
    // Within a day, pick up stock movements without refetching on every open.
    return newDay || now.difference(fetchedAt) >= maxCacheAge;
  }
}
