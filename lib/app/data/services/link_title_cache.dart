/// Human titles for Link values whose `name` is an opaque ID — e.g. Employee
/// `HR-EMP-00007` → "Jawwad Bilgi" via its `employee_name` field.
///
/// Filters still send the ID; this only decides what the user reads. Titles
/// are remembered for the app session as options are listed or picked, and a
/// value set some other way (a default, a restored filter) is looked up once.
library;

import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';

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

class LinkTitleCache {
  LinkTitleCache._();

  static final Map<(FieldsScope, String, String), String> _titles = {};
  static final Map<(FieldsScope, String, String), Future<String?>> _inFlight =
      {};

  /// The remembered title for [name], or null when unknown or not distinct.
  static String? peek(
    String doctype,
    String name, {
    required FieldsScope? scope,
  }) => scope == null ? null : _titles[(scope, doctype, name)];

  static void remember(
    String doctype,
    Iterable<LinkOption> options, {
    required FieldsScope? scope,
  }) {
    if (scope == null) return;
    for (final option in options) {
      if (option.hasDistinctTitle) {
        _titles[(scope, doctype, option.name)] = option.title;
      }
    }
  }

  /// Looks [name]'s title up on the server once; concurrent callers share the
  /// request. Null when the record has no distinct title or the read fails.
  static Future<String?> resolve(
    String doctype,
    String titleField,
    String name,
    ApiProvider api, {
    required FieldsScope? scope,
  }) {
    if (scope == null) return Future.value(null);
    final known = peek(doctype, name, scope: scope);
    if (known != null) return Future.value(known);
    final key = (scope, doctype, name);
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
        remember(doctype, options, scope: scope);
        return peek(doctype, name, scope: scope);
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
