import 'package:intl/intl.dart';

/// One age bucket of the Stock Ageing report, read from the returned columns
/// (`range1` / `range1value`, labelled e.g. "Age (0 - 90)").
class AgeBucket {
  final String qtyKey;
  final String valueKey;
  final String label;

  const AgeBucket({
    required this.qtyKey,
    required this.valueKey,
    required this.label,
  });
}

/// One column of the report, exactly as the server describes it. Cards and
/// the row sheet take their labels from here so they read as the Desk does.
class ReportColumn {
  final String fieldname;

  /// The column title, verbatim (e.g. "Variant Of", "Age (0 - 90)").
  final String label;
  final String fieldtype;

  const ReportColumn({
    required this.fieldname,
    required this.label,
    required this.fieldtype,
  });

  bool get isImage => fieldtype == 'Attach Image' || fieldtype == 'Attach';
}

/// Totals over a set of report rows.
class StockAgeingTotals {
  final double qty;
  final double value;

  /// Quantity per bucket, in bucket order.
  final List<double> bucketQty;

  const StockAgeingTotals({
    required this.qty,
    required this.value,
    required this.bucketQty,
  });
}

/// Pure logic for the Stock Ageing - Custom report, kept free of GetX and
/// widgets so every rule is unit-testable.
abstract final class StockAgeingLogic {
  static final _rangeField = RegExp(r'^range\d+$');
  static final _ageLabel = RegExp(r'^Age \((.*)\)$');

  /// Coerces a report cell to a number; null and non-numeric cells are 0.
  static double num_(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? 0;
    return 0;
  }

  static final _bucketField = RegExp(r'^range\d+(value)?$');

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
      final n = int.tryParse(part.trim());
      if (n == null) {
        if (part.trim().isNotEmpty) return columns;
        continue;
      }
      limits.add(n);
    }
    if (limits.isEmpty) return columns;

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

    bool isBucket(dynamic c) =>
        c is Map && _bucketField.hasMatch(c['fieldname']?.toString() ?? '');

    // Keep the buckets where the report has them; append if it has none.
    final out = <dynamic>[];
    var placed = false;
    for (final c in columns) {
      if (!isBucket(c)) {
        out.add(c);
      } else if (!placed) {
        out.addAll(generated);
        placed = true;
      }
    }
    if (!placed) out.addAll(generated);
    return out;
  }

  /// Reads the age buckets from `message.columns`, so the ranges are defined
  /// only on the Desk and never hard-coded here.
  static List<AgeBucket> parseBuckets(List<dynamic> columns) {
    final out = <AgeBucket>[];
    for (final c in columns) {
      if (c is! Map) continue;
      final field = c['fieldname']?.toString() ?? '';
      if (!_rangeField.hasMatch(field)) continue;
      final label = c['label']?.toString() ?? field;
      out.add(AgeBucket(
        qtyKey: field,
        valueKey: '${field}value',
        label: _ageLabel.firstMatch(label)?.group(1) ?? label,
      ));
    }
    return out;
  }

  /// Keeps only dict rows from `message.result` (a total row arrives as a
  /// list on some report configurations).
  static List<Map<String, dynamic>> parseRows(dynamic result) {
    if (result is! List) return [];
    return [
      for (final r in result)
        if (r is Map) Map<String, dynamic>.from(r),
    ];
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
            .where((r) =>
                hit(r, 'item_code') ||
                hit(r, 'item_name') ||
                hit(r, 'variant_of') ||
                hit(r, 'warehouse'))
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
    for (final r in rows) {
      qty += num_(r['qty']);
      for (var i = 0; i < buckets.length; i++) {
        bucketQty[i] += num_(r[buckets[i].qtyKey]);
        value += num_(r[buckets[i].valueKey]);
      }
    }
    return StockAgeingTotals(qty: qty, value: value, bucketQty: bucketQty);
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
    return x.length == y.length &&
        x.entries.every((e) => y[e.key] == e.value);
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
  static const fixedCardFields = {'item_code', 'qty', 'uom'};

  /// The card before the user changes anything.
  static const defaultCardFields = {
    'variant_of',
    'item_name',
    'warehouse',
    'average_age',
    ageBarField,
  };

  /// Reads `message.columns` in report order; entries without a fieldname
  /// are skipped and a missing label falls back to the fieldname.
  static List<ReportColumn> parseColumns(List<dynamic> columns) => [
        for (final c in columns)
          if (c is Map && (c['fieldname']?.toString() ?? '').isNotEmpty)
            ReportColumn(
              fieldname: c['fieldname'].toString(),
              label: (c['label']?.toString().trim().isNotEmpty ?? false)
                  ? c['label'].toString().trim()
                  : c['fieldname'].toString(),
              fieldtype: c['fieldtype']?.toString() ?? 'Data',
            ),
      ];

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
        final f = column.fieldtype == 'Currency' ||
                column.fieldname.endsWith('value')
            ? _valueFormat
            : _floatFormat;
        return f.format(num_(v));
      case 'Int':
        return _intFormat.format(num_(v));
      default:
        return v.toString().trim();
    }
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
    final newDay = fetchedAt.year != now.year ||
        fetchedAt.month != now.month ||
        fetchedAt.day != now.day;
    // Within a day, pick up stock movements without refetching on every open.
    return newDay || now.difference(fetchedAt) >= maxCacheAge;
  }
}
