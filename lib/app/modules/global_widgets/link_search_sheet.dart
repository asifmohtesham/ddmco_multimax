import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

/// Debounced search-as-you-type picker over a Link doctype's names.
/// Extracted from the POS & DN Item Rate / BOM Stock report filter sheets.
Future<void> showLinkSearchSheet({
  required String doctype,
  required String title,
  required ValueChanged<String> onSelected,
}) =>
    Get.bottomSheet(
      LinkSearchSheet(
        title: title,
        onSearch: (q) =>
            Get.find<ApiProvider>().searchLinkOptions(doctype, query: q),
        onSelected: onSelected,
      ),
      isScrollControlled: true,
    );

class LinkSearchSheet extends StatefulWidget {
  final String title;
  final Future<List<String>> Function(String query) onSearch;
  final ValueChanged<String> onSelected;
  const LinkSearchSheet({
    super.key,
    required this.title,
    required this.onSearch,
    required this.onSelected,
  });

  @override
  State<LinkSearchSheet> createState() => _LinkSearchSheetState();
}

class _LinkSearchSheetState extends State<LinkSearchSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<String> _options = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run('');
    _searchCtrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(
          const Duration(milliseconds: 300), () => _run(_searchCtrl.text));
    });
  }

  Future<void> _run(String q) async {
    setState(() => _loading = true);
    final results = await widget.onSearch(q);
    if (!mounted) return;
    setState(() {
      _options = results;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Text(widget.title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _options.isEmpty
                    ? const Center(child: Text('No matches'))
                    : Material(
                        color: Colors.transparent,
                        child: ListView.separated(
                          itemCount: _options.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (ctx, i) => ListTile(
                            title: Text(_options[i]),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              widget.onSelected(_options[i]);
                            },
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
