/// Human titles for Link values whose `name` is an opaque ID — e.g. Employee
/// `HR-EMP-00007` → "Jawwad Bilgi" via its `employee_name` field.
///
/// Filters still send the ID; this only decides what the user reads. Titles
/// are remembered for the app session as options are listed or picked, and a
/// value set some other way (a default, a restored filter) is looked up once.
library;

import 'package:multimax/app/data/providers/api_provider.dart';

/// One pickable Link value and its human title.
class LinkOption {
  const LinkOption({required this.name, required this.title});

  final String name;

  /// The title field's value; may be empty or equal to [name].
  final String title;

  bool get hasDistinctTitle => title.isNotEmpty && title != name;

  /// What a list or a field shows first.
  String get display => hasDistinctTitle ? title : name;
}

/// `[{name, <titleField>}]` rows → options; blank names are dropped.
List<LinkOption> parseLinkOptions(Object? rows, String titleField) => [
  if (rows is List)
    for (final row in rows)
      if (row is Map && (row['name']?.toString().trim() ?? '').isNotEmpty)
        LinkOption(
          name: row['name'].toString().trim(),
          title: row[titleField]?.toString().trim() ?? '',
        ),
];

/// `"Employee: Jawwad Bilgi"` when the title is known, else the ID.
String linkChipValue(String doctype, String name) =>
    LinkTitleCache.peek(doctype, name) ?? name;

class LinkTitleCache {
  LinkTitleCache._();

  static final Map<String, String> _titles = {};
  static final Map<String, Future<String?>> _inFlight = {};

  static String _key(String doctype, String name) => '$doctype\u0000$name';

  /// The remembered title for [name], or null when unknown or not distinct.
  static String? peek(String doctype, String name) =>
      _titles[_key(doctype, name)];

  static void remember(String doctype, Iterable<LinkOption> options) {
    for (final option in options) {
      if (option.hasDistinctTitle) {
        _titles[_key(doctype, option.name)] = option.title;
      }
    }
  }

  /// Looks [name]'s title up on the server once; concurrent callers share the
  /// request. Null when the record has no distinct title or the read fails.
  static Future<String?> resolve(
    String doctype,
    String titleField,
    String name,
    ApiProvider api,
  ) {
    final known = peek(doctype, name);
    if (known != null) return Future.value(known);
    final key = _key(doctype, name);
    return _inFlight[key] ??= () async {
      try {
        final response = await api.getDocumentList(
          doctype,
          fields: ['name', titleField],
          filters: {'name': name},
          limit: 1,
          orderBy: 'name asc',
        );
        final data = response.data is Map ? response.data['data'] : null;
        final options = parseLinkOptions(data, titleField);
        remember(doctype, options);
        return peek(doctype, name);
      } catch (_) {
        return null;
      } finally {
        _inFlight.remove(key);
      }
    }();
  }

  /// Test hook.
  static void clear() {
    _titles.clear();
    _inFlight.clear();
  }
}
