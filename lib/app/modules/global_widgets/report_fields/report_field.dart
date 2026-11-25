typedef FieldsScope = ({String site, String user});
typedef FieldsOwner = ({FieldsScope scope, String rawUser});
typedef FieldSection = ({String id, String title});
typedef DeskColumn = ({String fieldname, String label});
typedef Unsubscribe = void Function();
typedef EditFields = Map<String, bool>? Function(Map<String, bool> latest);

enum FieldsFailure { load, save }

class ReportField {
  const ReportField({
    required this.key,
    required this.column,
    required this.section,
    required this.defaultVisible,
    this.locked = false,
    this.requiresKey,
    this.hint,
    this.retainExplicitDefault = false,
  });

  final String key;
  final DeskColumn column;
  final String section;
  final bool defaultVisible;
  final bool locked;
  final String? requiresKey;
  final String? hint;
  final bool retainExplicitDefault;

  ReportField _withColumn(DeskColumn value) => ReportField(
    key: key,
    column: value,
    section: section,
    defaultVisible: defaultVisible,
    locked: locked,
    requiresKey: requiresKey,
    hint: hint,
    retainExplicitDefault: retainExplicitDefault,
  );
}

class ReportFieldsDefinition {
  const ReportFieldsDefinition({
    required this.id,
    required this.sections,
    required this.fields,
    required this.alwaysShown,
    List<ReportField> unlisted = const [],
  }) : _unlisted = unlisted;

  final String id;
  final String alwaysShown;
  final List<FieldSection> sections;
  final List<ReportField> fields;
  final List<ReportField> _unlisted;

  ReportField? field(String key) {
    for (final field in fields) {
      if (field.key == key) return field;
    }
    for (final field in _unlisted) {
      if (field.key == key) return field;
    }
    return null;
  }

  String? label(String key) {
    final label = field(key)?.column.label;
    return label == null || label.trim().isEmpty ? null : label;
  }

  ReportFieldsDefinition immutable() {
    assert(_valid());
    return ReportFieldsDefinition(
      id: id,
      sections: List.unmodifiable(sections),
      fields: List.unmodifiable(fields),
      alwaysShown: alwaysShown,
      unlisted: List.unmodifiable(_unlisted),
    );
  }

  /// Applies the site headers to known columns while retaining the rendering
  /// defaults and saved keys of details whose tiles are absent in this shape.
  ReportFieldsDefinition withColumns(
    List<DeskColumn>? columns, {
    Map<String, List<String>> aliases = const {},
  }) {
    if (columns == null) return immutable();
    final byName = {for (final column in columns) column.fieldname: column};
    final visible = <ReportField>[];
    final unlisted = <ReportField>[];
    for (final field in [...fields, ..._unlisted]) {
      final name = field.column.fieldname;
      DeskColumn? column = byName[name];
      for (final alias in aliases[name] ?? const <String>[]) {
        column ??= byName[alias];
      }
      if (column != null && column.label.trim().isNotEmpty) {
        visible.add(field._withColumn(column));
      } else if (field.locked && column == null) {
        visible.add(field);
      } else {
        unlisted.add(field);
      }
    }
    return ReportFieldsDefinition(
      id: id,
      sections: sections,
      fields: visible,
      alwaysShown: alwaysShown,
      unlisted: unlisted,
    ).immutable();
  }

  bool _valid() {
    final sectionIds = sections.map((section) => section.id).toSet();
    assert(sectionIds.length == sections.length, 'Duplicate field section');
    final all = [...fields, ..._unlisted];
    final byKey = {for (final field in all) field.key: field};
    assert(byKey.length == all.length, 'Duplicate report field key');
    for (final field in all) {
      assert(sectionIds.contains(field.section), 'Unknown field section');
      final visited = {field.key};
      var dependency = field.requiresKey;
      while (dependency != null) {
        assert(byKey.containsKey(dependency), 'Unknown field dependency');
        assert(visited.add(dependency), 'Cyclic field dependency');
        dependency = byKey[dependency]?.requiresKey;
      }
    }
    return true;
  }
}

typedef FieldsSnapshot = ({
  Map<String, bool> overrides,
  int revision,
  bool loaded,
  bool saving,
  FieldsFailure? failure,
});

const FieldsSnapshot emptyFieldsSnapshot = (
  overrides: <String, bool>{},
  revision: 0,
  loaded: false,
  saving: false,
  failure: null,
);

typedef FieldsState = ({
  ReportFieldsDefinition definition,
  FieldsSnapshot snapshot,
  bool binding,
  bool sessionOnly,
  bool resetting,
  bool retrying,
  Set<String> pendingKeys,
});

extension ReportFieldsSelection on FieldsState {
  bool selected(String key) {
    final field = definition.field(key);
    if (field?.locked ?? false) return true;
    return snapshot.overrides[key] ?? field?.defaultVisible ?? true;
  }

  bool shows(String key) {
    if (!selected(key)) return false;
    final dependency = definition.field(key)?.requiresKey;
    return dependency == null || shows(dependency);
  }

  bool canEdit(String key) {
    if (binding ||
        resetting ||
        retrying ||
        snapshot.failure == FieldsFailure.load ||
        (!sessionOnly && !snapshot.loaded) ||
        pendingKeys.contains(key)) {
      return false;
    }
    for (final field in definition.fields) {
      if (field.key != key) continue;
      final dependency = field.requiresKey;
      return !field.locked && (dependency == null || shows(dependency));
    }
    return false;
  }

  String? label(String key) => definition.label(key);
}

DeskColumn? decodeDeskColumn(Object? descriptor) {
  if (descriptor is Map) {
    final fieldname = descriptor['fieldname'];
    if (fieldname is! String || fieldname.trim().isEmpty) return null;
    final label = descriptor['label'];
    return (fieldname: fieldname, label: label is String ? label : '');
  }
  if (descriptor is! String || descriptor.trim().isEmpty) return null;
  final label = descriptor.split(':').first.trim();
  if (label.isEmpty) return null;
  // Older SQL-backed reports can return a dotted database column name
  // instead of a Frappe header descriptor.
  if (label.contains('`') || RegExp(r'^\w+\.\w+$').hasMatch(label)) {
    return (fieldname: label.split('.').last.replaceAll('`', ''), label: '');
  }
  // Frappe's legacy Label:FieldType/Options:Width syntax omits fieldname.
  final fieldname = label.toLowerCase().replaceAll(RegExp(r'[ -]'), '_');
  return (fieldname: fieldname, label: label);
}

List<DeskColumn> decodeDeskColumns(Object? columns) {
  if (columns is! List) return const [];
  return List.unmodifiable(
    columns.map(
      (column) => decodeDeskColumn(column) ?? (fieldname: '', label: ''),
    ),
  );
}

Map<String, dynamic>? decodeDeskRow(Object? row, List<DeskColumn> columns) {
  if (row is Map) {
    return {
      for (final entry in row.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  if (row is! List) return null;
  final mapped = <String, dynamic>{};
  for (var i = 0; i < columns.length && i < row.length; i++) {
    final name = columns[i].fieldname;
    if (name.isNotEmpty) mapped.putIfAbsent(name, () => row[i]);
  }
  return mapped;
}
