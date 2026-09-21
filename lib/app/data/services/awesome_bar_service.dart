import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/awesome_bar_option.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/global_search_service.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/utils/awesome_bar_query.dart';
import 'package:multimax/app/data/utils/fuzzy_match.dart';
import 'package:multimax/app/data/utils/safe_calculator.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/workspace_menu.dart';

/// Permission lookup: `null` while loading, `true` / `false` once known.
typedef AwesomeBarCanAccess = bool? Function(String doctype, String permType);

/// A DocType the Awesome Bar can list, search in, or create — Frappe's
/// `boot.user.can_read` ∩ `can_search` entry, resolved to app screens.
class AwesomeBarDoctype {
  final String doctype;
  final String label;
  final String listRoute;

  /// Whether the list screen consumes [kAwesomeBarQueryArg] — Frappe's
  /// `can_search`. `false` lists open without a query.
  final bool canSearch;

  const AwesomeBarDoctype({
    required this.doctype,
    required this.label,
    required this.listRoute,
    this.canSearch = true,
  });
}

/// A report screen — Frappe's `boot.user.all_reports` entry.
class AwesomeBarReport {
  final String name;
  final String label;
  final String route;

  /// DocType whose `report` permission gates the screen.
  final String guardDoctype;

  const AwesomeBarReport({
    required this.name,
    required this.label,
    required this.route,
    required this.guardDoctype,
  });
}

/// A non-DocType screen — Frappe's `boot.page_info` entry.
class AwesomeBarPage {
  final String title;
  final String route;
  const AwesomeBarPage({required this.title, required this.route});
}

/// Everything the option builders read. Built once from the app's
/// registries by [AwesomeBarRegistry.fromApp]; hand-rolled in tests.
class AwesomeBarRegistry {
  final List<AwesomeBarDoctype> doctypes;
  final List<AwesomeBarReport> reports;
  final List<AwesomeBarPage> pages;

  /// Form targets, for "New *DocType*" ([GlobalSearchTarget.newArgs]) and
  /// for opening recents / global results ([GlobalSearchTarget.argsFor]).
  final List<GlobalSearchTarget> targets;

  const AwesomeBarRegistry({
    required this.doctypes,
    required this.reports,
    required this.pages,
    required this.targets,
  });

  /// The live app: every list screen in [kNavCatalog] plus ToDo, every
  /// report screen in [kNavCatalog], the settings pages, and
  /// [kGlobalSearchTargets].
  factory AwesomeBarRegistry.fromApp() {
    final doctypes = <AwesomeBarDoctype>[
      const AwesomeBarDoctype(
        doctype: 'ToDo',
        label: 'ToDo',
        listRoute: AppRoutes.TODO,
      ),
      for (final l in kNavCatalog)
        if (l.linkType == 'DocType')
          AwesomeBarDoctype(
            doctype: l.linkTo,
            label: l.linkTo,
            listRoute: l.route,
            canSearch: !_kListsWithoutSearch.contains(l.linkTo),
          ),
    ];
    final reports = <AwesomeBarReport>[
      for (final l in kNavCatalog)
        if (l.linkType == 'Report')
          AwesomeBarReport(
            name: l.linkTo,
            label: l.title,
            route: l.route,
            guardDoctype: l.guard.doctype,
          ),
    ];
    return AwesomeBarRegistry(
      doctypes: doctypes,
      reports: reports,
      pages: kAwesomeBarPages,
      targets: kGlobalSearchTargets,
    );
  }

  GlobalSearchTarget? targetFor(String doctype) {
    for (final t in targets) {
      if (t.doctype == doctype) return t;
    }
    return null;
  }

  AwesomeBarDoctype? doctypeFor(String doctype) {
    for (final d in doctypes) {
      if (d.doctype == doctype) return d;
    }
    return null;
  }
}

/// List screens with no local search box (no `searchQuery`), so a
/// "Find *x* in …" option opens them without a query.
const Set<String> _kListsWithoutSearch = {'Attendance', 'Purchase Receipt'};

/// The app's non-DocType screens, for "Open *page*".
const List<AwesomeBarPage> kAwesomeBarPages = [
  AwesomeBarPage(title: 'Profile', route: AppRoutes.PROFILE),
  AwesomeBarPage(title: 'User Area', route: AppRoutes.USER_AREA),
  AwesomeBarPage(title: 'Theme', route: AppRoutes.THEME),
  AwesomeBarPage(title: 'Session Defaults', route: AppRoutes.SESSION_DEFAULTS),
  AwesomeBarPage(
      title: 'Notification Settings', route: AppRoutes.NOTIFICATION_SETTINGS),
  AwesomeBarPage(title: 'About', route: AppRoutes.ABOUT),
];

/// Mirror of Frappe's `frappe.search.AwesomeBar` + `frappe.search.utils`.
///
/// Every builder is a pure static that takes the registry, the permission
/// lookup and the recents as parameters, so the unit tests need no GetX. The
/// instance API ([assemble], [globalResults], [recents]) wires them to the
/// live app.
class AwesomeBarService extends GetxService {
  AwesomeBarService({
    AwesomeBarRegistry? registry,
    GlobalSearchService? globalSearch,
    AwesomeBarRecentsStore? recents,
  })  : _registry = registry,
        _globalSearch = globalSearch,
        _recents = recents;

  final AwesomeBarRegistry? _registry;
  final GlobalSearchService? _globalSearch;
  final AwesomeBarRecentsStore? _recents;

  AwesomeBarRegistry get registry => _registry ?? AwesomeBarRegistry.fromApp();

  GlobalSearchService get _service =>
      _globalSearch ??
      (Get.isRegistered<GlobalSearchService>()
          ? Get.find<GlobalSearchService>()
          : Get.put(GlobalSearchService()));

  AwesomeBarRecentsStore get recents => _recents ?? AwesomeBarRecentsStore();

  /// [PermissionService.hasAccess] when registered; permissive otherwise.
  bool? _canAccess(String doctype, String permType) {
    if (!Get.isRegistered<PermissionService>()) return null;
    return Get.find<PermissionService>().hasAccess(doctype, permType: permType);
  }

  // ── Frappe's index constants ─────────────────────────────────────────────
  static const double kSearchIndex = 100;
  static const double kCurrentIndex = 90;
  static const double kCalculatorIndex = 80;
  static const double kRecentIndex = 80;
  static const double kHelpIndex = -10;

  /// Frappe's `input` handler: the whole option list for [rawText], nav
  /// options only (global results are appended by the caller once they
  /// arrive — see [appendGlobalResults]). Deduplicated and sorted by
  /// `index` descending, "Help on Search" included.
  List<AwesomeBarOption> assemble(
    String rawText, {
    String? currentDoctype,
  }) =>
      assembleOptions(
        rawText,
        registry: registry,
        canAccess: _canAccess,
        recents: recents.list(),
        visits: recents.visits(),
        currentDoctype: currentDoctype,
      );

  /// Frappe's `get_global_results`: full-text hits for [text], as document
  /// options the bar can open. Empty on any endpoint failure.
  Future<List<AwesomeBarOption>> globalResults(String text,
      {int limit = 10}) async {
    List<GlobalSearchHit> hits;
    try {
      hits = await _service.globalSearch(text, limit: limit);
    } catch (e) {
      if (kDebugMode) print('AwesomeBarService: global search failed: $e');
      return const [];
    }
    return documentOptions(hits, text, registry);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Pure builders
  // ═══════════════════════════════════════════════════════════════════════

  /// Frappe's `txt = value.trim().replace(/\s\s+/g, " ")`.
  static String normalise(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s\s+'), ' ');

  /// The `input` handler. Pure.
  static List<AwesomeBarOption> assembleOptions(
    String rawText, {
    required AwesomeBarRegistry registry,
    required AwesomeBarCanAccess canAccess,
    List<AwesomeBarRecent> recents = const [],
    Map<String, int> visits = const {},
    String? currentDoctype,
  }) {
    final txt = normalise(rawText);
    var options = <AwesomeBarOption>[];
    if (txt.length > 1) {
      final lastSpace = txt.lastIndexOf(' ');
      if (lastSpace != -1) {
        options.addAll(setSpecifics(
          txt.substring(0, lastSpace),
          txt.substring(lastSpace + 1),
          registry: registry,
          canAccess: canAccess,
          recents: recents,
        ));
      }
      options.addAll(addDefaults(txt,
          registry: registry, currentDoctype: currentDoctype));
      options.addAll(buildOptions(txt,
          registry: registry, canAccess: canAccess, recents: recents));
    } else {
      options.addAll(deduplicate(getRecentPages(txt, recents, registry)));
      options.addAll(getFrequentLinks(visits, recents, registry));
    }
    options.add(helpOption());
    options = deduplicate(options);
    return sortByIndex(options);
  }

  /// Frappe's `set_specifics`: options for [txt] narrowed to the type whose
  /// name starts with [endTxt].
  static List<AwesomeBarOption> setSpecifics(
    String txt,
    String endTxt, {
    required AwesomeBarRegistry registry,
    required AwesomeBarCanAccess canAccess,
    List<AwesomeBarRecent> recents = const [],
  }) {
    final results = buildOptions(txt,
        registry: registry, canAccess: canAccess, recents: recents);
    final end = endTxt.toLowerCase();
    return [
      for (final r in results)
        if (r.type.typeName.isNotEmpty &&
            r.type.typeName.toLowerCase().startsWith(end))
          r,
    ];
  }

  /// Frappe's `add_defaults`: "Search for", "Find in current", calculator.
  static List<AwesomeBarOption> addDefaults(
    String txt, {
    required AwesomeBarRegistry registry,
    String? currentDoctype,
  }) {
    final out = <AwesomeBarOption>[];
    out.add(makeGlobalSearch(txt));
    final current = makeSearchInCurrent(txt, currentDoctype, registry);
    if (current != null) out.add(current);
    final calc = makeCalculator(txt);
    if (calc != null) out.add(calc);
    return out;
  }

  /// "Search for *txt*", index 100.
  static AwesomeBarOption makeGlobalSearch(String txt) => AwesomeBarOption(
        type: AwesomeBarOptionType.search,
        labelPrefix: 'Search for ',
        match: txt,
        value: 'Search for $txt',
        index: kSearchIndex,
        payload: txt,
      );

  /// "Find *txt* in *current list*", index 90 — only from a list screen and
  /// when the text has no ` in` (Frappe's `make_search_in_current`).
  static AwesomeBarOption? makeSearchInCurrent(
    String txt,
    String? currentDoctype,
    AwesomeBarRegistry registry,
  ) {
    if (currentDoctype == null || txt.contains(' in')) return null;
    final d = registry.doctypeFor(currentDoctype);
    if (d == null) return null;
    return AwesomeBarOption(
      type: AwesomeBarOptionType.current,
      labelPrefix: 'Find ',
      match: txt,
      labelSuffix: ' in ${d.label}',
      value: 'Find $txt in ${d.label}',
      index: kCurrentIndex,
      doctype: d.doctype,
      route: d.listRoute,
      arguments: {kAwesomeBarQueryArg: txt},
      payload: txt,
    );
  }

  /// "*expr* = *result*", index 80, when [txt] starts with a digit, `(` or
  /// `=` and evaluates safely.
  static AwesomeBarOption? makeCalculator(String txt) {
    if (!looksLikeCalculation(txt)) return null;
    final v = evaluateExpression(txt);
    if (v == null) return null;
    final expr = txt.startsWith('=') ? txt.substring(1) : txt;
    final result = formatCalculatorResult(v);
    return AwesomeBarOption(
      type: AwesomeBarOptionType.calculator,
      labelPrefix: '$expr = ',
      match: result,
      value: '$expr = $result',
      index: kCalculatorIndex,
      payload: result,
    );
  }

  /// "Help on Search", index −10.
  static AwesomeBarOption helpOption() => const AwesomeBarOption(
        type: AwesomeBarOptionType.help,
        match: 'Help on Search',
        value: 'Help on Search',
        index: kHelpIndex,
      );

  /// Frappe's `build_options`: creatables, search-in-list, doctypes,
  /// reports, pages, recents — deduplicated, sorted by index descending.
  static List<AwesomeBarOption> buildOptions(
    String txt, {
    required AwesomeBarRegistry registry,
    required AwesomeBarCanAccess canAccess,
    List<AwesomeBarRecent> recents = const [],
  }) {
    final options = <AwesomeBarOption>[
      ...getCreatables(txt, registry, canAccess),
      ...getSearchInList(txt, registry, canAccess),
      ...getDoctypes(txt, registry, canAccess),
      ...getReports(txt, registry, canAccess),
      ...getPages(txt, registry),
      ...getRecentPages(txt, recents, registry),
    ];
    return sortByIndex(deduplicate(options));
  }

  /// A target is kept unless access is explicitly denied — the same
  /// permissive-while-loading rule as
  /// [GlobalSearchService.filterPermittedTargets].
  static bool _allowed(AwesomeBarCanAccess canAccess, String doctype,
          String permType) =>
      canAccess(doctype, permType) != false;

  /// `get_creatables`: when the first word is `new`, fuzzy-match the rest
  /// against every creatable doctype → "New *DocType*", index `1 + score`.
  static List<AwesomeBarOption> getCreatables(
    String keywords,
    AwesomeBarRegistry registry,
    AwesomeBarCanAccess canAccess,
  ) {
    final out = <AwesomeBarOption>[];
    final first = keywords.split(' ').first;
    if (first.toLowerCase() != 'new') return out;
    final rest = keywords.length > 4 ? keywords.substring(4) : '';
    for (final t in registry.targets) {
      if (!t.canCreate) continue;
      if (!_allowed(canAccess, t.doctype, 'create')) continue;
      final r = fuzzySearch(rest, t.doctype);
      if (r.score == 0) continue;
      out.add(_newOption(t, r, 1 + r.score.toDouble()));
    }
    return out;
  }

  static AwesomeBarOption _newOption(
    GlobalSearchTarget t,
    FuzzyMatchResult r,
    double index,
  ) =>
      AwesomeBarOption(
        type: AwesomeBarOptionType.newDoc,
        labelPrefix: 'New ',
        match: t.doctype,
        matchIndices: r.matches,
        value: 'New ${t.doctype}',
        index: index,
        doctype: t.doctype,
        route: t.createRoute,
        arguments: Map<String, dynamic>.of(t.newArgs!),
        dedupeKey: 'new:${t.doctype}',
      );

  /// `get_search_in_list`: `x in y` → "Find *x* in *DocType*", index
  /// `1 + score`, when the text contains ` in ` and does not end in `in`.
  static List<AwesomeBarOption> getSearchInList(
    String keywords,
    AwesomeBarRegistry registry,
    AwesomeBarCanAccess canAccess,
  ) {
    final out = <AwesomeBarOption>[];
    final words = keywords.split(' ');
    if (!words.contains('in') || keywords.endsWith('in')) return out;
    final parts = keywords.split(' in ');
    if (parts.length < 2) return out;
    final needle = parts[0];
    final target = parts[1];
    for (final d in registry.doctypes) {
      if (!_allowed(canAccess, d.doctype, 'read')) continue;
      final r = fuzzySearch(target, d.doctype);
      if (r.score == 0) continue;
      out.add(AwesomeBarOption(
        type: AwesomeBarOptionType.inList,
        labelPrefix: 'Find $needle in ',
        match: d.doctype,
        matchIndices: r.matches,
        value: 'Find $needle in ${d.doctype}',
        index: 1 + r.score.toDouble(),
        doctype: d.doctype,
        route: d.listRoute,
        arguments: d.canSearch ? {kAwesomeBarQueryArg: needle} : null,
        dedupeKey: 'list:${d.doctype}',
        payload: needle,
      ));
    }
    return out;
  }

  /// `get_doctypes`: fuzzy-match against every readable doctype → "*DocType*
  /// List" (`score + 0.05`) and, if creatable, "New *DocType*"
  /// (`score + 0.015`). Frappe drops the word "List" when the doctype name
  /// already ends in it. The Report view has no app equivalent.
  static List<AwesomeBarOption> getDoctypes(
    String keywords,
    AwesomeBarRegistry registry,
    AwesomeBarCanAccess canAccess,
  ) {
    final out = <AwesomeBarOption>[];
    for (final d in registry.doctypes) {
      if (!_allowed(canAccess, d.doctype, 'read')) continue;
      final r = fuzzySearch(keywords, d.doctype);
      if (r.score == 0) continue;
      final target = registry.targetFor(d.doctype);
      if (target != null &&
          target.canCreate &&
          _allowed(canAccess, d.doctype, 'create')) {
        out.add(_newOption(target, r, r.score + 0.015));
      }
      final skipList = d.doctype.endsWith('List');
      out.add(AwesomeBarOption(
        type: AwesomeBarOptionType.list,
        match: d.doctype,
        matchIndices: r.matches,
        labelSuffix: skipList ? '' : ' List',
        value: '${d.doctype} List',
        index: r.score + 0.05,
        doctype: d.doctype,
        route: d.listRoute,
        dedupeKey: 'list:${d.doctype}',
      ));
    }
    return out;
  }

  /// `get_reports`: "Report *name*", index `score`.
  static List<AwesomeBarOption> getReports(
    String keywords,
    AwesomeBarRegistry registry,
    AwesomeBarCanAccess canAccess,
  ) {
    final out = <AwesomeBarOption>[];
    for (final rep in registry.reports) {
      if (!_allowed(canAccess, rep.guardDoctype, 'report')) continue;
      final r = fuzzySearch(keywords, rep.name);
      if (r.score <= 0) continue;
      out.add(AwesomeBarOption(
        type: AwesomeBarOptionType.report,
        labelPrefix: 'Report ',
        match: rep.name,
        matchIndices: r.matches,
        value: 'Report ${rep.name}',
        index: r.score.toDouble(),
        route: rep.route,
        dedupeKey: 'report:${rep.name}',
      ));
    }
    return out;
  }

  /// `get_pages`: "Open *page*", index `score`.
  static List<AwesomeBarOption> getPages(
    String keywords,
    AwesomeBarRegistry registry,
  ) {
    final out = <AwesomeBarOption>[];
    for (final p in registry.pages) {
      final r = fuzzySearch(keywords, p.title);
      if (r.score == 0) continue;
      out.add(AwesomeBarOption(
        type: AwesomeBarOptionType.page,
        labelPrefix: 'Open ',
        match: p.title,
        matchIndices: r.matches,
        value: 'Open ${p.title}',
        index: r.score.toDouble(),
        route: p.route,
        dedupeKey: 'page:${p.route}',
      ));
    }
    return out;
  }

  /// `get_recent_pages`: recents whose label contains [keywords] (case
  /// insensitive, `-` read as a space), index 80, `recent: true`. Empty
  /// [keywords] matches everything. Newest first.
  static List<AwesomeBarOption> getRecentPages(
    String keywords,
    List<AwesomeBarRecent> recents,
    AwesomeBarRegistry registry,
  ) {
    final needle = keywords.toLowerCase().replaceAll('-', ' ');
    final out = <AwesomeBarOption>[];
    for (final rec in recents) {
      final option = recentOption(rec, registry);
      if (option == null) continue;
      final hay = option.value.toLowerCase().replaceAll('-', ' ');
      if (needle.isEmpty || hay == needle || hay.contains(needle)) {
        out.add(option);
      }
    }
    return out;
  }

  /// `get_frequent_links`: the most visited screens, index = visit count;
  /// falls back to all recents when nothing has been counted.
  static List<AwesomeBarOption> getFrequentLinks(
    Map<String, int> visits,
    List<AwesomeBarRecent> recents,
    AwesomeBarRegistry registry, {
    int limit = 5,
  }) {
    if (visits.isEmpty) return getRecentPages('', recents, registry);
    final ranked = visits.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final out = <AwesomeBarOption>[];
    for (final e in ranked) {
      final rec = AwesomeBarRecentsStore.decodeKey(e.key, recents);
      if (rec == null) continue;
      final option = recentOption(rec, registry);
      if (option == null) continue;
      out.add(option.copyWith(index: e.value.toDouble(), recent: false));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// The option a recent opens as, or `null` when the app can no longer
  /// route it (a doctype removed from the registry).
  static AwesomeBarOption? recentOption(
    AwesomeBarRecent rec,
    AwesomeBarRegistry registry,
  ) {
    switch (rec.kind) {
      case 'form':
        final t = registry.targetFor(rec.name);
        if (t == null || rec.docname.isEmpty) return null;
        return AwesomeBarOption(
          type: AwesomeBarOptionType.recent,
          labelPrefix: '${rec.name} ',
          match: rec.docname,
          value: '${rec.name} ${rec.docname}',
          index: kRecentIndex,
          route: t.route,
          arguments: t.argsFor(rec.docname),
          dedupeKey: 'form:${rec.name}/${rec.docname}',
          doctype: rec.name,
          docname: rec.docname,
          recent: true,
        );
      case 'list':
        final d = registry.doctypeFor(rec.name);
        if (d == null) return null;
        return AwesomeBarOption(
          type: AwesomeBarOptionType.recent,
          match: d.doctype,
          labelSuffix: ' List',
          value: '${d.doctype} List',
          index: kRecentIndex,
          route: d.listRoute,
          dedupeKey: 'list:${d.doctype}',
          doctype: d.doctype,
          recent: true,
        );
      case 'report':
        AwesomeBarReport? rep;
        for (final r in registry.reports) {
          if (r.name == rec.name) rep = r;
        }
        if (rep == null) return null;
        return AwesomeBarOption(
          type: AwesomeBarOptionType.recent,
          match: rep.name,
          labelSuffix: ' Report',
          value: '${rep.name} Report',
          index: kRecentIndex,
          route: rep.route,
          dedupeKey: 'report:${rep.name}',
          recent: true,
        );
      case 'page':
        AwesomeBarPage? page;
        for (final p in registry.pages) {
          if (p.title == rec.name) page = p;
        }
        if (page == null) return null;
        return AwesomeBarOption(
          type: AwesomeBarOptionType.recent,
          match: page.title,
          value: page.title,
          index: kRecentIndex,
          route: page.route,
          dedupeKey: 'page:${page.route}',
          recent: true,
        );
    }
    return null;
  }

  /// Frappe's `deduplicate`: one option per route key. A later duplicate
  /// replaces the earlier one only when its index is higher AND it is not a
  /// recent. Options without a key are always kept.
  static List<AwesomeBarOption> deduplicate(List<AwesomeBarOption> options) {
    final out = <AwesomeBarOption>[];
    final keys = <String?>[];
    for (final option in options) {
      final key = option.dedupeKey;
      if (key == null) {
        out.add(option);
        keys.add(null);
        continue;
      }
      final old = keys.indexOf(key);
      if (old == -1) {
        out.add(option);
        keys.add(key);
      } else if (out[old].index < option.index && !option.recent) {
        out[old] = option;
      }
    }
    return out;
  }

  /// Stable sort by index descending.
  static List<AwesomeBarOption> sortByIndex(List<AwesomeBarOption> options) {
    final indexed = options.asMap().entries.toList();
    indexed.sort((a, b) {
      final c = b.value.index.compareTo(a.value.index);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
    return [for (final e in indexed) e.value];
  }

  /// Frappe's `input` tail: nav [options] + [globalResults], deduplicated.
  static List<AwesomeBarOption> appendGlobalResults(
    List<AwesomeBarOption> options,
    List<AwesomeBarOption> globalResults,
  ) =>
      deduplicate([...options, ...globalResults]);

  // ── Global results ───────────────────────────────────────────────────────

  /// `get_global_results` → one document option per routable hit, in
  /// server order (Frappe sorts by Global Search Settings priority), with
  /// the matched fields as [AwesomeBarOption.description].
  static List<AwesomeBarOption> documentOptions(
    List<GlobalSearchHit> hits,
    String keywords,
    AwesomeBarRegistry registry,
  ) {
    final out = <AwesomeBarOption>[];
    for (final h in hits) {
      final t = registry.targetFor(h.doctype);
      if (t == null) continue; // the app cannot open it
      out.add(AwesomeBarOption(
        type: AwesomeBarOptionType.document,
        match: h.name,
        value: h.name,
        index: 0,
        route: t.route,
        arguments: t.argsFor(h.name),
        dedupeKey: 'form:${h.doctype}/${h.name}',
        doctype: h.doctype,
        docname: h.name,
        description: makeDescription(h.content, keywords, h.name),
      ));
    }
    return out;
  }

  /// Frappe's `make_description`: the fields of [content] whose value
  /// contains [keywords], each trimmed to [fieldLength] chars around the
  /// first match, the whole capped at [resultMaxLength], joined with `, `.
  /// The document name is never repeated as a field. Pure.
  static String makeDescription(
    String content,
    String keywords,
    String docName, {
    int resultMaxLength = 300,
    int fieldLength = 120,
  }) {
    final parts = content.split(' ||| ');
    final fields = <String>[];
    var currentLength = 0;
    final needle = keywords.toLowerCase();
    for (final part in parts) {
      if (!part.toLowerCase().contains(needle)) continue;
      int colonIndex;
      String fieldValue;
      if (part.contains(' &&& ')) {
        colonIndex = part.indexOf(' &&& ');
        fieldValue = part.substring(colonIndex + 5);
      } else {
        colonIndex = part.indexOf(' : ');
        if (colonIndex == -1) {
          colonIndex = 0;
          fieldValue = part;
        } else {
          fieldValue = part.substring(colonIndex + 3);
        }
      }
      if (fieldValue.length > fieldLength) {
        var index = fieldValue.toLowerCase().indexOf(needle);
        if (index < 0) index = 0;
        final half = fieldLength ~/ 2;
        final buf = StringBuffer();
        if (index < half) {
          buf.write(fieldValue.substring(0, index));
        } else {
          buf.write('...');
          buf.write(fieldValue.substring(index - half, index));
        }
        final endOfMatch =
            index + half < fieldValue.length ? index + half : fieldValue.length;
        buf.write(fieldValue.substring(index, endOfMatch));
        if (index + half < fieldValue.length) buf.write('...');
        fieldValue = buf.toString();
      }
      final fieldName = part.substring(0, colonIndex);
      final remaining = resultMaxLength - currentLength;
      currentLength += fieldName.length + fieldValue.length + 2;
      if (currentLength < resultMaxLength) {
        final text = fieldName.isEmpty ? fieldValue : '$fieldName: $fieldValue';
        if (!fields.contains(text) && docName != fieldValue) fields.add(text);
      } else {
        if (fieldName.length < remaining) {
          var room = remaining - fieldName.length;
          if (room > fieldValue.length) room = fieldValue.length;
          var v = fieldValue.substring(0, room);
          final lastSpace = v.lastIndexOf(' ');
          v = (lastSpace > 0 ? v.substring(0, lastSpace) : v);
          fields.add('$fieldName: $v ...');
        } else {
          fields.add('...');
        }
        break;
      }
    }
    return fields.join(', ');
  }
}

/// Per-user recents + visit counts behind the Awesome Bar, persisted through
/// [StorageService]. Frappe keeps `boot.user.recent` and
/// `frequently_visited_links`; the app records both from
/// `GetMaterialApp.routingCallback` (see [recordRoute]).
class AwesomeBarRecentsStore {
  AwesomeBarRecentsStore({StorageService? storage, String? Function()? user})
      : _storage = storage,
        _user = user;

  final StorageService? _storage;
  final String? Function()? _user;

  static const int kMaxRecents = 20;
  static const int kMaxVisitKeys = 200;

  StorageService? get _box {
    if (_storage != null) return _storage;
    return Get.isRegistered<StorageService>()
        ? Get.find<StorageService>()
        : null;
  }

  String? get _currentUser {
    if (_user != null) return _user();
    if (!Get.isRegistered<AuthenticationController>()) return null;
    return Get.find<AuthenticationController>().currentUser.value?.email;
  }

  List<AwesomeBarRecent> list([String? user]) {
    final u = user ?? _currentUser;
    final box = _box;
    if (u == null || box == null) return const [];
    return decodeRecents(box.getAwesomeBarRecents(u));
  }

  Map<String, int> visits([String? user]) {
    final u = user ?? _currentUser;
    final box = _box;
    if (u == null || box == null) return const {};
    return decodeVisits(box.getAwesomeBarVisits(u));
  }

  /// Records [rec] for [user] (default: the signed-in user): newest first,
  /// deduplicated, capped at [kMaxRecents]; bumps its visit count.
  Future<void> record(AwesomeBarRecent rec, [String? user]) async {
    final u = user ?? _currentUser;
    final box = _box;
    if (u == null || box == null) return;
    final next = push(list(u), rec);
    await box.saveAwesomeBarRecents(u, [for (final r in next) r.toJson()]);
    final counts = bump(visits(u), rec.key);
    await box.saveAwesomeBarVisits(u, counts);
  }

  /// Forgets everything for [user].
  Future<void> clear(String user) async {
    final box = _box;
    if (box == null) return;
    await box.clearAwesomeBar(user);
  }

  /// Resolves a navigation ([route], [args]) to the recent it should record,
  /// or `null` when it is not a document, list, report or page the bar can
  /// reopen (Home, dialogs, a form in `new` mode…). Pure.
  static AwesomeBarRecent? recentForRoute(
    String route,
    dynamic args,
    AwesomeBarRegistry registry,
  ) {
    if (route.isEmpty) return null;
    for (final t in registry.targets) {
      if (t.route != route) continue;
      if (args is! Map) return null;
      final mode = args['mode'];
      if (mode == 'new') return null;
      final docname = (args['name'] ?? args['itemCode'] ?? '').toString();
      if (docname.isEmpty) return null;
      return AwesomeBarRecent(
          kind: 'form', name: t.doctype, docname: docname, route: route);
    }
    for (final d in registry.doctypes) {
      if (d.listRoute == route) {
        return AwesomeBarRecent(kind: 'list', name: d.doctype, route: route);
      }
    }
    for (final r in registry.reports) {
      if (r.route == route) {
        return AwesomeBarRecent(kind: 'report', name: r.name, route: route);
      }
    }
    for (final p in registry.pages) {
      if (p.route == route) {
        return AwesomeBarRecent(kind: 'page', name: p.title, route: route);
      }
    }
    return null;
  }

  /// `routingCallback` hook: records the screen [route] just opened.
  Future<void> recordRoute(String route, dynamic args,
      {AwesomeBarRegistry? registry}) async {
    final rec =
        recentForRoute(route, args, registry ?? AwesomeBarRegistry.fromApp());
    if (rec == null) return;
    await record(rec);
  }

  /// [rec] moved to the front of [current], duplicates removed, capped. Pure.
  static List<AwesomeBarRecent> push(
    List<AwesomeBarRecent> current,
    AwesomeBarRecent rec, {
    int max = kMaxRecents,
  }) {
    final out = <AwesomeBarRecent>[rec];
    for (final r in current) {
      if (r.key == rec.key) continue;
      out.add(r);
      if (out.length >= max) break;
    }
    return out;
  }

  /// [counts] with [key] incremented; the least-visited keys are dropped
  /// past [max]. Pure.
  static Map<String, int> bump(
    Map<String, int> counts,
    String key, {
    int max = kMaxVisitKeys,
  }) {
    final out = Map<String, int>.of(counts);
    out[key] = (out[key] ?? 0) + 1;
    if (out.length > max) {
      final ranked = out.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return {for (final e in ranked.take(max)) e.key: e.value};
    }
    return out;
  }

  static List<AwesomeBarRecent> decodeRecents(List<dynamic>? raw) {
    if (raw == null) return const [];
    final out = <AwesomeBarRecent>[];
    for (final e in raw) {
      final r = AwesomeBarRecent.fromJson(e);
      if (r != null) out.add(r);
    }
    return out;
  }

  static Map<String, int> decodeVisits(Map<dynamic, dynamic>? raw) {
    if (raw == null) return const {};
    final out = <String, int>{};
    raw.forEach((k, v) {
      final n = v is int ? v : int.tryParse(v.toString());
      if (k is String && n != null) out[k] = n;
    });
    return out;
  }

  /// Rebuilds the recent a visit-count [key] (`kind:name:docname`) stands
  /// for, preferring the stored recent (it carries the route). Pure.
  static AwesomeBarRecent? decodeKey(
    String key,
    List<AwesomeBarRecent> recents,
  ) {
    for (final r in recents) {
      if (r.key == key) return r;
    }
    final parts = key.split(':');
    if (parts.length < 2 || parts[1].isEmpty) return null;
    return AwesomeBarRecent(
      kind: parts[0],
      name: parts[1],
      docname: parts.length > 2 ? parts.sublist(2).join(':') : '',
    );
  }
}
