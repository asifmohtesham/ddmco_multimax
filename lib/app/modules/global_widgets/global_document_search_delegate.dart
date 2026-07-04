import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/global_search_service.dart';
import 'package:multimax/app/data/models/warehouse_stock_line.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/global_widgets/selectable_filter_chip.dart';
import 'package:multimax/app/modules/global_widgets/voice_search_sheet.dart';

/// Dashboard-wide search across every routed doctype.
///
/// Fans [GlobalSearchService.searchAll] out over the permitted targets and
/// renders the hits grouped by doctype. Tapping a hit opens that document's
/// form with the arguments the form expects ([GlobalSearchTarget.argsFor]).
///
/// Deliberately separate from [DocTypeSearchDelegate] (which 11 list screens
/// depend on) so this stays single-purpose and that one stays stable.
class GlobalDocumentSearchDelegate extends SearchDelegate<void> {
  GlobalDocumentSearchDelegate({
    GlobalSearchService? service,
    Future<String?> Function(BuildContext context)? voicePrompt,
  })  : _providedService = service,
        _voicePrompt = voicePrompt ?? VoiceSearchSheet.show;

  /// Opens the voice dictation UI and yields the transcript. Injectable so
  /// tests can drive the wiring without a live recognizer.
  final Future<String?> Function(BuildContext context) _voicePrompt;

  /// The query update implied by a raw voice [transcript]: the trimmed text
  /// when it carries content, otherwise `null` (leave the field untouched).
  static String? voiceQueryUpdate(String? transcript) {
    final t = transcript?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  // Resolved lazily (not in the constructor) so constructing the delegate
  // never requires DI to be warm — `buildResultsList` in particular must stay
  // service-free for widget testing (canned groups, no Get.find calls).
  final GlobalSearchService? _providedService;
  GlobalSearchService get _service =>
      _providedService ??
      (Get.isRegistered<GlobalSearchService>()
          ? Get.find<GlobalSearchService>()
          : Get.put(GlobalSearchService()));

  ApiProvider get _apiProvider => Get.find<ApiProvider>();

  /// The saved Default Warehouse, or null when unset / DI not warm (tests).
  String? get _defaultWarehouse => Get.isRegistered<StorageService>()
      ? Get.find<StorageService>().getDefaultWarehouse()
      : null;

  /// Item read access, mirroring [_permittedTargets] semantics: permissive when
  /// PermissionService isn't registered (widget tests) or access is unknown
  /// (null / cache not warm); only a definite `false` hides the balances. The
  /// inline Item-row balances come from a Stock Balance query, so they must
  /// honour the same Item gate the grouped results already apply.
  bool get _itemReadable {
    if (!Get.isRegistered<PermissionService>()) return true;
    return Get.find<PermissionService>().hasAccess('Item') != false;
  }

  static const int _kMinChars = 3;

  /// The doctype the search is narrowed to. `null` = search all doctypes
  /// (the fan-out). Selecting a scope chip runs a single per-doctype query,
  /// which is far faster than the all-doctype fan-out.
  final ValueNotifier<GlobalSearchTarget?> _scope =
      ValueNotifier<GlobalSearchTarget?>(null);

  // ── Debounced search (delegate instance persists across keystrokes) ──────
  Timer? _debounce;
  String? _pendingKey;
  Future<List<GlobalSearchGroup>>? _pendingFuture;

  /// Runs the search for [q] under [scope] (null = all doctypes), debounced.
  /// The in-flight future is cached per (scope, query) so incidental rebuilds
  /// don't re-fire the network; a scope or query change supersedes the timer.
  Future<List<GlobalSearchGroup>> _search(String q, GlobalSearchTarget? scope) {
    final key = '${scope?.doctype ?? ''} $q';
    if (key == _pendingKey && _pendingFuture != null) return _pendingFuture!;
    _pendingKey = key;
    _debounce?.cancel();
    final completer = Completer<List<GlobalSearchGroup>>();
    _pendingFuture = completer.future;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final result = scope == null
            ? await _service.searchAll(q)
            : GlobalSearchService.buildGroups([
                MapEntry(
                  scope,
                  (await _service.search(scope.doctype, q))
                      .take(GlobalSearchService.kGroupCap)
                      .toList(),
                ),
              ]);
        completer.complete(result);
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    });
    return completer.future;
  }

  @override
  String? get searchFieldLabel => 'Search any document…';

  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(
          icon: const Icon(Icons.mic),
          tooltip: 'Search by voice',
          onPressed: () => _startVoiceSearch(context),
        ),
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

  Future<void> _startVoiceSearch(BuildContext context) async {
    final transcript = await _voicePrompt(context);
    if (!context.mounted) return;
    final update = voiceQueryUpdate(transcript);
    if (update == null) return; // no speech → leave the field untouched
    query = update;
    showResults(context);
  }

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildBody(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildBody(context);

  Widget _buildBody(BuildContext context) {
    // Rebuilds the scope chips + results whenever the selected scope changes,
    // so tapping a chip re-runs the search without needing the query to change.
    return ValueListenableBuilder<GlobalSearchTarget?>(
      valueListenable: _scope,
      builder: (context, scope, _) {
        final scheme = context.scheme;
        return Container(
          color: scheme.bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildScopeChips(
                context,
                _permittedTargets(),
                scope,
                (t) => _scope.value = t,
              ),
              Expanded(child: _buildResultsArea(context, scope)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResultsArea(BuildContext context, GlobalSearchTarget? scope) {
    if (query.trim().length < _kMinChars) {
      return _messageState(
        context,
        icon: Icons.search,
        message: 'Type at least $_kMinChars characters',
      );
    }
    return FutureBuilder<List<GlobalSearchGroup>>(
      future: _search(query.trim(), scope),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Pin to the top so the bar keeps its natural 4px height — returned
          // bare into the surrounding Expanded, a LinearProgressIndicator gets
          // a tight height constraint and stretches to fill the whole area.
          return const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return _messageState(
            context,
            icon: Icons.error_outline,
            message: 'Search failed. Please try again.',
            isError: true,
          );
        }
        final groups = snapshot.data ?? const [];
        if (groups.isEmpty) {
          return _messageState(
            context,
            icon: Icons.search_off,
            message: 'No documents found matching "$query"',
          );
        }
        return _SearchResultsList(
          delegate: this,
          groups: groups,
          warehouse: _defaultWarehouse,
          itemReadable: _itemReadable,
          service: _service,
          onTap: (target, item) {
            close(context, null);
            Get.toNamed(target.route, arguments: target.argsFor(item.id));
          },
        );
      },
    );
  }

  /// The scope targets the user is allowed to read. Falls back to the full
  /// registry when [PermissionService] isn't registered (e.g. widget tests).
  List<GlobalSearchTarget> _permittedTargets() {
    if (!Get.isRegistered<PermissionService>()) return kGlobalSearchTargets;
    final perm = Get.find<PermissionService>();
    return GlobalSearchService.filterPermittedTargets(
      kGlobalSearchTargets,
      (doctype) => perm.hasAccess(doctype),
    );
  }

  /// Horizontally-scrollable scope chip row: an "All" chip (clears the scope)
  /// followed by one chip per [targets] entry. Service-free for widget testing.
  @visibleForTesting
  Widget buildScopeChips(
    BuildContext context,
    List<GlobalSearchTarget> targets,
    GlobalSearchTarget? selected,
    void Function(GlobalSearchTarget?) onSelect,
  ) {
    final scheme = context.scheme;
    return Material(
      color: scheme.bg,
      child: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SelectableFilterChip(
                label: 'All',
                selected: selected == null,
                onSelected: (_) => onSelect(null),
              ),
            ),
            for (final t in targets)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: SelectableFilterChip(
                  label: t.label,
                  selected: selected?.doctype == t.doctype,
                  onSelected: (_) => onSelect(t),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Flat scroll list: a header row per group, then its result rows. Item rows
  /// render the inline Default-Warehouse balance from [balances] (or a loader
  /// while [balancesLoading]); with neither set they fall back to the chevron.
  @visibleForTesting
  Widget buildResultsList(
    BuildContext context,
    List<GlobalSearchGroup> groups,
    void Function(GlobalSearchTarget target, GlobalSearchItem item) onTap, {
    Map<String, WarehouseStockLine>? balances,
    bool balancesLoading = false,
  }) {
    final scheme = context.scheme;
    final children = <Widget>[];
    for (final group in groups) {
      children.add(_sectionHeader(context, group.target));
      for (final item in group.items) {
        children.add(_resultTile(
          context,
          group.target,
          item,
          onTap,
          balances: balances,
          balancesLoading: balancesLoading,
        ));
      }
    }
    return Container(
      color: scheme.bg,
      child: ListView(
        // Clear the Android gesture/nav bar so the last row isn't hidden.
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        children: children,
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, GlobalSearchTarget target) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: [
          Icon(target.icon, size: 15, color: target.color),
          const SizedBox(width: 8),
          Text(
            target.label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: scheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultTile(
    BuildContext context,
    GlobalSearchTarget target,
    GlobalSearchItem item,
    void Function(GlobalSearchTarget, GlobalSearchItem) onTap, {
    Map<String, WarehouseStockLine>? balances,
    bool balancesLoading = false,
  }) {
    final scheme = context.scheme;
    return ListTile(
      leading: _leadingIcon(target, item.imageUrl),
      title: Text(
        item.title,
        style: TextStyle(fontWeight: FontWeight.w600, color: scheme.text),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: item.subtitle != null
          ? Text(
              item.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.textMuted),
            )
          : null,
      trailing: _trailingFor(context, target, item, balances, balancesLoading),
      onTap: () => onTap(target, item),
    );
  }

  /// The trailing widget for a result row. Item rows show the Default-Warehouse
  /// balance (bold qty + uom), a small loader while it's fetching, or `0` once
  /// loaded with no stock row; every other case (non-Item row, or feature off)
  /// shows the chevron.
  Widget _trailingFor(
    BuildContext context,
    GlobalSearchTarget target,
    GlobalSearchItem item,
    Map<String, WarehouseStockLine>? balances,
    bool balancesLoading,
  ) {
    final scheme = context.scheme;
    final chevron = Icon(Icons.chevron_right, color: scheme.textSubtle);
    if (target.doctype != 'Item') return chevron;
    if (balancesLoading) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (balances == null) return chevron; // feature off / error
    final line = balances[item.id];
    final label = line == null
        ? '0'
        : '${_qtyLabel(line.balanceQty)} ${line.uom}'.trim();
    return Text(
      label,
      style: TextStyle(fontWeight: FontWeight.w700, color: scheme.text),
    );
  }

  Widget _leadingIcon(GlobalSearchTarget target, String? imageUrl) {
    if (imageUrl != null &&
        imageUrl.isNotEmpty &&
        Get.isRegistered<ApiProvider>()) {
      final fullUrl = imageUrl.startsWith('http')
          ? imageUrl
          : '${_apiProvider.baseUrl}$imageUrl';
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          fullUrl,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _iconAvatar(target),
        ),
      );
    }
    return _iconAvatar(target);
  }

  Widget _iconAvatar(GlobalSearchTarget target) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: target.color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(target.icon, color: target.color, size: 20),
      );

  Widget _messageState(
    BuildContext context, {
    required IconData icon,
    required String message,
    bool isError = false,
  }) {
    final scheme = context.scheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: isError ? colorScheme.error : scheme.textSubtle,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isError ? colorScheme.error : scheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

String _qtyLabel(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// Renders the grouped search results immediately, then — when a Default
/// Warehouse is set and Item is readable — fetches the warehouse balances for
/// the Item group's already-known codes and rebuilds so each Item row shows its
/// balance inline. Fetch failure falls back to the chevron (search never breaks).
class _SearchResultsList extends StatefulWidget {
  const _SearchResultsList({
    required this.delegate,
    required this.groups,
    required this.warehouse,
    required this.itemReadable,
    required this.service,
    required this.onTap,
  });

  final GlobalDocumentSearchDelegate delegate;
  final List<GlobalSearchGroup> groups;
  final String? warehouse;
  final bool itemReadable;
  final GlobalSearchService service;
  final void Function(GlobalSearchTarget, GlobalSearchItem) onTap;

  @override
  State<_SearchResultsList> createState() => _SearchResultsListState();
}

class _SearchResultsListState extends State<_SearchResultsList> {
  Map<String, WarehouseStockLine>? _balances; // null = feature off / loading / error
  bool _loading = false;
  int _fetchId = 0; // guards against a stale in-flight fetch resolving last

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(_SearchResultsList old) {
    super.didUpdateWidget(old);
    if (old.warehouse != widget.warehouse ||
        _itemCodesOf(old.groups) != _itemCodesOf(widget.groups)) {
      _fetch();
    }
  }

  bool get _active => widget.warehouse != null && widget.itemReadable;

  static String _itemCodesOf(List<GlobalSearchGroup> groups) {
    for (final g in groups) {
      if (g.target.doctype == 'Item') {
        return g.items.map((i) => i.id).join(',');
      }
    }
    return '';
  }

  Future<void> _fetch() async {
    final int id = ++_fetchId;
    final codesKey = _itemCodesOf(widget.groups);
    if (!_active || codesKey.isEmpty) {
      setState(() {
        _balances = null;
        _loading = false;
      });
      return;
    }
    final codes = codesKey.split(',').where((c) => c.isNotEmpty).toList();
    setState(() {
      _balances = null;
      _loading = true;
    });
    try {
      final result =
          await widget.service.warehouseBalances(codes, widget.warehouse!);
      if (!mounted || id != _fetchId) return;
      setState(() {
        _balances = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || id != _fetchId) return;
      // Fail closed: fall back to the chevron; never break document search.
      setState(() {
        _balances = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.delegate.buildResultsList(
      context,
      widget.groups,
      widget.onTap,
      balances: _balances,
      balancesLoading: _loading,
    );
  }
}
