import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

// --- Controller for managing search state ---
class LinkFieldController extends GetxController {
  final GlobalSearchService _service = Get.find<GlobalSearchService>();

  var searchQuery = ''.obs;
  var results = <GlobalSearchItem>[].obs;
  var isLoading = false.obs;

  // Worker to handle debounce automatically
  Worker? _debounceWorker;
  String? _currentDoctype;
  Map<String, dynamic>? _currentFilters;

  @override
  void onInit() {
    super.onInit();
    // Debounce the search execution by 300ms
    _debounceWorker = debounce(
      searchQuery,
      (query) => _performSearch(query as String),
      time: const Duration(milliseconds: 300),
    );
  }

  // Initialize with filters
  void initSearch(String doctype, {Map<String, dynamic>? filters}) {
    _currentDoctype = doctype;
    _currentFilters = filters;
    searchQuery.value = '';
    _performSearch('');
  }

  Future<void> _performSearch(String query) async {
    if (_currentDoctype == null) return;

    isLoading.value = true;
    try {
      // Use searchLink to support filters
      final items = await _service.searchLink(
        _currentDoctype!,
        query,
        filters: _currentFilters,
      );
      results.assignAll(items);
    } catch (e) {
      print("LinkField Search Error: $e");
      results.clear();
    } finally {
      isLoading.value = false;
    }
  }

  @override
  void onClose() {
    _debounceWorker?.dispose();
    super.onClose();
  }
}

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
    // Unique tag including hash of filters to differentiate same-field instances if needed
    final String controllerTag = "LinkField_${label}_${filters.hashCode}";

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
              _showSearchBottomSheet(context, controllerTag);
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

  void _showSearchBottomSheet(BuildContext context, String tag) {
    // Initialise (or find) the controller with a unique tag
    final controller = Get.put(LinkFieldController(), tag: tag);
    // Pass filters during initialization
    controller.initSearch(doctype, filters: filters);

    Get.bottomSheet(
      Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
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
                  "Select $doctype",
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
              autofocus: true,
              decoration: InputDecoration(
                hintText: "Search...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              // Update controller's reactive variable
              onChanged: (val) => controller.searchQuery.value = val,
            ),
            const SizedBox(height: 12),

            // Reactive List Results
            Expanded(
              child: Obx(() {
                if (controller.isLoading.value) return const Center(child: CircularProgressIndicator());
                if (controller.results.isEmpty) return const Center(child: Text("No results found"));
                return ListView.separated(
                  itemCount: controller.results.length,
                  separatorBuilder: (c, i) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = controller.results[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: item.subtitle != null ? Text(item.subtitle!, maxLines: 1) : null,
                      onTap: () {
                        onChanged(item.id);
                        Get.back();
                      },
                      trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    ).whenComplete(() => Get.delete<LinkFieldController>(tag: tag));
  }
}