import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/item/item_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

class ItemFilterBottomSheet extends StatefulWidget {
  const ItemFilterBottomSheet({super.key});

  @override
  State<ItemFilterBottomSheet> createState() => _ItemFilterBottomSheetState();
}

class _ItemFilterBottomSheetState extends State<ItemFilterBottomSheet> {
  final ItemController controller = Get.find();

  late TextEditingController itemGroupController;
  late TextEditingController variantOfController;
  late TextEditingController attributeNameController;
  late TextEditingController attributeValueController;

  late bool showImagesOnly;

  final RxList<Map<String, String>> localAttributeFilters = <Map<String, String>>[].obs;

  // Speech to Text
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _lastWords = '';

  @override
  void initState() {
    super.initState();
    itemGroupController = TextEditingController(text: _extractFilterValue('item_group'));
    variantOfController = TextEditingController(text: _extractFilterValue('variant_of'));

    localAttributeFilters.assignAll(
        controller.attributeFilters.map((e) => Map<String, String>.from(e)).toList()
    );

    attributeNameController = TextEditingController();
    attributeValueController = TextEditingController();

    showImagesOnly = controller.showImagesOnly.value;

    _speech = stt.SpeechToText();
  }

  String _extractFilterValue(String key) {
    final val = controller.activeFilters[key];
    if (val is List && val.isNotEmpty && val[0] == 'like') {
      return val[1].toString().replaceAll('%', '');
    }
    if (val is List && val.isNotEmpty && val[0] == '=') {
      return val[1].toString();
    }
    if (val is String) return val;
    return '';
  }

  @override
  void dispose() {
    itemGroupController.dispose();
    variantOfController.dispose();
    attributeNameController.dispose();
    attributeValueController.dispose();
    super.dispose();
  }

  // --- Voice Input Logic ---

  Future<void> _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            setState(() => _isListening = false);
            if (_lastWords.isNotEmpty) {
              _parseVoiceInput(_lastWords);
            }
          }
        },
        onError: (val) => print('onError: $val'),
      );

      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) => setState(() {
            _lastWords = val.recognizedWords;
          }),
        );
      } else {
        GlobalSnackbar.error(message: 'Speech recognition not available');
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _parseVoiceInput(String input) {
    if (input.isEmpty) return;
    String processed = input.toLowerCase();

    // 1. Parse Item Group: "Filter the [Wallets] Item Group"
    // Regex looks for words before "item group" or "group"
    final groupRegex = RegExp(r'(?:filter\s+(?:the\s+)?)?(.+?)\s+(?:item\s+group|group)');
    final groupMatch = groupRegex.firstMatch(processed);

    if (groupMatch != null) {
      String rawGroup = groupMatch.group(1)?.trim() ?? '';
      // Cleanup common prefixes if regex didn't catch them
      rawGroup = rawGroup.replaceAll('filter the', '').replaceAll('filter', '').trim();

      if (rawGroup.isNotEmpty) {
        // Attempt to find matching group from controller list
        final match = controller.itemGroups.firstWhere(
                (g) => g.toLowerCase().contains(rawGroup),
            orElse: () => ''
        );
        if (match.isNotEmpty) {
          itemGroupController.text = match;
          GlobalSnackbar.success(message: 'Item Group set to $match');
        } else {
          // Fallback to raw text if no exact list match
          itemGroupController.text = rawGroup[0].toUpperCase() + rawGroup.substring(1);
        }
      }
    }

    // 2. Parse Variant/Template: "Article Number/Template/Variant Of [022]"
    // Regex looks for value after keywords
    final variantRegex = RegExp(r'(?:article number|template|variant of|variant)\s+(.+)');
    final variantMatch = variantRegex.firstMatch(processed);

    if (variantMatch != null) {
      String rawVariant = variantMatch.group(1)?.trim() ?? '';
      // Remove any trailing punctuation
      rawVariant = rawVariant.replaceAll(RegExp(r'[^\w\s\-]'), '');

      if (rawVariant.isNotEmpty) {
        variantOfController.text = rawVariant;
        GlobalSnackbar.success(message: 'Variant filter set to $rawVariant');
      }
    }

    // Clear last words to avoid re-processing
    _lastWords = '';
  }

  // ... (Existing selection sheet methods) ...

  void _showSelectionSheet({
    required BuildContext context,
    required String title,
    required List<String> items,
    required Function(String) onSelected,
    bool isLoading = false,
  }) {
    // ... (Keep existing implementation) ...
    final searchController = TextEditingController();
    final RxList<String> filteredItems = RxList<String>(items);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16.0),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: "Search...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (val) {
                      if (val.isEmpty) {
                        filteredItems.assignAll(items);
                      } else {
                        filteredItems.assignAll(items.where(
                                (item) => item.toLowerCase().contains(val.toLowerCase())
                        ).toList());
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Obx(() {
                      if (isLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (filteredItems.isEmpty) {
                        return const Center(child: Text("No items found"));
                      }
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: filteredItems.length,
                        separatorBuilder: (c, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          return ListTile(
                            title: Text(item),
                            onTap: () {
                              onSelected(item);
                              Get.back();
                            },
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _addAttributeFilter() {
    // ... (Keep existing implementation) ...
    final name = attributeNameController.text;
    final value = attributeValueController.text;

    if (name.isNotEmpty && value.isNotEmpty) {
      final exists = localAttributeFilters.any((e) => e['name'] == name && e['value'] == value);
      if (!exists) {
        localAttributeFilters.add({'name': name, 'value': value});
        attributeNameController.clear();
        attributeValueController.clear();
      } else {
        GlobalSnackbar.info(message: 'Filter already added');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Filter Items', style: Theme.of(context).textTheme.titleLarge),
                // VOICE INPUT BUTTON
                Row(
                  children: [
                    AvatarGlowWidget(
                      isListening: _isListening,
                      onTap: _listen,
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        controller.clearFilters();
                        Get.back();
                      },
                      child: const Text('Clear All'),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView(
                children: [
                  SwitchListTile(
                    title: const Text('Show Images Only'),
                    subtitle: const Text('Hide items without a product image'),
                    value: showImagesOnly,
                    onChanged: (val) {
                      setState(() {
                        showImagesOnly = val;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 12),

                  // Item Group
                  TextFormField(
                    controller: itemGroupController,
                    readOnly: true,
                    onTap: () => _showSelectionSheet(
                      context: context,
                      title: "Select Item Group",
                      items: controller.itemGroups,
                      isLoading: controller.isLoadingGroups.value,
                      onSelected: (val) => setState(() => itemGroupController.text = val),
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Item Group',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Variant Of (Template)
                  TextFormField(
                    controller: variantOfController,
                    readOnly: true,
                    onTap: () => _showSelectionSheet(
                      context: context,
                      title: "Select Template Item",
                      items: controller.templateItems,
                      isLoading: controller.isLoadingTemplates.value,
                      onSelected: (val) => setState(() => variantOfController.text = val),
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Variant Of (Template)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.copy),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Text('Filter By Attributes', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),

                  // Active Filters Chips
                  Obx(() {
                    if (localAttributeFilters.isEmpty) return const SizedBox.shrink();
                    return Wrap(
                      spacing: 8.0,
                      children: localAttributeFilters.map((filter) {
                        return Chip(
                          label: Text('${filter['name']}: ${filter['value']}'),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: () {
                            localAttributeFilters.remove(filter);
                          },
                          backgroundColor: Colors.blue.shade50,
                          side: BorderSide(color: Colors.blue.shade200),
                        );
                      }).toList(),
                    );
                  }),
                  const SizedBox(height: 8),

                  // Add New Attribute Filter Row
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: attributeNameController,
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: 'Attribute',
                                  hintText: 'Color...',
                                  border: OutlineInputBorder(),
                                  suffixIcon: Icon(Icons.arrow_drop_down),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                ),
                                onTap: () => _showSelectionSheet(
                                    context: context,
                                    title: "Select Attribute",
                                    items: controller.itemAttributes,
                                    isLoading: controller.isLoadingAttributes.value,
                                    onSelected: (val) {
                                      setState(() {
                                        attributeNameController.text = val;
                                        attributeValueController.clear();
                                      });
                                      controller.fetchAttributeValues(val);
                                    }
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Obx(() {
                                final enabled = attributeNameController.text.isNotEmpty;
                                return TextFormField(
                                  controller: attributeValueController,
                                  readOnly: true,
                                  enabled: enabled,
                                  decoration: InputDecoration(
                                    labelText: 'Value',
                                    hintText: 'Red...',
                                    border: const OutlineInputBorder(),
                                    suffixIcon: controller.isLoadingAttributeValues.value
                                        ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2)))
                                        : const Icon(Icons.arrow_drop_down),
                                    fillColor: enabled ? Colors.white : Colors.grey.shade100,
                                    filled: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                  ),
                                  onTap: enabled ? () => _showSelectionSheet(
                                    context: context,
                                    title: "Select Value",
                                    items: controller.currentAttributeValues,
                                    onSelected: (val) => setState(() => attributeValueController.text = val),
                                  ) : null,
                                );
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => setState(_addAttributeFilter),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Attribute Filter'),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final filters = <String, dynamic>{};

                if (itemGroupController.text.isNotEmpty) {
                  filters['item_group'] = ['like', '%${itemGroupController.text}%'];
                }

                if (variantOfController.text.isNotEmpty) {
                  filters['variant_of'] = variantOfController.text;
                }

                controller.setImagesOnly(showImagesOnly);
                controller.applyFilters(filters, localAttributeFilters.toList());
                Get.back();
              },
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('Apply Filters'),
            ),
          ],
        ),
      ),
    );
  }
}

// Simple Glow widget for mic feedback
class AvatarGlowWidget extends StatelessWidget {
  final bool isListening;
  final VoidCallback onTap;

  const AvatarGlowWidget({super.key, required this.isListening, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isListening ? Colors.redAccent.withOpacity(0.2) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          isListening ? Icons.mic : Icons.mic_none,
          color: isListening ? Colors.red : Colors.grey,
        ),
      ),
    );
  }
}