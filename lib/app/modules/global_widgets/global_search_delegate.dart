import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show SemanticsInputType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/global_search_service.dart';
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';
import 'package:multimax/app/modules/global_widgets/recent_search_suggestions.dart';
import 'package:multimax/app/shared/image_scan/image_scan_flow.dart';
import 'package:multimax/app/shared/image_scan/image_scan_result.dart';

typedef SearchListDocuments =
    Future<List<GlobalSearchItem>> Function(String doctype, String query);
typedef ListSearchImageScanner =
    Future<ImageScanResult?> Function(BuildContext context);

/// SearchDelegate adapter for callers that use Flutter's showSearch API.
/// List headers and applied search chips use [showListSearch] instead.
class DocTypeSearchDelegate extends SearchDelegate<void> {
  // ── API search (optional) ──────────────────────────────────────────────
  final String doctype;
  final String targetRoute;

  // ── Local search wiring (optional) ────────────────────────────────────
  /// The controller's [RxString] that holds the current query.
  final RxString? searchQuery;

  /// Called on every keystroke; debounce is handled by the controller.
  final ValueChanged<String>? onSearchChanged;

  /// Called when the user taps the × clear button.
  final VoidCallback? onSearchClear;

  // ── Filter button (optional) ───────────────────────────────────────────
  /// Map of currently active filters — drives the badge count.
  final RxMap<String, dynamic>? activeFilters;

  /// Opens the DocType-specific filter bottom sheet.
  final VoidCallback? onFilterTap;

  // ── Image scan (optional) ──────────────────────────────────────────────
  /// When non-null, the search delegate shows a camera icon that opens the
  /// image scan flow. Only [ItemListAppBar] sets this.
  final ValueChanged<ImageScanResult>? onImageScanResult;

  final SearchListDocuments? searcher;
  final String? recentSearchKey;
  late final _SearchSession _session;

  DocTypeSearchDelegate({
    this.doctype = '',
    this.targetRoute = '',
    this.searchQuery,
    this.onSearchChanged,
    this.onSearchClear,
    this.activeFilters,
    this.onFilterTap,
    this.onImageScanResult,
    this.searcher,
    this.recentSearchKey,
    RecentSearchStore? recentSearchStore,
  }) {
    _session = _SearchSession(
      doctype: doctype,
      targetRoute: targetRoute,
      recentSearchKey: recentSearchKey ?? doctype,
      recentSearchStore: recentSearchStore,
      searcher: searcher,
    );
  }

  String? _notifiedQuery;
  ModalRoute<dynamic>? _route;
  bool _disposed = false;
  bool _scanning = false;

  @override
  String get searchFieldLabel =>
      _session.isApiMode ? _session.label : 'Search…';

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = super.appBarTheme(context);
    final scheme = context.scheme;
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: scheme.fg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
          color: scheme.text,
        ),
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        hintStyle: theme.textTheme.titleLarge?.copyWith(
          color: scheme.textMuted,
        ),
      ),
      textSelectionTheme: HeaderPalette.of(context).searchSelection,
    );
  }

  void _observeRoute(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null || identical(route, _route)) return;
    _route = route;
    unawaited(
      route.popped.then((_) {
        if (!identical(route, _route) || _disposed) return;
        _route = null;
        _notifiedQuery = null;
        _session.cancelSearch();
      }),
    );
  }

  // Flutter asks the delegate for its bodies during build. Publish after
  // layout, once per query, while the route and that exact query are current.
  void _notifyAfterBuild(BuildContext context) {
    _observeRoute(context);
    final value = query;
    if (onSearchChanged == null || _notifiedQuery == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed ||
          !context.mounted ||
          ModalRoute.of(context)?.isCurrent == false ||
          query != value) {
        return;
      }
      _notify(value);
    });
  }

  void _notify(String value) {
    if (_notifiedQuery == value) return;
    _notifiedQuery = value;
    onSearchChanged?.call(value);
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return [
      if (query.isNotEmpty)
        HeaderIconAction(
          tooltip: 'Clear search',
          foregroundColor: context.scheme.text,
          onPressed: () {
            query = '';
            _notifiedQuery = '';
            _clearSearch(onSearchClear, onSearchChanged);
            showSuggestions(context);
          },
          child: const Icon(Icons.clear),
        ),
      if (onFilterTap != null && activeFilters == null)
        _filterButton(colorScheme, 0),
      if (onFilterTap != null && activeFilters != null)
        Obx(() => _filterButton(colorScheme, activeFilters!.length)),
      if (onImageScanResult != null)
        HeaderIconAction(
          tooltip: 'Search by image',
          foregroundColor: context.scheme.text,
          onPressed: () async {
            if (_scanning) return;
            _scanning = true;
            try {
              final result = await ImageScanFlow.run(context);
              if (result != null &&
                  context.mounted &&
                  ModalRoute.of(context)?.isCurrent == true) {
                close(context, null);
                onImageScanResult!(result);
              }
            } finally {
              _scanning = false;
            }
          },
          child: const Icon(Icons.image_search),
        ),
    ];
  }

  Widget _filterButton(ColorScheme colorScheme, int count) {
    return Tooltip(
      message: count > 0
          ? '$count filter${count > 1 ? 's' : ''} active'
          : 'Filter',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onFilterTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                count > 0 ? Icons.filter_alt : Icons.filter_list,
                color: count > 0
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              if (count > 0)
                Positioned(
                  top: -4,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: colorScheme.onError,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget buildLeading(BuildContext context) => HeaderIconAction(
    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    foregroundColor: context.scheme.text,
    onPressed: () => close(context, null),
    child: const BackButtonIcon(),
  );

  @override
  void showResults(BuildContext context) {
    _session.history.record(query);
    super.showResults(context);
  }

  @override
  Widget buildResults(BuildContext context) {
    _notifyAfterBuild(context);
    if (_session.isApiMode) return _buildBody(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed &&
          context.mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        close(context, null);
      }
    });
    return const SizedBox.shrink();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    _notifyAfterBuild(context);
    return _buildBody(context);
  }

  Widget _buildBody(BuildContext context) => _session.buildBody(
    context,
    query: query,
    onSelect: (context, term) {
      query = term;
      if (_session.isApiMode) {
        showResults(context);
      } else {
        _applyLocalSearch(context);
      }
    },
    onApply: () => _applyLocalSearch(context),
    onOpenResult: () => close(context, null),
  );

  void _applyLocalSearch(BuildContext context) {
    _session.history.record(query);
    _notify(query);
    close(context, null);
  }

  @override
  void dispose() {
    _disposed = true;
    _session.dispose();
    super.dispose();
  }
}

/// Backward-compatible name for the SDK search delegate.
typedef GlobalSearchDelegate = DocTypeSearchDelegate;

void _clearSearch(VoidCallback? onClear, ValueChanged<String>? onChanged) {
  if (onClear != null) {
    onClear();
  } else {
    onChanged?.call('');
  }
}

/// Query results and history shared by the adaptive route and Flutter adapter.
class _SearchSession {
  _SearchSession({
    required this.doctype,
    required this.targetRoute,
    required String? recentSearchKey,
    RecentSearchStore? recentSearchStore,
    this.searcher,
  }) {
    history = RecentSearchHistory(
      recentSearchKey == null || recentSearchKey.trim().isEmpty
          ? null
          : recentSearchKey,
      isApiMode ? _minApiChars : 1,
      recentSearchStore,
    );
  }

  final String doctype;
  final String targetRoute;
  final SearchListDocuments? searcher;
  late final RecentSearchHistory history;
  late final GlobalSearchService _service = Get.put(GlobalSearchService());
  late final ApiProvider _apiProvider = Get.find<ApiProvider>();

  bool get isApiMode => doctype.isNotEmpty && targetRoute.isNotEmpty;
  String get label => doctype.isEmpty ? 'Search…' : 'Search $doctype…';
  static const _minApiChars = 3;

  Timer? _debounce;
  String? _pendingKey;
  Completer<List<GlobalSearchItem>>? _pendingSearch;

  Future<List<GlobalSearchItem>> _search(String query) {
    if (query == _pendingKey) return _pendingSearch!.future;
    cancelSearch();
    final pending = Completer<List<GlobalSearchItem>>();
    _pendingKey = query;
    _pendingSearch = pending;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await (searcher ?? _service.search)(doctype, query);
        if (!pending.isCompleted) pending.complete(results);
      } catch (error, stack) {
        if (!pending.isCompleted) pending.completeError(error, stack);
      }
    });
    return pending.future;
  }

  void cancelSearch() {
    _debounce?.cancel();
    final pending = _pendingSearch;
    if (pending != null && !pending.isCompleted) {
      pending.complete(const []);
    }
    _pendingKey = null;
    _pendingSearch = null;
  }

  Widget buildBody(
    BuildContext context, {
    required String query,
    required void Function(BuildContext, String) onSelect,
    required VoidCallback onApply,
    required VoidCallback onOpenResult,
  }) {
    if (!isApiMode) {
      return history.build(
        query: query,
        fallback: _buildLocalHint(context, query, onApply),
        includeHint: query.isNotEmpty,
        onSelect: onSelect,
      );
    }
    if (query.trim().length < _minApiChars) {
      cancelSearch();
      return history.build(
        query: query,
        fallback: _buildMessageState(
          icon: Icons.search,
          message: 'Type at least $_minApiChars characters',
        ),
        onSelect: onSelect,
      );
    }

    return FutureBuilder<List<GlobalSearchItem>>(
      future: _search(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: LinearProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildMessageState(
            icon: Icons.error_outline,
            message: 'Search failed. Please try again.',
            isError: true,
          );
        }

        final results = snapshot.data ?? [];
        if (results.isEmpty) {
          return _buildMessageState(
            icon: Icons.search_off,
            message: 'No $doctype found matching "$query"',
          );
        }

        return ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) =>
              _buildResultTile(results[index], query, onOpenResult),
        );
      },
    );
  }

  Widget _buildLocalHint(
    BuildContext context,
    String query,
    VoidCallback onApply,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasQuery = query.isNotEmpty;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Icons.manage_search : Icons.search,
              size: 64,
              color: colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              hasQuery
                  ? 'Press ↵ to apply "$query"'
                  : 'Type to search the list',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (hasQuery) ...[
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: onApply,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Apply'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultTile(
    GlobalSearchItem item,
    String query,
    VoidCallback onOpenResult,
  ) {
    return ListTile(
      leading: _buildLeadingIcon(item.imageUrl),
      title: Text(
        item.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: item.subtitle != null
          ? Text(item.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        history.record(query);
        onOpenResult();
        Get.toNamed(
          targetRoute,
          arguments: searchNavArgsFor(targetRoute, item.id),
        );
      },
    );
  }

  Widget _buildLeadingIcon(String? imageUrl) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final baseUrl = _apiProvider.baseUrl;
      final fullUrl = imageUrl.startsWith('http')
          ? imageUrl
          : '$baseUrl$imageUrl';
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          fullUrl,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultIcon(),
        ),
      );
    }
    return _defaultIcon();
  }

  Widget _defaultIcon() {
    return CircleAvatar(
      backgroundColor: Colors.blueGrey.shade100,
      foregroundColor: Colors.blueGrey.shade700,
      child: const Icon(Icons.description, size: 20),
    );
  }

  Widget _buildMessageState({
    required IconData icon,
    required String message,
    bool isError = false,
  }) => Builder(
    builder: (context) {
      final error = Theme.of(context).colorScheme.error;
      final scheme = context.scheme;
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 64,
                color: isError ? error : scheme.textSubtle,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: TextStyle(color: isError ? error : scheme.textMuted),
              ),
            ],
          ),
        ),
      );
    },
  );

  void dispose() {
    cancelSearch();
    history.dispose();
  }
}

/// Opens list search with the live query and the source screen's history key.
Future<void> showListSearch(
  BuildContext context, {
  String query = '',
  String doctype = '',
  String targetRoute = '',
  String? recentSearchKey,
  ValueChanged<String>? onSearchChanged,
  VoidCallback? onSearchClear,
  ValueChanged<ImageScanResult>? onImageScanResult,
  RecentSearchStore? recentSearchStore,
  SearchListDocuments? searcher,
  ListSearchImageScanner imageScanner = ImageScanFlow.run,
}) {
  final key = listRecentSearchKey(context, recentSearchKey, doctype);
  final navigator = Navigator.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  final toolbarScaler = scaler == MediaQuery.textScalerOf(navigator.context)
      ? null
      : scaler;
  final direction = Directionality.of(context);
  final directionOverride = direction == Directionality.of(navigator.context)
      ? null
      : direction;
  return navigator.push<void>(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (context, _, _) {
        final page = _ListSearchPage(
          initialQuery: query,
          doctype: doctype,
          targetRoute: targetRoute,
          recentSearchKey: key,
          recentSearchStore: recentSearchStore,
          searcher: searcher,
          onSearchChanged: onSearchChanged,
          onSearchClear: onSearchClear,
          onImageScanResult: onImageScanResult,
          imageScanner: imageScanner,
          toolbarScaler: toolbarScaler,
        );
        return Builder(
          builder: (context) => Directionality(
            textDirection: directionOverride ?? Directionality.of(context),
            child: page,
          ),
        );
      },
    ),
  );
}

/// Re-opens the shared search from an applied "Search: …" chip.
Future<void> editListSearch(
  BuildContext context, {
  required RxString searchQuery,
  String doctype = '',
  String targetRoute = '',
  String? recentSearchKey,
  ValueChanged<String>? onSearchChanged,
  VoidCallback? onSearchClear,
  ValueChanged<ImageScanResult>? onImageScanResult,
}) => showListSearch(
  context,
  query: searchQuery.value,
  doctype: doctype,
  targetRoute: targetRoute,
  recentSearchKey: recentSearchKey,
  onSearchChanged: onSearchChanged,
  onSearchClear: onSearchClear,
  onImageScanResult: onImageScanResult,
);

class _ListSearchPage extends StatefulWidget {
  const _ListSearchPage({
    required this.initialQuery,
    required this.doctype,
    required this.targetRoute,
    required this.recentSearchKey,
    required this.recentSearchStore,
    required this.searcher,
    required this.onSearchChanged,
    required this.onSearchClear,
    required this.onImageScanResult,
    required this.imageScanner,
    required this.toolbarScaler,
  });

  final String initialQuery;
  final String doctype;
  final String targetRoute;
  final String? recentSearchKey;
  final RecentSearchStore? recentSearchStore;
  final SearchListDocuments? searcher;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onSearchClear;
  final ValueChanged<ImageScanResult>? onImageScanResult;
  final ListSearchImageScanner imageScanner;
  final TextScaler? toolbarScaler;

  @override
  State<_ListSearchPage> createState() => _ListSearchPageState();
}

class _ListSearchEditingController extends TextEditingController {
  _ListSearchEditingController(super.value) : super.fromValue();

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final selected = selection;
    if (!withComposing ||
        !selected.isValid ||
        selected.isCollapsed ||
        selected.end > text.length) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final composing = value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final boundaries = {
      0,
      text.length,
      selected.start,
      selected.end,
      if (composing.isValid) ...[composing.start, composing.end],
    }.toList()..sort();
    final selectionStyle = TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: HeaderPalette.of(context).ink,
      decorationThickness: 2,
    );
    return TextSpan(
      style: style,
      children: [
        for (var i = 0; i < boundaries.length - 1; i++)
          TextSpan(
            text: text.substring(boundaries[i], boundaries[i + 1]),
            style:
                boundaries[i] >= selected.start && boundaries[i] < selected.end
                ? selectionStyle
                : boundaries[i] >= composing.start &&
                      boundaries[i] < composing.end
                ? const TextStyle(decoration: TextDecoration.underline)
                : null,
          ),
      ],
    );
  }
}

class _ListSearchPageState extends State<_ListSearchPage> {
  late final _SearchSession _session = _SearchSession(
    doctype: widget.doctype,
    targetRoute: widget.targetRoute,
    recentSearchKey: widget.recentSearchKey,
    recentSearchStore: widget.recentSearchStore,
    searcher: widget.searcher,
  );
  late final _controller = _ListSearchEditingController(
    TextEditingValue(
      text: widget.initialQuery,
      selection: TextSelection.collapsed(offset: widget.initialQuery.length),
    ),
  );
  final _fieldFocus = FocusNode(debugLabel: 'List search input');
  final _toolbarKey = GlobalKey();
  final _resultsKey = GlobalKey();
  Animation<double>? _openingAnimation;
  late String _query = widget.initialQuery;
  bool _sentEdit = false;
  bool _closing = false;
  bool _scanning = false;
  bool _showingResults = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_highlightChanged);
    _fieldFocus.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation == _openingAnimation) return;
    _openingAnimation?.removeStatusListener(_focusAfterOpen);
    _openingAnimation = animation;
    animation?.addStatusListener(_focusAfterOpen);
  }

  void _focusAfterOpen(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _openingAnimation?.removeStatusListener(_focusAfterOpen);
    _fieldFocus.requestFocus();
  }

  void _highlightChanged(FocusHighlightMode _) => _focusChanged();

  void _focusChanged() {
    if (!mounted) return;
    setState(() {
      if (_fieldFocus.hasFocus) _showingResults = false;
    });
  }

  void _changeQuery(String value) {
    if (_closing || value == _query) return;
    setState(() => _query = value);
    _sentEdit = widget.onSearchChanged != null;
    widget.onSearchChanged?.call(value);
  }

  void _clear() {
    if (_closing || _query.isEmpty) return;
    _controller.clear();
    setState(() {
      _query = '';
      _showingResults = false;
    });
    if (_sentEdit && widget.onSearchClear != null) {
      // Replace any controller debounce armed by the previous edit.
      widget.onSearchChanged?.call('');
    }
    _sentEdit = false;
    _clearSearch(widget.onSearchClear, widget.onSearchChanged);
    _fieldFocus.requestFocus();
  }

  void _selectRecent(BuildContext context, String value) {
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _changeQuery(value);
    _submit();
  }

  void _submit() {
    if (_closing) return;
    _session.history.record(_query);
    if (_session.isApiMode) {
      setState(() => _showingResults = true);
      _fieldFocus.unfocus();
    } else {
      _close();
    }
  }

  void _didClose(bool didPop, void _) {
    if (didPop) {
      _closing = true;
      _session.cancelSearch();
    }
  }

  void _close() {
    if (_closing || ModalRoute.of(context)?.isCurrent != true) return;
    Navigator.of(context).pop();
  }

  Future<void> _scan() async {
    if (_scanning || _closing) return;
    setState(() => _scanning = true);
    try {
      final result = await widget.imageScanner(context);
      if (result == null ||
          !mounted ||
          _closing ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      _close();
      widget.onImageScanResult?.call(result);
    } finally {
      if (mounted && !_closing) setState(() => _scanning = false);
    }
  }

  @override
  void dispose() {
    _openingAnimation?.removeStatusListener(_focusAfterOpen);
    FocusManager.instance.removeHighlightModeListener(_highlightChanged);
    _fieldFocus.dispose();
    _controller.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    onPopInvokedWithResult: _didClose,
    child: CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: _session.label,
        child: Scaffold(body: Builder(builder: _buildBody)),
      ),
    ),
  );

  Widget _buildBody(BuildContext context) {
    final media = MediaQuery.of(context);
    final results = MediaQuery(
      key: _resultsKey,
      data: media.removePadding(removeTop: true),
      child: Builder(builder: _buildResults),
    );
    final toolbar = ListHeaderTextScope(
      child: LayoutBuilder(
        builder: (context, constraints) =>
            _buildLayout(context, constraints, results),
      ),
    );
    final scaler = widget.toolbarScaler;
    if (scaler == null) return toolbar;
    return MediaQuery(
      data: media.copyWith(textScaler: scaler),
      child: toolbar,
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_closing) return const SizedBox.shrink();
    final body = _session.buildBody(
      context,
      query: _query,
      onSelect: _selectRecent,
      onApply: _submit,
      onOpenResult: _close,
    );
    if (!_session.isApiMode) return body;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: KeyedSubtree(key: ValueKey(_showingResults), child: body),
    );
  }

  Widget _buildLayout(
    BuildContext context,
    BoxConstraints constraints,
    Widget results,
  ) {
    final scheme = context.scheme;
    final style = Theme.of(
      context,
    ).textTheme.titleLarge!.copyWith(color: scheme.text);
    const sideInset = 16.0;
    const verticalInset = 4.0;
    const fieldInset = 6.0;
    const actionSize = 48.0;
    const leadingWidth = 56.0;
    const actionRowHeight = 56.0;
    final labelSize = measureHeaderText(context, _session.label, style).size;
    final fieldHeight = math.max(
      actionSize,
      labelSize.height.ceilToDouble() + 2 * verticalInset,
    );
    final showClear = _query.isNotEmpty;
    final showCamera = widget.onImageScanResult != null;
    final suffixWidth =
        (showClear ? actionSize : 0) + (showCamera ? actionSize : 0);
    final padding = MediaQuery.paddingOf(context);
    final availableHeight = constraints.maxHeight - padding.top;
    final fieldWidth =
        constraints.maxWidth - padding.horizontal - leadingWidth - suffixWidth;
    final stackedHeight = actionRowHeight + fieldHeight + verticalInset;
    final inline =
        fieldWidth - 2 * sideInset >= labelSize.width ||
        (fieldWidth >= actionSize &&
            stackedHeight + actionSize > availableHeight);
    final rowHeight = math.max(
      actionRowHeight,
      fieldHeight + 2 * verticalInset,
    );
    final toolbarHeight = inline ? rowHeight : stackedHeight;
    final actionTop = ((inline ? rowHeight : actionRowHeight) - actionSize) / 2;
    final inputInset = inline
        ? ((fieldWidth - actionSize) / 2).clamp(0.0, sideInset - fieldInset)
        : sideInset - fieldInset;
    final field = FocusTraversalOrder(
      order: NumericFocusOrder(inline ? 1 : 3),
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.enter): _submit},
        child: HeaderActionContour(
          states: {
            if (_fieldFocus.hasFocus &&
                FocusManager.instance.highlightMode ==
                    FocusHighlightMode.traditional)
              WidgetState.focused,
          },
          borderRadius: 8,
          child: TextSelectionTheme(
            data: HeaderPalette.of(context).searchSelection,
            child: Semantics(
              label: _session.label,
              inputType: SemanticsInputType.search,
              child: TextField(
                controller: _controller,
                focusNode: _fieldFocus,
                style: style,
                textAlignVertical: TextAlignVertical.center,
                textInputAction: TextInputAction.search,
                onChanged: _changeQuery,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hint: ExcludeSemantics(
                    child: Text(
                      _session.label,
                      style: style.copyWith(color: scheme.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: fieldInset,
                    vertical: verticalInset,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final overlayStyle = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    final toolbar = Material(
      key: _toolbarKey,
      color: scheme.fg,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: SizedBox(
            height: toolbarHeight,
            child: Stack(
              children: [
                PositionedDirectional(
                  top: actionTop,
                  start: inline ? (leadingWidth - actionSize) / 2 : 0,
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(0),
                    child: HeaderIconAction(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      foregroundColor: scheme.text,
                      onPressed: _close,
                      child: const BackButtonIcon(),
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: inline ? (rowHeight - fieldHeight) / 2 : actionRowHeight,
                  start: (inline ? leadingWidth : 0) + inputInset,
                  end: (inline ? suffixWidth : 0) + inputInset,
                  height: fieldHeight,
                  child: field,
                ),
                if (showClear)
                  PositionedDirectional(
                    key: const ValueKey('clear'),
                    top: actionTop,
                    end: showCamera ? actionSize : 0,
                    child: FocusTraversalOrder(
                      order: NumericFocusOrder(inline ? 2 : 1),
                      child: HeaderIconAction(
                        tooltip: 'Clear search',
                        foregroundColor: scheme.text,
                        onPressed: _clear,
                        child: const Icon(Icons.clear),
                      ),
                    ),
                  ),
                if (showCamera)
                  PositionedDirectional(
                    key: const ValueKey('camera'),
                    top: actionTop,
                    end: 0,
                    child: FocusTraversalOrder(
                      order: NumericFocusOrder(inline ? 3 : 2),
                      child: MergeSemantics(
                        child: Semantics(
                          liveRegion: _scanning,
                          value: _scanning ? 'Scanning image' : null,
                          child: HeaderIconAction(
                            tooltip: 'Search by image',
                            foregroundColor: scheme.text,
                            onPressed: _scanning ? null : _scan,
                            child: const Icon(Icons.image_search),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (toolbarHeight + actionSize <= availableHeight) {
      return Column(
        children: [
          AnnotatedRegion(value: overlayStyle, child: toolbar),
          Expanded(child: results),
        ],
      );
    }

    // In tight windows the results can use the same viewport as the toolbar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fieldContext = _fieldFocus.context;
      if (_fieldFocus.hasFocus &&
          fieldContext != null &&
          fieldContext.mounted) {
        Scrollable.ensureVisible(fieldContext, alignment: 0.5);
      }
    });
    final topInset = math.min(padding.top, constraints.maxHeight);
    return Column(
      children: [
        AnnotatedRegion(
          value: overlayStyle,
          child: ColoredBox(
            color: scheme.fg,
            child: SizedBox(width: double.infinity, height: topInset),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                children: [
                  toolbar,
                  SizedBox(
                    height: constraints.maxHeight - topInset,
                    child: results,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
