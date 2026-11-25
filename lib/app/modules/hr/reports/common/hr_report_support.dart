/// Pure helpers shared by the HRMS script-report screens (Shift Attendance,
/// Employee Hours Utilisation).
///
/// Free of Flutter/GetX so the wire contract unit-tests without a binding.
library;

import 'package:intl/intl.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';

/// Keep positional cells associated with the original column index. Known
/// aliases cover older Frappe header strings for the same measures.
List<Map<String, dynamic>> decodeHrReportRows(
  Object? raw,
  List<DeskColumn> columns, {
  Map<String, List<String>> aliases = const {},
}) => [
  if (raw is List)
    for (final entry in raw)
      if (decodeDeskRow(entry, columns) case final row?)
        {
          ...row,
          for (final alias in aliases.entries)
            if (!row.containsKey(alias.key))
              for (final key in alias.value)
                if (row.containsKey(key)) alias.key: row[key],
        },
];

/// Rows of a `frappe.desk.query_report.run` response as string-keyed maps;
/// anything that is not a map (a total row, a stray scalar) is skipped.
Iterable<Map<String, dynamic>> reportMaps(Object? raw) sync* {
  if (raw is! List) return;
  for (final entry in raw) {
    if (entry is Map) yield Map<String, dynamic>.from(entry);
  }
}

/// The colour a report-summary card carries in Desk (`indicator`).
enum SummaryIndicator { green, red, blue, orange, none }

SummaryIndicator _indicatorFrom(Object? value) =>
    switch (value?.toString().trim().toLowerCase() ?? '') {
      'green' => SummaryIndicator.green,
      'red' => SummaryIndicator.red,
      'blue' => SummaryIndicator.blue,
      'orange' || 'yellow' => SummaryIndicator.orange,
      _ => SummaryIndicator.none,
    };

/// One card of a script report's `report_summary`, exactly as the server
/// computed it — the app never recomputes these.
class ReportSummaryItem {
  const ReportSummaryItem({
    required this.label,
    required this.value,
    this.indicator = SummaryIndicator.none,
  });

  final String label;

  /// Display text: integers stay integers, floats keep at most two decimals,
  /// strings (e.g. `"82.5%"`) pass through.
  final String value;

  final SummaryIndicator indicator;
}

/// `report_summary` → cards, in server order. Missing or malformed → empty.
List<ReportSummaryItem> parseReportSummary(Object? raw) => [
  for (final item in reportMaps(raw))
    if ((item['label']?.toString() ?? '').isNotEmpty)
      ReportSummaryItem(
        label: item['label'].toString(),
        value: _summaryValue(item['value']),
        indicator: _indicatorFrom(item['indicator']),
      ),
];

String _summaryValue(Object? value) {
  if (value == null) return '—';
  if (value is int) return NumberFormat.decimalPattern().format(value);
  if (value is num) {
    return value == value.roundToDouble()
        ? NumberFormat.decimalPattern().format(value.round())
        : NumberFormat('#,##0.##').format(value);
  }
  return value.toString();
}

/// Reads a number the server may send as `num`, a numeric string, or null.
double asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

/// `true` for `1`, `true`, `"1"`; Frappe Check fields arrive as ints.
bool asFlag(Object? value) =>
    value == true || value == 1 || value?.toString() == '1';

/// Trimmed string, or null when blank.
String? asText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

/// Decimal hours to `"3h 56m"`; whole hours drop the minutes (`"10h"`),
/// under an hour reads `"45m"`, zero reads `"0h"`.
String formatHours(double hours) {
  if (hours <= 0) return '0h';
  final totalMinutes = (hours * 60).round();
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

// ── Period presets ──────────────────────────────────────────────────────────

/// Quick date ranges offered above a report's results.
enum ReportPeriod {
  today('Today'),
  yesterday('Yesterday'),
  last7Days('Last 7 days'),
  thisMonth('This month'),
  lastMonth('Last month'),
  last30Days('Last 30 days');

  const ReportPeriod(this.label);

  final String label;

  /// Inclusive `(from, to)` dates for this preset relative to [now].
  (DateTime, DateTime) rangeFor(DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    return switch (this) {
      ReportPeriod.today => (day, day),
      yesterday => (
        day.subtract(const Duration(days: 1)),
        day.subtract(const Duration(days: 1)),
      ),
      last7Days => (day.subtract(const Duration(days: 6)), day),
      thisMonth => (DateTime(day.year, day.month), day),
      lastMonth => (
        DateTime(day.year, day.month - 1),
        DateTime(day.year, day.month, 0),
      ),
      last30Days => (day.subtract(const Duration(days: 29)), day),
    };
  }
}

final DateFormat kReportDate = DateFormat('yyyy-MM-dd');

/// The preset whose range is exactly `from`…`to`, if any — so the chip row
/// can show which one is active after a manual date edit.
ReportPeriod? matchingPeriod(
  List<ReportPeriod> options,
  String from,
  String to,
  DateTime today,
) {
  for (final option in options) {
    final (start, end) = option.rangeFor(today);
    if (kReportDate.format(start) == from && kReportDate.format(end) == to) {
      return option;
    }
  }
  return null;
}

/// `"1 Nov → 15 Nov 2026"`; a single day reads `"Sat 14 Nov 2026"`.
String periodLabel(String from, String to) {
  final start = DateTime.tryParse(from);
  final end = DateTime.tryParse(to);
  if (start == null || end == null) return '$from → $to';
  if (start == end) return DateFormat('EEE d MMM yyyy').format(start);
  final sameYear = start.year == end.year;
  return '${DateFormat(sameYear ? 'd MMM' : 'd MMM yyyy').format(start)} → '
      '${DateFormat('d MMM yyyy').format(end)}';
}
