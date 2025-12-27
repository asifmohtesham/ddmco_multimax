import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

class GlobalSearchDelegate extends SearchDelegate {
  final String doctype;
  final String targetRoute;

  // Lazy load the service (ensure it's available)
  final GlobalSearchService _service = Get.put(GlobalSearchService());
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  GlobalSearchDelegate({
    required this.doctype,
    required this.targetRoute,
  });

  @override
  String? get searchFieldLabel => 'Search $doctype...';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults();

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults();

  Widget _buildSearchResults() {
    if (query.trim().length < 3) {
      return _buildMessageState(
        icon: Icons.search,
        message: "Type at least 3 characters",
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
            message: "Search failed. Please try again.",
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
          itemBuilder: (context, index) => _buildResultTile(context, results[index]),
        );
      },
    );
  }

  Widget _buildResultTile(BuildContext context, GlobalSearchItem item) {
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
        close(context, null);
        Get.toNamed(targetRoute, arguments: item.id);
      },
    );
  }

  Widget _buildLeadingIcon(String? imageUrl) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final baseUrl = _apiProvider.baseUrl;
      final fullUrl = imageUrl.startsWith('http') ? imageUrl : '$baseUrl$imageUrl';

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

  Widget _buildMessageState({required IconData icon, required String message, bool isError = false}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: isError ? Colors.red.shade300 : Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: isError ? Colors.red : Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}