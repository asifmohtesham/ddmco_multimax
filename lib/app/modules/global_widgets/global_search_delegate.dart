import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/global_search_service.dart';
import 'package:multimax/app/modules/global_widgets/recent_search_suggestions.dart';
import 'package:multimax/app/shared/image_scan/image_scan_flow.dart';
import 'package:multimax/app/shared/image_scan/image_scan_result.dart';

/// Unified search + filter delegate for every DocType list screen.
///
/// Replaces the old split between the AppBar [GlobalSearchDelegate] icon and
/// the in-list [SearchBar] filter suffix.  Now a single AppBar search icon
/// opens this overlay which owns:
///
///  1. **Text search** — the standard [SearchDelegate] query bar.
///     - In *API mode* (both [doctype] and [targetRoute] are non-empty) the
///       delegate calls the ERPNext search API and shows a result list that
///       navigates on tap.
///     - In *local mode* ([doctype]/[targetRoute] empty, [onSearchChanged]
///       provided) every keystroke is forwarded to the controller's RxString
///       and the delegate closes on submit so the filtered list is revealed.
///     - Recent searches are saved on explicit commits, per user and
///       [recentSearchKey] (or [doctype]). Selecting one runs the search.
///
///  2. **Filter button** — badged [IconButton] injected into [buildActions]
///     when [onFilterTap] is provided.  Mirrors the old trailing filter icon
///     that lived inside the SearchBar widget.
///
/// ### IMPORTANT — build-phase safety
/// [buildSuggestions] and [buildResults] are invoked by Flutter during its
/// build phase.  Any synchronous write to a GetX [Rx] value from inside
/// those methods will trigger [Obx] widgets to call `setState()` mid-build,
/// causing the "setState() called during build" assertion.
///
/// All [onSearchChanged] calls that originate **inside a build method** are
/// therefore wrapped in [WidgetsBinding.instance.addPostFrameCallback] so the
/// Rx write is deferred until after the current frame.
///
/// Calls that originate from **user-gesture handlers** (button `onPressed`,
/// `onTap`, etc.) are already outside the build phase and remain synchronous.
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

  // ── Internals ──────────────────────────────────────────────────────────
  // `late` so a local-mode delegate (and the widget tests) never touch GetX:
  // resolving ApiProvider eagerly would throw wherever it isn't registered.
  late final GlobalSearchService _service = Get.put(GlobalSearchService());
  late final ApiProvider _apiProvider = Get.find<ApiProvider>();

  /// Test seam for [_search] — defaults to the live [GlobalSearchService].
  final Future<List<GlobalSearchItem>> Function(String doctype, String query)?
      searcher;

  bool get _isApiMode => doctype.isNotEmpty && targetRoute.isNotEmpty;
  static const _minApiChars = 3;

  final String? recentSearchKey;
  late final RecentSearchHistory _history;

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
    final key = recentSearchKey ?? doctype;
    _history = RecentSearchHistory(
      key.trim().isEmpty ? null : key,
      _isApiMode ? _minApiChars : 1,
      recentSearchStore,
    );
  }

  @override
  String? get searchFieldLabel =>
      _isApiMode ? 'Search $doctype…' : 'Search…';

  // ── Debounced API search ──────────────────────────────────────────────
  //
  // One delegate instance lives for the whole search session (showSearch is
  // called once, per keystroke Flutter re-invokes buildSuggestions on the SAME
  // object), so these fields survive across keystrokes.
  //
  // Without them a fresh Future — and therefore a fresh network round-trip —
  // was created on every build: one request per character typed, plus more for
  // incidental rebuilds (keyboard, theme, filter badge).  Mirrors the debounce
  // already used by GlobalDocumentSearchDelegate.
  Timer? _debounce;
  String? _pendingKey;
  Future<List<GlobalSearchItem>>? _pendingFuture;

  Future<List<GlobalSearchItem>> _search(String q) {
    if (q == _pendingKey && _pendingFuture != null) return _pendingFuture!;
    _pendingKey = q;
    _debounce?.cancel();
    final completer = Completer<List<GlobalSearchItem>>();
    _pendingFuture = completer.future;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        completer.complete(await (searcher ?? _service.search)(doctype, q));
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    });
    return completer.future;
  }

  // ── Helper: post-frame safe notify ────────────────────────────────────
  //
  // Call this from inside build methods (buildSuggestions, buildResults).
  // Defers the Rx write until after the current frame so that Obx widgets
  // are not asked to mark themselves dirty while Flutter is still building.
  void _notifySearchChanged(String value) {
    if (onSearchChanged == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onSearchChanged!(value);
    });
  }

  // ── Actions: clear + filter badge ─────────────────────────────────────

  @override
  List<Widget>? buildActions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return [
      // Clear button — shown whenever there is text in the field.
      // onPressed is a gesture handler, NOT a build method → synchronous call.
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          tooltip: 'Clear search',
          onPressed: () {
            query = '';
            if (onSearchClear != null) {
              onSearchClear!();
            } else if (onSearchChanged != null) {
              onSearchChanged!('');
            }
            showSuggestions(context);
          },
        ),

      // Filter badge button — migrated from SearchBar trailing suffix.
      // onTap is a gesture handler → synchronous call.
      // Only wrap in Obx when there is an RxMap to observe: an Obx whose
      // builder reads no observables (activeFilters == null short-circuits
      // ?.length) throws GetX's improper-use error on first build.
      if (onFilterTap != null && activeFilters == null)
        _filterButton(colorScheme, 0),
      if (onFilterTap != null && activeFilters != null)
        Obx(() => _filterButton(colorScheme, activeFilters!.length)),

      // Camera icon — only shown when caller provides onImageScanResult.
      if (onImageScanResult != null)
        IconButton(
          icon: const Icon(Icons.image_search),
          tooltip: 'Search by image',
          onPressed: () async {
            final result = await ImageScanFlow.run(context);
            if (result != null && context.mounted) {
              close(context, null);
              onImageScanResult!(result);
            }
          },
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
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
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
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  // ── Results & Suggestions ─────────────────────────────────────────────

  @override
  void showResults(BuildContext context) {
    // Flutter's keyboard submit calls this before building the results.
    _history.record(query);
    super.showResults(context);
  }

  @override
  Widget buildResults(BuildContext context) {
    // Called during Flutter's build phase → use post-frame callback.
    _notifySearchChanged(query);

    if (_isApiMode) return _buildApiResults(context);

    // Local mode: close overlay so the filtered list is visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
        close(context, null);
      }
    });
    return const SizedBox.shrink();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    // Called during Flutter's build phase → use post-frame callback.
    _notifySearchChanged(query);

    if (_isApiMode) return _buildApiResults(context);

    return _history.build(
      query: query,
      fallback: _buildLocalHint(context),
      includeHint: query.isNotEmpty,
      onSelect: (context, term) {
        query = term;
        _applyLocalSearch(context);
      },
    );
  }

  void _applyLocalSearch(BuildContext context) {
    _history.record(query);
    onSearchChanged?.call(query);
    close(context, null);
  }

  // ── API result list ───────────────────────────────────────────────────

  Widget _buildApiResults(BuildContext context) {
    if (query.trim().length < _minApiChars) {
      return _history.build(
        query: query,
        fallback: _buildMessageState(
          icon: Icons.search,
          message: 'Type at least $_minApiChars characters',
        ),
        onSelect: (context, term) {
          query = term;
          showResults(context);
        },
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
              _buildResultTile(context, results[index]),
        );
      },
    );
  }

  // ── Local-mode hint ───────────────────────────────────────────────────

  Widget _buildLocalHint(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasQuery = query.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (hasQuery) ...[
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                // onPressed is a gesture handler → synchronous call is fine.
                onPressed: () => _applyLocalSearch(context),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Apply'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────

  Widget _buildResultTile(BuildContext context, GlobalSearchItem item) {
    return ListTile(
      leading: _buildLeadingIcon(item.imageUrl),
      title: Text(
        item.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: item.subtitle != null
          ? Text(item.subtitle!,
              maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: const Icon(Icons.chevron_right),
      // onTap is a gesture handler → synchronous call is fine.
      onTap: () {
        _history.record(query);
        close(context, null);
        // Resolve the argument shape the target form expects — a bare String
        // crashes forms that read Get.arguments['name'] (String's [] wants an
        // int index).
        Get.toNamed(targetRoute,
            arguments: searchNavArgsFor(targetRoute, item.id));
      },
    );
  }

  Widget _buildLeadingIcon(String? imageUrl) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final baseUrl = _apiProvider.baseUrl;
      final fullUrl =
          imageUrl.startsWith('http') ? imageUrl : '$baseUrl$imageUrl';
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
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: isError ? Colors.red.shade300 : Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
                color: isError ? Colors.red : Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _history.dispose();
    super.dispose();
  }
}

/// Backward-compatibility alias.  Any call-site still using
/// [GlobalSearchDelegate] compiles without change.
typedef GlobalSearchDelegate = DocTypeSearchDelegate;

/// Re-opens a list screen's search to edit the active query — what its
/// "Search: …" filter chip does when tapped. Pass the same wiring the
/// screen gives [DocTypeListHeader]; the search bar opens holding the
/// current [searchQuery].
Future<void> editListSearch(
  BuildContext context, {
  required RxString searchQuery,
  String doctype = '',
  String targetRoute = '',
  String? recentSearchKey,
  ValueChanged<String>? onSearchChanged,
  VoidCallback? onSearchClear,
  ValueChanged<ImageScanResult>? onImageScanResult,
}) =>
    showSearch(
      context: context,
      query: searchQuery.value,
      delegate: DocTypeSearchDelegate(
        doctype: doctype,
        targetRoute: targetRoute,
        recentSearchKey: listRecentSearchKey(context, recentSearchKey, doctype),
        searchQuery: searchQuery,
        onSearchChanged: onSearchChanged,
        onSearchClear: onSearchClear,
        onImageScanResult: onImageScanResult,
      ),
    );
