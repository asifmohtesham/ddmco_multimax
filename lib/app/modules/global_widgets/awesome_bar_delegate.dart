import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/awesome_bar_option.dart';
import 'package:multimax/app/data/services/awesome_bar_service.dart';
import 'package:multimax/app/modules/global_widgets/awesome_bar_help_sheet.dart';
import 'package:multimax/app/modules/global_widgets/global_document_search_delegate.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/search_highlight.dart';

/// Opens the full document search (the Dashboard fan-out) pre-filled with
/// [query]. [context] must outlive the Awesome Bar route (the Navigator's).
typedef OpenDocumentSearch = void Function(BuildContext context, String query);

/// One titled group of rows in the Awesome Bar list.
class AwesomeBarSection {
  final String? title;
  final List<AwesomeBarOption> options;
  const AwesomeBarSection(this.title, this.options);
}

/// The Frappe Awesome Bar as a [SearchDelegate].
///
/// Typing builds the nav options synchronously through
/// [AwesomeBarService.assemble] ("New …", "… List", "Report …", "Open …",
/// "Find x in …", recents, calculator, help) and, 100 ms after the last
/// keystroke, appends full-text hits from `frappe.utils.global_search.search`
/// under a "Documents" group. An empty field lists Recents and frequent
/// links, as Frappe does on focus.
///
/// "Search for *txt*" opens [GlobalDocumentSearchDelegate] with the query
/// pre-filled. Every other option navigates, then the field is cleared and
/// the bar dismissed. Escape closes the bar ([SearchDelegate] handles the
/// key itself).
///
/// ### Build-phase safety
/// [buildSuggestions] / [buildResults] never write an Rx synchronously —
/// the busy flag is only toggled from the debounce timer, never from a
/// build method (see the note atop `global_search_delegate.dart`).
class AwesomeBarDelegate extends SearchDelegate<void> {
  AwesomeBarDelegate({
    AwesomeBarService? service,
    this.currentDoctype,
    this.onFindInCurrent,
    Future<List<AwesomeBarOption>> Function(String text)? globalSearcher,
    OpenDocumentSearch? openDocumentSearch,
  })  : _providedService = service,
        _globalSearcher = globalSearcher,
        _openDocumentSearch = openDocumentSearch ?? _defaultOpenDocumentSearch;

  /// DocType of the list screen the bar was opened from, for
  /// "Find *txt* in *this list*". `null` from the Dashboard / drawer.
  final String? currentDoctype;

  /// Applies "Find *txt* in *this list*" in place when the bar was opened
  /// from a list screen. When `null`, the option navigates to the list.
  final ValueChanged<String>? onFindInCurrent;

  final AwesomeBarService? _providedService;
  final Future<List<AwesomeBarOption>> Function(String text)? _globalSearcher;
  final OpenDocumentSearch _openDocumentSearch;

  // Resolved lazily so constructing the delegate never needs DI to be warm
  // (the widget tests build the list with canned options).
  AwesomeBarService get _service =>
      _providedService ??
      (Get.isRegistered<AwesomeBarService>()
          ? Get.find<AwesomeBarService>()
          : Get.put(AwesomeBarService()));

  static void _defaultOpenDocumentSearch(BuildContext context, String query) {
    showSearch<void>(
      context: context,
      delegate: GlobalDocumentSearchDelegate(),
      query: query,
    );
  }

  /// `true` while a global-results request is in flight — drives the
  /// progress bar under the field.
  final RxBool busy = false.obs;
  int _inFlight = 0;

  final ScrollController _scroll = ScrollController();

  // ── Debounced global results (delegate instance persists) ───────────────
  static const Duration kDebounce = Duration(milliseconds: 100);
  Timer? _debounce;
  String? _pendingKey;
  Future<List<AwesomeBarOption>>? _pendingFuture;

  Future<List<AwesomeBarOption>> _globalResults(String txt) {
    if (txt == _pendingKey && _pendingFuture != null) return _pendingFuture!;
    _pendingKey = txt;
    _debounce?.cancel();
    final completer = Completer<List<AwesomeBarOption>>();
    _pendingFuture = completer.future;
    _debounce = Timer(kDebounce, () async {
      _inFlight++;
      busy.value = true;
      try {
        final r = await (_globalSearcher ?? _service.globalResults)(txt);
        if (!completer.isCompleted) completer.complete(r);
      } catch (e) {
        if (kDebugMode) print('AwesomeBarDelegate: global results failed: $e');
        if (!completer.isCompleted) completer.complete(const []);
      } finally {
        _inFlight--;
        busy.value = _inFlight > 0;
      }
    });
    return completer.future;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  // ── SearchDelegate surface ───────────────────────────────────────────────

  @override
  String? get searchFieldLabel => 'Search or type a command…';

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Clear search',
            onPressed: () {
              query = '';
              showSuggestions(context);
            },
          ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Close search',
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildBody(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildBody(context);

  Widget _buildBody(BuildContext context) {
    final txt = AwesomeBarService.normalise(query);
    final nav = _service.assemble(query, currentDoctype: currentDoctype);
    final scheme = context.scheme;
    final wantsGlobal = txt.length > 1;
    return Container(
      color: scheme.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildProgress(),
          Expanded(
            child: wantsGlobal
                ? FutureBuilder<List<AwesomeBarOption>>(
                    future: _globalResults(txt),
                    builder: (context, snapshot) {
                      final all = AwesomeBarService.appendGlobalResults(
                        nav,
                        snapshot.data ?? const [],
                      );
                      return buildOptionList(
                        context,
                        all,
                        onTap: (o) => select(context, o),
                      );
                    },
                  )
                : buildOptionList(
                    context,
                    nav,
                    onTap: (o) => select(context, o),
                  ),
          ),
        ],
      ),
    );
  }

  /// The 4 px progress strip under the field: a [LinearProgressIndicator]
  /// while [busy], else an empty box of the same height so the list never
  /// jumps. Its own [Obx] so the swap repaints.
  @visibleForTesting
  Widget buildProgress() => Obx(
        () => busy.value
            ? const LinearProgressIndicator(minHeight: 4)
            : const SizedBox(height: 4),
      );

  // ── Selection ────────────────────────────────────────────────────────────

  /// Acts on a tapped [option]: the search / calculator / help rows open
  /// their UI; everything else navigates, clears the field and dismisses.
  @visibleForTesting
  void select(BuildContext context, AwesomeBarOption option) {
    switch (option.type) {
      case AwesomeBarOptionType.search:
        // The Navigator's context outlives this route, unlike [context].
        final navContext = Navigator.of(context).context;
        final q = option.payload ?? query;
        query = '';
        close(context, null);
        _openDocumentSearch(navContext, q);
        return;
      case AwesomeBarOptionType.current:
        if (onFindInCurrent != null) {
          final q = option.payload ?? query;
          query = '';
          close(context, null);
          onFindInCurrent!(q);
          return;
        }
        break;
      case AwesomeBarOptionType.calculator:
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Result'),
            content: SelectableText(
              option.value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: ctx.scheme.text,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        return;
      case AwesomeBarOptionType.help:
        AwesomeBarHelpSheet.show(context);
        return;
      default:
        break;
    }
    final route = option.route;
    if (route == null) return;
    query = '';
    close(context, null);
    Get.toNamed(route, arguments: option.arguments);
  }

  // ── List rendering (service-free, widget-testable) ───────────────────────

  /// Groups a flat, index-sorted option list for display: the "Search for"
  /// / "Find in current" / calculator rows first, then Recents, Create a
  /// new…, Lists, Reports, Pages, Find "x" in…, Documents, then Help last.
  /// Empty sections are dropped. Pure.
  static List<AwesomeBarSection> groupForDisplay(
    List<AwesomeBarOption> options,
  ) {
    final top = <AwesomeBarOption>[];
    final help = <AwesomeBarOption>[];
    final byType = <AwesomeBarOptionType, List<AwesomeBarOption>>{};
    String? inListNeedle;
    for (final o in options) {
      switch (o.type) {
        case AwesomeBarOptionType.search:
        case AwesomeBarOptionType.current:
        case AwesomeBarOptionType.calculator:
          top.add(o);
        case AwesomeBarOptionType.help:
          help.add(o);
        default:
          byType.putIfAbsent(o.type, () => []).add(o);
          if (o.type == AwesomeBarOptionType.inList) inListNeedle ??= o.payload;
      }
    }
    final sections = <AwesomeBarSection>[];
    if (top.isNotEmpty) sections.add(AwesomeBarSection(null, top));
    void add(String title, AwesomeBarOptionType type) {
      final list = byType[type];
      if (list != null && list.isNotEmpty) {
        sections.add(AwesomeBarSection(title, list));
      }
    }

    add('Recents', AwesomeBarOptionType.recent);
    add('Create a new…', AwesomeBarOptionType.newDoc);
    add('Lists', AwesomeBarOptionType.list);
    add('Reports', AwesomeBarOptionType.report);
    add('Pages', AwesomeBarOptionType.page);
    add('Find "${inListNeedle ?? ''}" in…', AwesomeBarOptionType.inList);
    add('Documents', AwesomeBarOptionType.document);
    if (help.isNotEmpty) sections.add(AwesomeBarSection(null, help));
    return sections;
  }

  /// The scrollable option list. Service-free: takes the options and a tap
  /// callback so widget tests can drive it with canned data.
  @visibleForTesting
  Widget buildOptionList(
    BuildContext context,
    List<AwesomeBarOption> options, {
    required ValueChanged<AwesomeBarOption> onTap,
  }) {
    final scheme = context.scheme;
    final bottom = MediaQuery.of(context).padding.bottom;
    final children = <Widget>[];
    for (final section in groupForDisplay(options)) {
      if (section.title != null) {
        children.add(_sectionHeader(context, section.title!));
      }
      for (final o in section.options) {
        children.add(_row(context, o, onTap));
      }
    }
    if (children.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
        child: Column(
          children: [
            Icon(Icons.search, size: 40, color: scheme.textSubtle),
            const SizedBox(height: 8),
            Text(
              'Type to search documents, lists, reports and pages',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.textMuted),
            ),
          ],
        ),
      ));
    }
    children.add(ListEndFooter(
      hasMore: false,
      bottomPadding: bottom,
      label: 'End of list',
    ));
    return Container(
      color: scheme.bg,
      // Transparent Material so ListTile ink paints above the Container.
      child: Material(
        color: Colors.transparent,
        child: Scrollbar(
          controller: _scroll,
          child: ListView(
            controller: _scroll,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: scheme.textMuted,
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AwesomeBarOption o,
    ValueChanged<AwesomeBarOption> onTap,
  ) {
    final scheme = context.scheme;
    final target = o.doctype != null ? searchTargetForDoctype(o.doctype!) : null;
    final titleStyle = TextStyle(
      fontWeight: FontWeight.w600,
      color: scheme.text,
      fontSize: 15,
    );
    final subtitle = o.type == AwesomeBarOptionType.document
        ? [
            if (target != null) target.doctype else o.doctype,
            if (o.description != null && o.description!.isNotEmpty)
              o.description,
          ].whereType<String>().join(' · ')
        : null;
    return ListTile(
      key: ValueKey('awesome-bar:${o.type.name}:${o.value}'),
      leading: Icon(
        _iconFor(o, target),
        color: target?.color ?? scheme.textSubtle,
      ),
      title: MatchIndexHighlight(
        prefix: o.labelPrefix,
        text: o.match,
        suffix: o.labelSuffix,
        indices: o.matchIndices,
        style: titleStyle,
        maxLines: 1,
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.textMuted),
            ),
      trailing: o.type == AwesomeBarOptionType.search
          ? Icon(Icons.keyboard_return, size: 18, color: scheme.textSubtle)
          : null,
      onTap: () => onTap(o),
    );
  }

  static IconData _iconFor(AwesomeBarOption o, GlobalSearchTarget? target) {
    switch (o.type) {
      case AwesomeBarOptionType.search:
        return Icons.search;
      case AwesomeBarOptionType.current:
        return Icons.manage_search;
      case AwesomeBarOptionType.calculator:
        return Icons.calculate_outlined;
      case AwesomeBarOptionType.help:
        return Icons.help_outline;
      case AwesomeBarOptionType.newDoc:
        return Icons.add_circle_outline;
      case AwesomeBarOptionType.inList:
        return Icons.find_in_page_outlined;
      case AwesomeBarOptionType.list:
        return Icons.list_alt_outlined;
      case AwesomeBarOptionType.report:
        return Icons.summarize_outlined;
      case AwesomeBarOptionType.page:
        return Icons.open_in_new;
      case AwesomeBarOptionType.recent:
        return Icons.history;
      case AwesomeBarOptionType.document:
        return target?.icon ?? Icons.description_outlined;
    }
  }
}
