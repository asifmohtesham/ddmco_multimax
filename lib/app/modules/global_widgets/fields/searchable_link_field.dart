import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

class SearchableLinkField extends StatelessWidget {
  final String label;
  final String? value;
  final String doctype;
  final Function(dynamic) onChanged;
  final bool readOnly;
  final Map<String, dynamic>? filters;

  const SearchableLinkField({
    super.key,
    required this.label,
    required this.value,
    required this.doctype,
    required this.onChanged,
    this.readOnly = false,
    this.filters,
  });

  @override
  Widget build(BuildContext context) {
    // Controller for the display field
    final textController = TextEditingController(text: value);
    // Ensure controller stays synced if parent updates value
    if (value != textController.text) {
      textController.text = value ?? '';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        controller: textController,
        readOnly: true,
        // Prevent manual typing, force selection via Sheet
        canRequestFocus: false,
        // Prevent keyboard from popping up on main screen
        onTap: readOnly
            ? null
            : () {
                _showSearchBottomSheet(context);
              },
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
          filled: readOnly,
          fillColor: readOnly ? Colors.grey[100] : null,
          hintText: "Tap to select $doctype",
        ),
      ),
    );
  }

  void _showSearchBottomSheet(BuildContext context) {
    Get.bottomSheet(
      _SearchBottomSheetContent(
        doctype: doctype,
        onSelected: (val) {
          onChanged(val);
          Get.back(); // Close sheet
        },
      ),
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );
  }
}

// --- Private Widget for Bottom Sheet Content ---
// Uses internal state to manage the search query and list updates independently
class _SearchBottomSheetContent extends StatefulWidget {
  final String doctype;
  final Function(String) onSelected;

  const _SearchBottomSheetContent({
    required this.doctype,
    required this.onSelected,
  });

  @override
  State<_SearchBottomSheetContent> createState() =>
      _SearchBottomSheetContentState();
}

class _SearchBottomSheetContentState extends State<_SearchBottomSheetContent> {
  final GlobalSearchService _service = Get.find<GlobalSearchService>();
  final TextEditingController _searchController = TextEditingController();
  List<GlobalSearchItem> _results = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Load initial data (optional, or wait for type)
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _search(query);
    });
  }

  Future<void> _search(String query) async {
    setState(() => _isLoading = true);
    try {
      final results = await _service.search(widget.doctype, query);
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate height: 85% of screen height max
    final height = MediaQuery.of(context).size.height * 0.85;

    return Container(
      height: height,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Select ${widget.doctype}",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Get.back(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Search Bar
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: "Search...",
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 12),

          // List Results
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                ? Center(
                    child: Text(
                      "No results found",
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (c, i) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _results[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          item.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle:
                            item.subtitle != null && item.subtitle != item.title
                            ? Text(
                                item.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        onTap: () => widget.onSelected(item.id),
                        trailing: const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: Colors.grey,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
