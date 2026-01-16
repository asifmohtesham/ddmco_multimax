import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/controllers/frappe_form_controller.dart';
import 'package:multimax/models/frappe_field_config.dart';
import 'package:multimax/theme/frappe_theme.dart';

class FrappeLinkField extends StatelessWidget {
  final FrappeFieldConfig config;
  final FrappeFormController controller;

  const FrappeLinkField({super.key, required this.config, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Get current value safely
      final val = controller.data[config.fieldname]?.toString() ?? '';

      return InkWell(
        onTap: config.readOnly ? null : () => _showSearchSheet(context),
        child: InputDecorator(
          decoration: FrappeTheme.inputDecoration(config.label).copyWith(
            suffixIcon: const Icon(Icons.arrow_drop_down),
            filled: config.readOnly,
            fillColor: config.readOnly ? FrappeTheme.surface : Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 16,
            ),
          ),
          child: Text(
            val.isEmpty ? 'Tap to select' : val,
            style: TextStyle(
              fontSize: 16,
              color: val.isEmpty ? Colors.grey : FrappeTheme.textBody,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    });
  }

  void _showSearchSheet(BuildContext context) {
    // Safety check
    if (config.optionsLink == null || config.optionsLink!.isEmpty) {
      Get.snackbar(
        "Configuration Error",
        "No Link Options defined for field: ${config.label}",
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(16),
      );
      return;
    }

    final searchCtrl = TextEditingController();
    final RxList<String> items = <String>[].obs;
    final RxBool isLoading = false.obs;
    Timer? debounce;

    // Fetch Function
    void fetch(String query) async {
      isLoading.value = true;
      try {
        final res = await controller.searchLink(config.optionsLink!, query);
        items.assignAll(res);
      } catch (e) {
        items.clear();
      } finally {
        isLoading.value = false;
      }
    }

    // Initial Fetch
    fetch('');

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Text(
              "Select ${config.label}",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Search Input
            TextField(
              controller: searchCtrl,
              autofocus: true,
              decoration: FrappeTheme.inputDecoration(
                "Search ${config.optionsLink}...",
              ).copyWith(prefixIcon: const Icon(Icons.search)),
              onChanged: (val) {
                if (debounce?.isActive ?? false) debounce!.cancel();
                debounce = Timer(
                  const Duration(milliseconds: 300),
                  () => fetch(val),
                );
              },
            ),
            const SizedBox(height: 12),

            // List Results
            Expanded(
              child: Obx(() {
                if (isLoading.value) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: FrappeTheme.primary,
                    ),
                  );
                }
                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      "No results found",
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (c, i) => const Divider(height: 1),
                  itemBuilder: (ctx, index) {
                    final item = items[index];
                    return ListTile(
                      title: Text(
                        item,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      onTap: () {
                        controller.setValue(config.fieldname, item);
                        Get.back();
                      },
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }
}
