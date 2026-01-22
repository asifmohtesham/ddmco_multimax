import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/forms/frappe_child_form_sheet.dart';
import 'package:multimax/app/modules/global_widgets/forms/configure_columns_sheet.dart';

/// Lightweight controller to handle table search state independently
class FrappeTableController extends GetxController {
  var searchText = ''.obs;

  // Track selected filter field (null = All fields)
  var selectedFilterField = Rxn<String>();
  var selectedFilterLabel = Rxn<String>();

  // Tracks which columns are currently visible in the list view
  var visibleFieldNames = <String>[].obs;
  bool isColumnsInitialised = false;

  final TextEditingController searchInputController = TextEditingController();

  void setFilterField(String? fieldname, String? label) {
    selectedFilterField.value = fieldname;
    selectedFilterLabel.value = label;
  }

  void setVisibleFields(List<String> fields) {
    visibleFieldNames.assignAll(fields);
  }

  void initialiseColumns(List<Map<String, dynamic>> meta) {
    if (isColumnsInitialised) return;

    // Default: Use 'in_list_view' property from metadata
    final defaults = meta
        .where((c) => c['in_list_view'] == 1)
        .map((c) => c['fieldname'] as String)
        .toList();

    // Fallback: If no list view columns defined, show first 2 visible data fields
    if (defaults.isEmpty) {
      final fallback = meta
          .where((c) => c['hidden'] != 1)
          .take(2)
          .map((c) => c['fieldname'] as String)
          .toList();
      visibleFieldNames.assignAll(fallback);
    } else {
      visibleFieldNames.assignAll(defaults);
    }

    isColumnsInitialised = true;
  }

  void clearSearch() {
    searchText.value = '';
    searchInputController.clear();
  }

  @override
  void onClose() {
    searchInputController.dispose();
    super.onClose();
  }
}

class FrappeTableField extends StatelessWidget {
  final String label;
  final List<dynamic> items;
  final Map<String, dynamic> fieldMeta;
  final List<Map<String, dynamic>>? childFieldMeta; // Whitelisted columns
  final Function(int index, dynamic data) onRowUpdate;

  // Optional callbacks for Add/Delete operations
  final Function(Map<String, dynamic> data)? onAddRow;
  final Function(int index)? onDeleteRow;

  final Map<String, dynamic> Function(String fieldname, Map<String, dynamic> doc)? onGetFilters;

  // New: Callback for row field changes
  final Function(String key, dynamic value, RxMap<String, dynamic> row)? onRowFieldChange;

  // Sentinel value for "All Fields" to ensure robust selection
  static const String _allFieldsSentinel = '__ALL__';

  const FrappeTableField({
    super.key,
    required this.label,
    required this.items,
    required this.fieldMeta,
    this.childFieldMeta,
    required this.onRowUpdate,
    this.onAddRow,
    this.onDeleteRow,
    this.onGetFilters,
    this.onRowFieldChange
  });

  void _openRowEditor(
    BuildContext context, {
    int? index,
    Map<String, dynamic>? data,
  }) {
    if (childFieldMeta == null || childFieldMeta!.isEmpty) {
      Get.snackbar("Error", "No field metadata available for this table.");
      return;
    }

    final bool isNew = index == null;
    final Map<String, dynamic> initialData = isNew
        ? {}
        : Map<String, dynamic>.from(data ?? items[index!]);

    Get.bottomSheet(
      FrappeChildFormSheet(
        title: isNew ? "Add $label Item" : "Edit $label Item",
        fieldsMeta: childFieldMeta!,
        initialData: initialData,
        isNew: isNew,
        onSave: (updatedData) {
          if (isNew) {
            if (onAddRow != null) {
              onAddRow!(updatedData);
            }
          } else {
            onRowUpdate(index!, updatedData);
          }
        },
        onDelete: isNew
            ? null
            : () {
                if (onDeleteRow != null && index != null) {
                  onDeleteRow!(index);
                }
              },
        onGetFilters: onGetFilters,
        onValueChange: onRowFieldChange,
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  void _openColumnConfig(
    BuildContext context,
    FrappeTableController controller,
  ) {
    if (childFieldMeta == null) return;

    Get.bottomSheet(
      ConfigureColumnsSheet(
        allFields: childFieldMeta!,
        currentVisibleFields: controller.visibleFieldNames,
        onSave: (newFields) {
          controller.setVisibleFields(newFields);
        },
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Instantiate a controller unique to this fieldname
    final controller = Get.put(
      FrappeTableController(),
      tag: fieldMeta['fieldname'] ?? label,
    );

    if (childFieldMeta != null && !controller.isColumnsInitialised) {
      controller.initialiseColumns(childFieldMeta!);
    }

    // Get visible columns for the filter menu
    final List<Map<String, dynamic>> filterableColumns =
        childFieldMeta?.where((c) => c['hidden'] != 1).toList() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Header ---
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  if (items.isNotEmpty)
                    Text(
                      '${items.length} Items',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  const SizedBox(width: 8),

                  // Configure Columns Button
                  IconButton(
                    icon: const Icon(
                      Icons.settings,
                      size: 20,
                      color: Colors.grey,
                    ),
                    tooltip: 'Configure Columns',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    onPressed: () => _openColumnConfig(context, controller),
                  ),
                  const SizedBox(width: 4),

                  if (onAddRow != null)
                    TextButton.icon(
                      onPressed: () => _openRowEditor(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text("Add"),
                      style: TextButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        // --- Search Bar (Always Visible) ---
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Obx(
            () => TextField(
              controller: controller.searchInputController,
              decoration: InputDecoration(
                hintText: "Search...",
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.white,
                isDense: true,

                // Allow prefix to expand to fit text
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 0,
                  minHeight: 0,
                ),

                prefixIcon: PopupMenuButton<String>(
                  tooltip: 'Filter By Field',
                  offset: const Offset(0, 40),
                  // Explicit dropdown trigger UI
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.filter_list,
                          size: 18,
                          color: controller.selectedFilterField.value != null
                              ? Colors.blue
                              : Colors.grey[600],
                        ),
                        const SizedBox(width: 6),

                        Text(
                          controller.selectedFilterLabel.value ?? "All",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: controller.selectedFilterField.value != null
                                ? Colors.blue
                                : Colors.grey[800],
                          ),
                        ),

                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_drop_down,
                          size: 18,
                          color: Colors.grey[600],
                        ),

                        // Vertical Divider
                        Container(
                          height: 20,
                          width: 1,
                          margin: const EdgeInsets.only(left: 10, right: 2),
                          color: Colors.grey[300],
                        ),
                      ],
                    ),
                  ),
                  onSelected: (value) {
                    if (value == _allFieldsSentinel) {
                      controller.setFilterField(null, null);
                    } else {
                      final col = filterableColumns.firstWhere(
                        (c) => c['fieldname'] == value,
                      );
                      controller.setFilterField(value, col['label']);
                    }
                  },
                  itemBuilder: (BuildContext context) {
                    return [
                      const PopupMenuItem<String>(
                        value: _allFieldsSentinel,
                        child: Text(
                          "All Fields",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const PopupMenuDivider(),
                      ...filterableColumns.map((col) {
                        return PopupMenuItem<String>(
                          value: col['fieldname'],
                          child: Text(col['label'] ?? col['fieldname']),
                        );
                      }),
                    ];
                  },
                ),

                suffixIcon: controller.searchText.value.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: controller.clearSearch,
                      )
                    : null,
              ),
              onChanged: (val) => controller.searchText.value = val,
            ),
          ),
        ),

        // --- Table Content ---
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey[50],
          ),
          child: Obx(() {
            // CRITICAL: Explicitly access visibleFieldNames here so Obx listens to it.
            // Without this, Obx doesn't know it depends on visibleFieldNames because
            // it's only accessed inside the lazy itemBuilder.
            // ignore: unused_local_variable
            // Explicitly subscribe to visibleFieldNames
            // ignore: unused_local_variable
            final visibleColumnsTrigger = Get.find<FrappeTableController>(tag: fieldMeta['fieldname'] ?? label).visibleFieldNames.length;

            // Re-fetch controller to ensure we have the instance
            final controller = Get.find<FrappeTableController>(tag: fieldMeta['fieldname'] ?? label);

            // 1. Filter Logic
            final query = controller.searchText.value.toLowerCase();
            final filterField = controller.selectedFilterField.value;
            final List<dynamic> filteredItems;

            if (query.isEmpty) {
              filteredItems = items;
            } else {
              filteredItems = items.where((item) {
                // Case A: Specific Field Search
                if (filterField != null) {
                  final val = item[filterField]?.toString().toLowerCase() ?? '';
                  return val.contains(query);
                }

                // Case B: All Fields Search (Only checks visible list columns)
                return childFieldMeta?.any((col) {
                      if (col['hidden'] == 1) return false;
                      final key = col['fieldname'];
                      final val = item[key]?.toString().toLowerCase() ?? '';
                      return val.contains(query);
                    }) ??
                    false;
              }).toList();
            }

            // 2. Empty State
            if (filteredItems.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: Text(
                    items.isEmpty ? 'No items added' : 'No matches found',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              );
            }

            // 3. List Builder
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredItems.length,
              separatorBuilder: (c, i) =>
                  const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                final item = filteredItems[index];
                final originalIndex = items.indexOf(item);

                return _buildDynamicRow(context, originalIndex, item, controller);
              },
            );
          },
          // CRITICAL: Force Obx to rebuild when 'items' list identity changes.
          key: ValueKey(items),
          ),
        ),
      ],
    );
  }

  Widget _buildDynamicRow(
    BuildContext context,
    int index,
    Map<String, dynamic> row,
    FrappeTableController controller,
  ) {
    if (childFieldMeta == null || childFieldMeta!.isEmpty) {
      return ListTile(
        title: Text(row['item_code'] ?? 'Row #${index + 1}'),
        subtitle: Text('Qty: ${row['qty'] ?? 0}'),
        trailing: const Icon(Icons.chevron_right),
      );
    }

    return InkWell(
      onTap: () => _openRowEditor(context, index: index, data: row),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: childFieldMeta!
              .where((col) {
                // Render only columns present in the controller's visible list
                return controller.visibleFieldNames.contains(col['fieldname']);
              })
              .map((col) {
                final String label = col['label'] ?? '';
                final String fieldname = col['fieldname'] ?? '';
                final dynamic value = row[fieldname];

                if (value == null || value.toString().isEmpty) {
                  return const SizedBox.shrink();
                }

                final isPrimary = col == childFieldMeta!.first;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          "$label:",
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            fontWeight: isPrimary
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          value.toString(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isPrimary
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              })
              .toList(),
        ),
      ),
    );
  }
}
