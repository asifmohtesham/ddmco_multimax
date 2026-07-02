import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

/// Dashboard-wide search across every routed doctype.
///
/// Fans [GlobalSearchService.searchAll] out over the permitted targets and
/// renders the hits grouped by doctype. Tapping a hit opens that document's
/// form with the arguments the form expects ([GlobalSearchTarget.argsFor]).
///
/// Deliberately separate from [DocTypeSearchDelegate] (which 11 list screens
/// depend on) so this stays single-purpose and that one stays stable.
class GlobalDocumentSearchDelegate extends SearchDelegate<void> {
  GlobalDocumentSearchDelegate({GlobalSearchService? service})
      : _providedService = service;

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

  static const int _kMinChars = 3;

  // ── Debounced search (delegate instance persists across keystrokes) ──────
  Timer? _debounce;
  String? _pendingQuery;
  Future<List<GlobalSearchGroup>>? _pendingFuture;

  Future<List<GlobalSearchGroup>> _search(String q) {
    if (q == _pendingQuery && _pendingFuture != null) return _pendingFuture!;
    _pendingQuery = q;
    _debounce?.cancel();
    final completer = Completer<List<GlobalSearchGroup>>();
    _pendingFuture = completer.future;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        completer.complete(await _service.searchAll(q));
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
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildBody(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildBody(context);

  Widget _buildBody(BuildContext context) {
    if (query.trim().length < _kMinChars) {
      return _messageState(
        context,
        icon: Icons.search,
        message: 'Type at least $_kMinChars characters',
      );
    }
    return FutureBuilder<List<GlobalSearchGroup>>(
      future: _search(query.trim()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
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
        return buildResultsList(
          context,
          groups,
          (target, item) {
            close(context, null);
            Get.toNamed(target.route, arguments: target.argsFor(item.id));
          },
        );
      },
    );
  }

  /// Flat scroll list: a header row per group, then its result rows.
  @visibleForTesting
  Widget buildResultsList(
    BuildContext context,
    List<GlobalSearchGroup> groups,
    void Function(GlobalSearchTarget target, GlobalSearchItem item) onTap,
  ) {
    final scheme = context.scheme;
    final children = <Widget>[];
    for (final group in groups) {
      children.add(_sectionHeader(context, group.target));
      for (final item in group.items) {
        children.add(_resultTile(context, group.target, item, onTap));
      }
    }
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
    if (imageUrl != null && imageUrl.isNotEmpty) {
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
