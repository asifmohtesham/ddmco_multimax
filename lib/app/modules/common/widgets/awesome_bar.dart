import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/modules/common/controllers/awesome_bar_controller.dart';
import 'package:flutter_html/flutter_html.dart';

class AwesomeBar extends StatefulWidget {
  const AwesomeBar({super.key, this.onScanRepeat});

  final Future<void> Function(String code)? onScanRepeat;

  @override
  State<AwesomeBar> createState() => _AwesomeBarState();
}

class _AwesomeBarState extends State<AwesomeBar> {
  final AwesomeBarController controller = Get.put(AwesomeBarController());
  int _lastOpenedScanRevision = 0;

  Widget _buildScanTile(
    BuildContext context,
    SearchController searchController,
    AwesomeBarOption option,
    Future<void> Function(String code) repeat,
  ) {
    final scheme = context.scheme;
    final failed = option.scanOutcome != ScanOutcome.ok;
    final statusColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.red300
        : AppColors.red700;

    return ListTile(
      leading: Icon(
        option.icon,
        color: failed ? statusColor : option.color ?? scheme.primary,
        size: 20,
      ),
      title: Text(option.label, style: TextStyle(color: scheme.text)),
      subtitle: Text(
        option.description ?? '',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: failed ? statusColor : scheme.textMuted,
        ),
      ),
      onTap: () {
        if (!searchController.isOpen) return;
        searchController.closeView('');
        unawaited(repeat(option.value));
      },
    );
  }

  Widget _buildOptionTile(
    BuildContext context,
    SearchController searchController,
    AwesomeBarOption option,
    bool isRecent,
  ) {
    return ListTile(
      leading: option.icon != null
          ? Icon(
              option.icon,
              color: option.color ?? Theme.of(context).colorScheme.primary,
              size: 20,
            )
          : (isRecent ? const Icon(Icons.history, size: 20) : null),
      title: Html(
        data: option.label,
        style: {
          "body": Style(margin: Margins.zero, padding: HtmlPaddings.zero),
          "b": Style(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        },
      ),
      subtitle: option.description != null
          ? Text(
              option.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            )
          : null,
      onTap: () {
        searchController.closeView(option.value);
        controller.onOptionSelected(option);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SearchAnchor(
      builder: (BuildContext context, SearchController searchController) {
        return IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search or type a command',
          onPressed: () {
            if (widget.onScanRepeat != null) {
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
            // Pass the query to the AwesomeBarController
            controller.onSearchQueryChanged(searchController.text);

            return [
              Obx(() {
                if (controller.isLoading.value) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                // Empty State Handling
                final options = controller.options.toList();
                if (options.isEmpty) {
                  if (searchController.text.trim().isEmpty) {
                    final repeat = widget.onScanRepeat;
                    final recents = controller.recentOptions
                        .where((option) => !option.isScan || repeat != null)
                        .toList();
                    if (recents.isEmpty) return _buildEmptyHints(context);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(
                            'RECENT',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        for (final option in recents)
                          if (option.isScan && repeat != null)
                            _buildScanTile(
                              context,
                              searchController,
                              option,
                              repeat,
                            )
                          else
                            _buildOptionTile(
                              context,
                              searchController,
                              option,
                              true,
                            ),
                      ],
                    );
                  } else {
                    return _buildEmptyHints(context);
                  }
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options[index];
                    final showHeader =
                        index == 0 || options[index - 1].type != option.type;

                    final listTile = _buildOptionTile(
                      context,
                      searchController,
                      option,
                      false,
                    );

                    if (showHeader) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                            child: Text(
                              option.type.toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          listTile,
                        ],
                      );
                    }

                    return listTile;
                  },
                );
              }),
            ];
          },
    );
  }

  Widget _buildEmptyHints(BuildContext context) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48, color: scheme.textSubtle),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: scheme.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try searching for an ID, a Doctype (e.g. "Delivery Note"), "New Task", or evaluate expressions like "2 + 2".',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.textMuted),
          ),
        ],
      ),
    );
  }
}
