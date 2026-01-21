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

  void initSearch(String doctype) {
    // Clear previous state and load initial list (empty query)
    searchQuery.value = '';
    _performSearch('', overrideDoctype: doctype);
  }

  // We need to store doctype locally for the worker to access it,
  // or pass it dynamically. Simpler to store it when initialized.
  String? _currentDoctype;

  Future<void> _performSearch(String query, {String? overrideDoctype}) async {
    if (overrideDoctype != null) _currentDoctype = overrideDoctype;
    if (_currentDoctype == null) return;

    isLoading.value = true;
    try {
      final items = await _service.search(_currentDoctype!, query);
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
    // Use a unique tag for the controller to support multiple link fields on one screen
    final String controllerTag = "LinkField_$label";

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
    // Initialize (or find) the controller with a unique tag
    final controller = Get.put(LinkFieldController(), tag: tag);

    // Reset and Load Initial Data
    controller.initSearch(doctype);

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
              // Update controller's reactive variable
              onChanged: (val) => controller.searchQuery.value = val,
            ),
            const SizedBox(height: 12),

            // Reactive List Results
            Expanded(
              child: Obx(() {
                if (controller.isLoading.value) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (controller.results.isEmpty) {
                  return Center(
                    child: Text(
                      "No results found",
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: controller.results.length,
                  separatorBuilder: (c, i) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = controller.results[index];
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
                      onTap: () {
                        onChanged(item.id);
                        Get.back(); // Close Sheet
                        // Ideally delete controller to free memory,
                        // though GetX smart management usually handles this if bound to routes.
                        // For bottom sheets, explicit delete is safer if the tag is unique per field.
                        Get.delete<LinkFieldController>(tag: tag);
                      },
                      trailing: const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Colors.grey,
                      ),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    ).whenComplete(() {
      // Ensure controller is cleaned up when sheet is closed via drag/back
      Get.delete<LinkFieldController>(tag: tag);
    });
  }
}
