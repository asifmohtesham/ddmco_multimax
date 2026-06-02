import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

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

  // ── Internals ──────────────────────────────────────────────────────────
  final GlobalSearchService _service = Get.put(GlobalSearchService());
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  bool get _isApiMode => doctype.isNotEmpty && targetRoute.isNotEmpty;

  DocTypeSearchDelegate({
    this.doctype = '',
    this.targetRoute = '',
    this.searchQuery,
    this.onSearchChanged,
    this.onSearchClear,
    this.activeFilters,
    this.onFilterTap,
  });

  @override
  String? get searchFieldLabel =>
      _isApiMode ? 'Search $doctype…' : 'Search…';

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
      if (onFilterTap != null)
        Obx(() {
          final count = activeFilters?.length ?? 0;
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
                              minWidth: 16, minHeight: 16),
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
        }),
    ];
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
  Widget buildResults(BuildContext context) {
    // Called during Flutter's build phase → use post-frame callback.
    _notifySearchChanged(query);

    if (_isApiMode) return _buildApiResults(context);

    // Local mode: close overlay so the filtered list is visible.
    WidgetsBinding.instance.addPostFrameCallback((_) => close(context, null));
    return const SizedBox.shrink();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    // Called during Flutter's build phase → use post-frame callback.
    _notifySearchChanged(query);

    if (_isApiMode) {
      if (query.trim().length < 3) {
        return _buildMessageState(
          icon: Icons.search,
          message: 'Type at least 3 characters',
        );
      }
      return _buildApiResults(context);
    }

    // Local mode: show a hint card — the list behind updates live.
    return _buildLocalHint(context);
  }

  // ── API result list ───────────────────────────────────────────────────

  Widget _buildApiResults(BuildContext context) {
    if (query.trim().length < 3) {
      return _buildMessageState(
        icon: Icons.search,
        message: 'Type at least 3 characters',
      );
    }

    return FutureBuilder<List<GlobalSearchItem>>(
      future: _service.search(doctype, query),
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
                onPressed: () {
                  if (onSearchChanged != null) onSearchChanged!(query);
                  close(context, null);
                },
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
        close(context, null);
        Get.toNamed(targetRoute, arguments: item.id);
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
}

/// Backward-compatibility alias.  Any call-site still using
/// [GlobalSearchDelegate] compiles without change.
typedef GlobalSearchDelegate = DocTypeSearchDelegate;
