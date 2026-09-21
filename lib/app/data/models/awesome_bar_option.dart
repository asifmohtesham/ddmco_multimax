/// One row the Awesome Bar can show — a mirror of the option objects Frappe's
/// `awesome_bar.js` / `search_utils.js` build (`{type, label, value, index,
/// route, match, recent, …}`), minus the HTML.
///
/// Rendering: [label] is `labelPrefix + match + labelSuffix`; [matchIndices]
/// are positions inside [match] the fuzzy matcher hit, emphasised the way
/// Frappe wraps them in `<mark>`.
library;

/// Frappe's `type` strings, used by `set_specifics` (the last word of a
/// multi-word query narrows the options to a type whose name starts with
/// it: `delivery note list` → only "Delivery Note List").
enum AwesomeBarOptionType {
  /// "Search for *txt*" — opens the full document search.
  search('Search'),

  /// "Find *txt* in *current list*".
  current('Current'),

  /// "*expr* = *result*".
  calculator('Calculator'),

  /// "Help on Search".
  help('Help'),

  /// "New *DocType*".
  newDoc('New'),

  /// "Find *x* in *DocType*".
  inList('In List'),

  /// "*DocType* List".
  list('List'),

  /// "Report *name*".
  report('Report'),

  /// "Open *page*".
  page('Page'),

  /// A recently opened document or screen (no type in Frappe, so it never
  /// matches a `set_specifics` word).
  recent(''),

  /// A full-text hit from `frappe.utils.global_search.search`.
  document('');

  const AwesomeBarOptionType(this.typeName);

  /// Frappe's `type` string; empty when Frappe gives the option none.
  final String typeName;
}

class AwesomeBarOption {
  final AwesomeBarOptionType type;

  /// Text before the matched target, e.g. `"New "`.
  final String labelPrefix;

  /// The matched target text, e.g. `"Delivery Note"` — or the whole label
  /// when nothing is fuzzy-matched.
  final String match;

  /// Text after the matched target, e.g. `" List"`.
  final String labelSuffix;

  /// Character positions inside [match] the fuzzy matcher hit.
  final List<int> matchIndices;

  /// Frappe's `value` — the plain text of the option.
  final String value;

  /// Frappe's `index` — sort key, higher first.
  final double index;

  /// Route to open, or `null` for options with an `onclick`-style action
  /// (search, current, calculator, help).
  final String? route;

  /// Navigation arguments for [route].
  final Map<String, dynamic>? arguments;

  /// Key options are deduplicated on (Frappe joins the route parts). `null`
  /// = never deduplicated.
  final String? dedupeKey;

  /// Frappe's `recent` flag: a recent never displaces an existing option.
  final bool recent;

  /// Secondary line (global results: the matched fields).
  final String? description;

  /// DocType this option belongs to (grouping / icons), when it has one.
  final String? doctype;

  /// Document name for form-opening options.
  final String? docname;

  /// Extra text the action needs: the query for [AwesomeBarOptionType.search]
  /// / [AwesomeBarOptionType.current], the result for
  /// [AwesomeBarOptionType.calculator].
  final String? payload;

  const AwesomeBarOption({
    required this.type,
    required this.match,
    required this.value,
    required this.index,
    this.labelPrefix = '',
    this.labelSuffix = '',
    this.matchIndices = const [],
    this.route,
    this.arguments,
    this.dedupeKey,
    this.recent = false,
    this.description,
    this.doctype,
    this.docname,
    this.payload,
  });

  /// The full display text.
  String get label => '$labelPrefix$match$labelSuffix';

  AwesomeBarOption copyWith({double? index, bool? recent}) => AwesomeBarOption(
        type: type,
        match: match,
        value: value,
        index: index ?? this.index,
        labelPrefix: labelPrefix,
        labelSuffix: labelSuffix,
        matchIndices: matchIndices,
        route: route,
        arguments: arguments,
        dedupeKey: dedupeKey,
        recent: recent ?? this.recent,
        description: description,
        doctype: doctype,
        docname: docname,
        payload: payload,
      );

  @override
  String toString() => 'AwesomeBarOption(${type.name}, "$label", $index)';
}

/// A full-text hit from `frappe.utils.global_search.search`.
class GlobalSearchHit {
  final String doctype;
  final String name;

  /// `"Label : value ||| Label : value …"`.
  final String content;
  final double rank;
  final String? image;

  const GlobalSearchHit({
    required this.doctype,
    required this.name,
    required this.content,
    this.rank = 0,
    this.image,
  });
}

/// A recently opened document or screen, persisted per user.
class AwesomeBarRecent {
  /// `form` | `list` | `report` | `page`.
  final String kind;

  /// DocType (form / list), report name, or page title.
  final String name;

  /// Document name for `form` entries, else empty.
  final String docname;

  /// Route to reopen a `list` / `report` / `page` entry (forms resolve
  /// their route through the search-target registry).
  final String route;

  const AwesomeBarRecent({
    required this.kind,
    required this.name,
    this.docname = '',
    this.route = '',
  });

  /// Identity for dedupe and visit counting.
  String get key => '$kind:$name:$docname';

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'name': name,
        'docname': docname,
        'route': route,
      };

  static AwesomeBarRecent? fromJson(dynamic json) {
    if (json is! Map) return null;
    final kind = json['kind'];
    final name = json['name'];
    if (kind is! String || name is! String || name.isEmpty) return null;
    return AwesomeBarRecent(
      kind: kind,
      name: name,
      docname: (json['docname'] ?? '').toString(),
      route: (json['route'] ?? '').toString(),
    );
  }
}
