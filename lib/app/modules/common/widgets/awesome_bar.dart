import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/common/controllers/awesome_bar_controller.dart';
import 'package:flutter_html/flutter_html.dart';

class AwesomeBar extends StatelessWidget {
  AwesomeBar({Key? key}) : super(key: key);

  final AwesomeBarController controller = Get.put(AwesomeBarController());

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

            if (controller.options.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No results found.'),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: controller.options.length,
              itemBuilder: (context, index) {
                final option = controller.options[index];
                final showHeader = index == 0 || controller.options[index - 1].type != option.type;
                
                final listTile = ListTile(
                  title: Html(
                    data: option.label,
                    style: {
                      "body": Style(
                        margin: Margins.zero,
                        padding: HtmlPaddings.zero,
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
}
