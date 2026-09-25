import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/common/controllers/awesome_bar_controller.dart';
import 'package:flutter_html/flutter_html.dart';

class AwesomeBar extends StatelessWidget {
  AwesomeBar({Key? key}) : super(key: key);

  final AwesomeBarController controller = Get.put(AwesomeBarController());

  Widget _buildOptionTile(BuildContext context, SearchController searchController, AwesomeBarOption option, bool isRecent) {
    return ListTile(
      leading: option.icon != null 
          ? Icon(option.icon, color: option.color ?? Theme.of(context).colorScheme.primary, size: 20)
          : (isRecent ? const Icon(Icons.history, size: 20) : null),
      title: Html(
        data: option.label,
        style: {
          "body": Style(
            margin: Margins.zero,
            padding: HtmlPaddings.zero,
          ),
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
            if (controller.options.isEmpty) {
              if (searchController.text.trim().isEmpty) {
                // Show Recent Searches
                if (controller.recentOptions.isEmpty) {
                   return _buildEmptyHints(context);
                }
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
                    ...controller.recentOptions.map((opt) => _buildOptionTile(context, searchController, opt, true)),
                  ],
                );
              } else {
                return _buildEmptyHints(context);
              }
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: controller.options.length,
              itemBuilder: (context, index) {
                final option = controller.options[index];
                final showHeader = index == 0 || controller.options[index - 1].type != option.type;
                
                final listTile = _buildOptionTile(context, searchController, option, false);

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
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48, color: Colors.grey.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text(
            'No results found',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try searching for an ID, a Doctype (e.g. "Delivery Note"), "New Task", or evaluate expressions like "2 + 2".',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
