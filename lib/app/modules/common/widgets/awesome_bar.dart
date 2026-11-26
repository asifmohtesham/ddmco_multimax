import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/modules/common/controllers/awesome_bar_controller.dart';
import 'package:flutter_html/flutter_html.dart';

class AwesomeBar extends StatefulWidget {
  const AwesomeBar({super.key, this.onScanRepeat});

  /// Set on Dashboard, where scans appear in RECENT and can be repeated.
  final Future<void> Function(String code)? onScanRepeat;

  @override
  State<AwesomeBar> createState() => _AwesomeBarState();
}

enum _RecentAction {
  scanAgain('Scan again', Icons.replay),
  editAndScan('Edit code and scan', Icons.edit_outlined),
  searchAsText('Search for this code', Icons.search),
  openItem('Open item', Icons.open_in_new),
  copyCode('Copy code', Icons.copy),
  open('Open', Icons.open_in_new),
  searchAgain('Search again', Icons.search),
  remove('Remove from recent', Icons.delete_outline);

  const _RecentAction(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _AwesomeBarState extends State<AwesomeBar> {
  final AwesomeBarController controller = Get.put(AwesomeBarController());
  int _lastOpenedScanRevision = 0;

  bool get _onDashboard => widget.onScanRepeat != null;

  @override
  Widget build(BuildContext context) {
    return SearchAnchor(
      viewOnSubmitted: controller.onQuerySubmitted,
      builder: (BuildContext context, SearchController searchController) {
        return IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search or type a command',
          onPressed: () {
            if (_onDashboard) {
              final revision = AwesomeBarRecentStore.scanRevision;
              if (revision != _lastOpenedScanRevision) {
                searchController.clear();
                _lastOpenedScanRevision = revision;
              }
            }
            searchController.openView();
          },
        );
      },
      suggestionsBuilder:
          (BuildContext context, SearchController searchController) async {
            controller.onSearchQueryChanged(searchController.text);
            return [Obx(() => _buildSuggestions(context, searchController))];
          },
    );
  }

  Widget _buildSuggestions(BuildContext context, SearchController search) {
    final loading = controller.isLoading.value;
    final options = controller.options.toList();
    if (search.text.trim().isEmpty) return _buildRecents(context, search);
    if (options.isEmpty && !loading) {
      return _buildEmptyHints(context, noResults: true);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A fixed-height slot, so results don't shift when loading ends.
        SizedBox(
          height: 4,
          child: loading
              ? const LinearProgressIndicator(semanticsLabel: 'Searching')
              : null,
        ),
        if (loading && options.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Searching…',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.scheme.textMuted),
            ),
          ),
        for (final (index, option) in options.indexed) ...[
          if (index == 0 || options[index - 1].type != option.type)
            _sectionHeader(context, option.type.toUpperCase()),
          _buildOptionTile(context, search, option),
        ],
      ],
    );
  }

  Widget _buildRecents(BuildContext context, SearchController search) {
    final recents = controller.recentOptions
        .where((option) => !option.isScan || _onDashboard)
        .toList();
    if (recents.isEmpty) return _buildEmptyHints(context, noResults: false);

    final now = AwesomeBarRecentStore.clock();
    final groups = [
      for (final option in recents) recentDayGroup(option.recordedAt, now),
    ];
    final showGroups = groups.toSet().length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, right: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Centred against Clear all, so no vertical padding here.
              _sectionHeader(
                context,
                'RECENT',
                padding: const EdgeInsets.only(left: 16),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: context.scheme.text,
                ),
                onPressed: () => _confirmClear(context),
                child: const Text('Clear all'),
              ),
            ],
          ),
        ),
        for (final (index, option) in recents.indexed) ...[
          if (showGroups && (index == 0 || groups[index - 1] != groups[index]))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                groups[index].label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: context.scheme.textMuted,
                ),
              ),
            ),
          _buildRecentTile(context, search, option, now),
        ],
      ],
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    String text, {
    EdgeInsets padding = const EdgeInsets.fromLTRB(16, 16, 16, 4),
  }) => Padding(
    padding: padding,
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
        // The accent falls below 4.5:1 on the search view's surface for some
        // accents (dark Maroon, light Blue and Purple); muted ink never does.
        color: context.scheme.textMuted,
      ),
    ),
  );

  bool _failed(AwesomeBarOption option) =>
      option.isScan && option.scanOutcome != ScanOutcome.ok;

  Widget _buildRecentTile(
    BuildContext context,
    SearchController search,
    AwesomeBarOption option,
    DateTime now,
  ) {
    final scheme = context.scheme;
    final failed = _failed(option);
    final failColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.red300
        : AppColors.red700;
    final subtitle = [
      if (option.description case final text? when text.isNotEmpty) text,
      if (option.recordedAt case final at?) recentTimeLabel(at, now),
    ].join(' · ');

    final Widget leading;
    if (option.isQuery) {
      leading = Icon(Icons.manage_search, color: scheme.textSubtle, size: 20);
    } else if (option.icon != null) {
      leading = Icon(
        option.icon,
        color: failed ? failColor : option.color ?? scheme.primary,
        size: 20,
      );
    } else {
      leading = Icon(Icons.history, color: scheme.textSubtle, size: 20);
    }

    return ListTile(
      leading: leading,
      title: option.isScan || option.isQuery
          ? Text(option.label, style: TextStyle(color: scheme.text))
          : _htmlLabel(context, option.label),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: failed ? failColor : scheme.textMuted,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (failed)
            IconButton(
              icon: Icon(Icons.edit_outlined, color: scheme.textMuted),
              tooltip: _RecentAction.editAndScan.label,
              onPressed: () => _editAndScan(context, search, option),
            ),
          IconButton(
            icon: Icon(Icons.close, color: scheme.textSubtle),
            tooltip: _RecentAction.remove.label,
            onPressed: () => unawaited(AwesomeBarRecentStore.remove(option)),
          ),
        ],
      ),
      onTap: () => _openRecent(search, option),
      onLongPress: () => _showRecentActions(context, search, option),
    );
  }

  Widget _buildOptionTile(
    BuildContext context,
    SearchController search,
    AwesomeBarOption option,
  ) {
    final scheme = context.scheme;
    return ListTile(
      leading: option.icon != null
          ? Icon(option.icon, color: option.color ?? scheme.primary, size: 20)
          : null,
      title: _htmlLabel(context, option.label),
      subtitle: option.description != null
          ? Text(
              option.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.textMuted),
            )
          : null,
      onTap: () {
        search.closeView(option.value);
        controller.onOptionSelected(option);
      },
    );
  }

  Widget _htmlLabel(BuildContext context, String label) => Html(
    data: label,
    style: {
      "body": Style(
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
        color: context.scheme.text,
      ),
      // Bold alone marks the match: the accent isn't readable enough on
      // this surface for every accent.
      "b": Style(fontWeight: FontWeight.w800, color: context.scheme.text),
    },
  );

  void _openRecent(SearchController search, AwesomeBarOption option) {
    if (option.isQuery) {
      _searchFor(search, option.value);
      controller.onQuerySubmitted(option.value);
      return;
    }
    if (option.isScan) {
      _repeatScan(search, option.value);
      return;
    }
    search.closeView(option.value);
    controller.onOptionSelected(option);
  }

  void _repeatScan(SearchController search, String code) {
    final repeat = widget.onScanRepeat;
    if (repeat == null || !search.isOpen) return;
    search.closeView('');
    unawaited(repeat(code));
  }

  void _searchFor(SearchController search, String text) {
    search.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _editAndScan(
    BuildContext context,
    SearchController search,
    AwesomeBarOption option,
  ) async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => _EditCodeDialog(initial: option.value),
    );
    if (code == null || code.trim().isEmpty) return;
    _repeatScan(search, code.trim());
  }

  List<_RecentAction> _actionsFor(AwesomeBarOption option) {
    if (option.isQuery) {
      return const [_RecentAction.searchAgain, _RecentAction.remove];
    }
    if (!option.isScan) return const [_RecentAction.open, _RecentAction.remove];
    return [
      _RecentAction.scanAgain,
      _RecentAction.editAndScan,
      if (option.itemCode != null && searchTargetForDoctype('Item') != null)
        _RecentAction.openItem,
      _RecentAction.searchAsText,
      _RecentAction.copyCode,
      _RecentAction.remove,
    ];
  }

  Future<void> _showRecentActions(
    BuildContext context,
    SearchController search,
    AwesomeBarOption option,
  ) async {
    final scheme = context.scheme;
    final action = await showModalBottomSheet<_RecentAction>(
      context: context,
      backgroundColor: scheme.fg,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                option.isScan || option.isQuery ? option.label : option.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleMedium?.copyWith(color: scheme.text),
              ),
            ),
            for (final action in _actionsFor(option))
              ListTile(
                leading: Icon(action.icon, color: scheme.textMuted),
                title: Text(action.label, style: TextStyle(color: scheme.text)),
                onTap: () => Navigator.pop(sheetContext, action),
              ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case _RecentAction.scanAgain:
        _repeatScan(search, option.value);
      case _RecentAction.editAndScan:
        await _editAndScan(context, search, option);
      case _RecentAction.searchAsText:
        _searchFor(search, option.value.trim());
      case _RecentAction.openItem:
        final target = searchTargetForDoctype('Item');
        final code = option.itemCode;
        if (target == null || code == null || !search.isOpen) return;
        search.closeView('');
        Get.toNamed(target.route, arguments: target.argsFor(code));
      case _RecentAction.copyCode:
        await Clipboard.setData(ClipboardData(text: option.value.trim()));
      case _RecentAction.open:
        _openRecent(search, option);
      case _RecentAction.searchAgain:
        _openRecent(search, option);
      case _RecentAction.remove:
        await AwesomeBarRecentStore.remove(option);
    }
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear recent?'),
        content: Text(
          _onDashboard
              ? 'Your recent scans and searches will be removed from this device.'
              : 'Your recent searches will be removed from this device.',
        ),
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
    if (confirm != true) return;
    // Outside Dashboard, scans are hidden, so they are kept.
    await AwesomeBarRecentStore.clear(
      where: _onDashboard ? null : (option) => !option.isScan,
    );
  }

  Widget _buildEmptyHints(BuildContext context, {required bool noResults}) {
    final scheme = context.scheme;
    final (icon, title, hint) = noResults
        ? (
            Icons.search_off,
            'No results found',
            'Try searching for an ID, a Doctype (e.g. "Delivery Note"), "New Task", or evaluate expressions like "2 + 2".',
          )
        : _onDashboard
        ? (
            Icons.search,
            'Search or scan',
            'Your scans from the field below and your searches will show here. Type an ID, a list such as "Delivery Note", "New Task", or a sum like "2 + 2".',
          )
        : (
            Icons.search,
            'Search or type a command',
            'Type an ID, a list such as "Delivery Note", "New Task", or a sum like "2 + 2".',
          );
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.textSubtle),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: scheme.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.textMuted),
          ),
        ],
      ),
    );
  }
}

class _EditCodeDialog extends StatefulWidget {
  const _EditCodeDialog({required this.initial});

  final String initial;

  @override
  State<_EditCodeDialog> createState() => _EditCodeDialogState();
}

class _EditCodeDialogState extends State<_EditCodeDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial.trim(),
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _text.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit code'),
      content: TextField(
        controller: _text,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Barcode or rack code'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Scan')),
      ],
    );
  }
}
