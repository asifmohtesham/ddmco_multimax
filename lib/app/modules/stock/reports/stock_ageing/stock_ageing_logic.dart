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

/// An optional field on a report row card. Item code and quantity are always
/// shown; everything else is the user's choice.
enum AgeingCardField {
  image('Item image'),
  itemName('Item name'),
  warehouse('Warehouse'),
  averageAge('Average age'),
  bucketBar('Age bar'),
  value('Stock value'),
  earliestLatest('Earliest / latest age'),
  variantOf('Variant of'),
  itemGroup('Item group'),
  brand('Brand'),
  country('Country of origin');

  final String label;
  const AgeingCardField(this.label);

  /// The card as first shipped.
  static const defaults = {itemName, warehouse, averageAge, bucketBar};
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

  /// Sum of every bucket's value for one row.
  static double rowValue(Map<String, dynamic> row, List<AgeBucket> buckets) {
    var v = 0.0;
    for (final b in buckets) {
      v += num_(row[b.valueKey]);
    }
    return v;
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

  /// Reads a stored card-field selection. Null (never saved) or a value of
  /// the wrong shape gives the defaults; unknown names (a field removed in a
  /// later version) are dropped. An empty saved list is a valid choice.
  static Set<AgeingCardField> decodeCardFields(dynamic stored) {
    if (stored is! List) return {...AgeingCardField.defaults};
    final byName = {for (final f in AgeingCardField.values) f.name: f};
    return {
      for (final name in stored)
        if (byName[name.toString()] != null) byName[name.toString()]!,
    };
  }

  /// Stored form of a selection, in declaration order.
  static List<String> encodeCardFields(Set<AgeingCardField> fields) => [
        for (final f in AgeingCardField.values)
          if (fields.contains(f)) f.name,
      ];

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
