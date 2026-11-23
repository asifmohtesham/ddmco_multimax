import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/services/recent_searches.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';

/// Overrides both storage and identity for tests that run without GetX.
typedef RecentSearchStore = ({StorageService storage, String user});

/// Resolve the source screen's key before opening the search route.
String? listRecentSearchKey(
  BuildContext context,
  String? override,
  String? doctype,
) {
  final route = ModalRoute.of(context)?.settings.name;
  for (final key in [override, doctype, route, Get.currentRoute]) {
    if (key != null && key.trim().isNotEmpty) return key;
  }
  return null;
}

/// The history for one search overlay. Storage reads and in-memory writes
/// are synchronous. Disk flushes are independent of the search interaction.
class RecentSearchHistory {
  RecentSearchHistory(this.contextKey, this.minLength, this.testStore);

  final String? contextKey;
  final int minLength;
  final RecentSearchStore? testStore;
  RecentSearchStore? _loadedStore;
  ValueNotifier<List<String>>? _entries;

  AuthenticationController? get _auth =>
      Get.isRegistered<AuthenticationController>()
      ? Get.find<AuthenticationController>()
      : null;

  String? get _user => testStore?.user ?? _auth?.currentUser.value?.email;

  StorageService? get _storage =>
      testStore?.storage ??
      (Get.isRegistered<StorageService>() ? Get.find<StorageService>() : null);

  ValueNotifier<List<String>> _entriesFor(
    StorageService storage,
    String key,
    String user,
  ) {
    final store = (storage: storage, user: user);
    if (_loadedStore != store) {
      _loadedStore = store;
      // The old builder detaches from its notifier when the account changes.
      _entries = ValueNotifier(storage.getRecentSearches(key, user));
    }
    return _entries!;
  }

  Future<void> _mutate(
    String? user,
    Future<void> Function(StorageService, String, String) write,
  ) async {
    try {
      final key = contextKey;
      if (key == null || user == null || user.isEmpty || user != _user) return;
      final storage = _storage;
      if (storage == null) return;
      final pending = write(storage, key, user);
      // GetStorage updates its memory before returning the disk-write future.
      try {
        _entriesFor(storage, key, user).value = storage.getRecentSearches(
          key,
          user,
        );
      } finally {
        await pending;
      }
    } catch (error, stack) {
      developer.log(
        'Could not update recent searches',
        name: 'RecentSearchHistory',
        error: error,
        stackTrace: stack,
      );
    }
  }

  void record(String query) {
    if (contextKey == null) return;
    unawaited(
      _mutate(
        _user,
        (storage, key, user) =>
            storage.addRecentSearch(key, user, query, minLength: minLength),
      ),
    );
  }

  Widget build({
    required String query,
    required Widget fallback,
    required void Function(BuildContext, String) onSelect,
    bool includeHint = false,
  }) {
    final key = contextKey;
    if (key == null) return fallback;

    Widget forUser() {
      final user = _user;
      if (user == null || user.isEmpty) return fallback;
      final storage = _storage;
      if (storage == null) return fallback;

      return ValueListenableBuilder<List<String>>(
        valueListenable: _entriesFor(storage, key, user),
        builder: (context, entries, _) {
          final filter = RecentSearches.normalize(query).toLowerCase();
          final matches = entries
              .where((term) => term.toLowerCase().contains(filter))
              .toList();
          if (matches.isEmpty) return fallback;

          final scheme = context.scheme;
          return _RecentSearchList(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent searches',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: scheme.textMuted),
                    ),
                    TextButton(
                      onPressed: () => _confirmClear(context, user),
                      child: const Text('Clear all'),
                    ),
                  ],
                ),
              ),
              for (final term in matches)
                ListTile(
                  leading: Icon(Icons.history, color: scheme.textSubtle),
                  title: Text(
                    term,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.text),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.close, color: scheme.textSubtle),
                    tooltip: 'Remove from recent searches',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () => unawaited(
                      _mutate(
                        user,
                        (storage, key, user) =>
                            storage.removeRecentSearch(key, user, term),
                      ),
                    ),
                  ),
                  onTap: () {
                    if (_user == user) onSelect(context, term);
                  },
                ),
              if (includeHint) fallback,
            ],
          );
        },
      );
    }

    return testStore == null && _auth != null ? Obx(forUser) : forUser();
  }

  Future<void> _confirmClear(BuildContext context, String user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear recent searches?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await _mutate(
        user,
        (storage, key, user) => storage.clearRecentSearches(key, user),
      );
    }
  }

  void dispose() => _entries?.dispose();
}

class _RecentSearchList extends StatefulWidget {
  const _RecentSearchList({required this.children});

  final List<Widget> children;

  @override
  State<_RecentSearchList> createState() => _RecentSearchListState();
}

class _RecentSearchListState extends State<_RecentSearchList> {
  // SearchDelegate animates between suggestion and result bodies, so both can
  // contain scroll views during the transition.
  final _scroll = ScrollController();

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _scroll,
    child: ListView(
      controller: _scroll,
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      children: widget.children,
    ),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }
}
