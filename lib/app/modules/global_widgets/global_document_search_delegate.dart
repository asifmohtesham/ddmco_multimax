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

  /// The Stock Balance section only shows under the All or Item scopes.
  static bool _sbScopeAllowed(GlobalSearchTarget? scope) =>
      scope == null || scope.doctype == 'Item';

  /// Item read access, mirroring [_permittedTargets] semantics: permissive when
  /// PermissionService isn't registered (widget tests) or access is unknown
  /// (null / cache not warm); only a definite `false` hides the section. The
  /// Stock Balance footer surfaces item data via a direct Item search, so it
  /// must honour the same Item gate the grouped results already apply.
  bool get _itemReadable {
    if (!Get.isRegistered<PermissionService>()) return true;
    return Get.find<PermissionService>().hasAccess('Item') != false;
  }

  static final GlobalSearchTarget _itemTarget =
      kGlobalSearchTargets.firstWhere((t) => t.doctype == 'Item');

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
        final wh = _defaultWarehouse;
        final footer = (wh != null && _itemReadable && _sbScopeAllowed(scope))
            ? _StockBalanceSection(
                query: query.trim(),
                warehouse: wh,
                service: _service,
                onTapItem: (line) {
                  close(context, null);
                  Get.toNamed(
                    _itemTarget.route,
                    arguments: _itemTarget.argsFor(line.itemCode),
                  );
                },
              )
            : null;
        return buildResultsList(
          context,
          groups,
          (target, item) {
            close(context, null);
            Get.toNamed(target.route, arguments: target.argsFor(item.id));
          },
          footer: footer,
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

  /// Flat scroll list: a header row per group, then its result rows.
  @visibleForTesting
  Widget buildResultsList(
    BuildContext context,
    List<GlobalSearchGroup> groups,
    void Function(GlobalSearchTarget target, GlobalSearchItem item) onTap, {
    Widget? footer,
  }) {
    final scheme = context.scheme;
    final children = <Widget>[];
    for (final group in groups) {
      children.add(_sectionHeader(context, group.target));
      for (final item in group.items) {
        children.add(_resultTile(context, group.target, item, onTap));
      }
    }
    if (footer != null) children.add(footer);
    return Container(
      color: scheme.bg,
      child: ListView(children: children),
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
    void Function(GlobalSearchTarget, GlobalSearchItem) onTap,
  ) {
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
      trailing: Icon(Icons.chevron_right, color: scheme.textSubtle),
      onTap: () => onTap(target, item),
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

/// Async wrapper: fetches Stock Balance for [query] in [warehouse] and renders
/// it via [buildStockBalanceSection]. Its own future so it fills in AFTER the
/// document results (loading feedback), and re-fires when query/warehouse change.
class _StockBalanceSection extends StatefulWidget {
  const _StockBalanceSection({
    required this.query,
    required this.warehouse,
    required this.service,
    required this.onTapItem,
  });

  final String query;
  final String warehouse;
  final GlobalSearchService service;
  final void Function(WarehouseStockLine) onTapItem;

  @override
  State<_StockBalanceSection> createState() => _StockBalanceSectionState();
}

class _StockBalanceSectionState extends State<_StockBalanceSection> {
  late Future<List<WarehouseStockLine>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service.stockBalanceForQuery(widget.query, widget.warehouse);
  }

  @override
  void didUpdateWidget(_StockBalanceSection old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query || old.warehouse != widget.warehouse) {
      _future =
          widget.service.stockBalanceForQuery(widget.query, widget.warehouse);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WarehouseStockLine>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return buildStockBalanceSection(context, widget.warehouse, null);
        }
        // Hide the section entirely on error — never break document search.
        if (snap.hasError) return const SizedBox.shrink();
        return buildStockBalanceSection(
          context,
          widget.warehouse,
          snap.data ?? const [],
          onTap: widget.onTapItem,
        );
      },
    );
  }
}

String _qtyLabel(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// Pure renderer for the search Stock Balance section. [lines] == null renders
/// the loading state; empty renders a message; non-empty renders tappable rows.
@visibleForTesting
Widget buildStockBalanceSection(
  BuildContext context,
  String warehouse,
  List<WarehouseStockLine>? lines, {
  void Function(WarehouseStockLine)? onTap,
}) {
  final scheme = context.scheme;
  final header = Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Row(
      children: [
        const Icon(Icons.warehouse_outlined, size: 15, color: Colors.teal),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'STOCK BALANCE · $warehouse'.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: scheme.textMuted,
            ),
          ),
        ),
      ],
    ),
  );

  if (lines == null) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: LinearProgressIndicator(),
        ),
      ],
    );
  }

  if (lines.isEmpty) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            'No stock for matching items in $warehouse',
            style: TextStyle(color: scheme.textMuted),
          ),
        ),
      ],
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      header,
      for (final line in lines)
        ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.inventory_2_outlined,
                color: Colors.teal, size: 20),
          ),
          title: Text(
            line.itemName.isEmpty ? line.itemCode : line.itemName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w600, color: scheme.text),
          ),
          subtitle: Text(
            line.itemCode,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.textMuted),
          ),
          trailing: Text(
            '${_qtyLabel(line.balanceQty)} ${line.uom}'.trim(),
            style: TextStyle(fontWeight: FontWeight.w700, color: scheme.text),
          ),
          onTap: onTap == null ? null : () => onTap(line),
        ),
    ],
  );
}
