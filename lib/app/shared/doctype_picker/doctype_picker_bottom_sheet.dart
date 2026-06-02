import 'package:flutter/material.dart';
import 'doctype_picker_config.dart';
import 'doctype_picker_column.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/doctype_picker_provider.dart';

// ────────────────────────────────────────────────────────────────────────────
// showDocTypePickerBottomSheet
// ────────────────────────────────────────────────────────────────────────────

/// Opens a bottom sheet allowing the user to search and select a record from
/// the given [config]'s DocType.
///
/// Returns the selected row as `Map<String, dynamic>` or `null` if dismissed.
///
/// ### Example
/// ```dart
/// final selected = await showDocTypePickerBottomSheet(context, config: itemConfig);
/// if (selected != null) {
///   print('Selected: ${selected['item_code']}');
/// }
/// ```
Future<Map<String, dynamic>?> showDocTypePickerBottomSheet(
  BuildContext context, {
  required DocTypePickerConfig config,
}) {
  return showModalBottomSheet<Map<String, dynamic>?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _DocTypePickerBottomSheet(config: config),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// _DocTypePickerBottomSheet
// ────────────────────────────────────────────────────────────────────────────

class _DocTypePickerBottomSheet extends StatefulWidget {
  final DocTypePickerConfig config;

  const _DocTypePickerBottomSheet({required this.config});

  @override
  State<_DocTypePickerBottomSheet> createState() =>
      _DocTypePickerBottomSheetState();
}

class _DocTypePickerBottomSheetState
    extends State<_DocTypePickerBottomSheet> {
  final TextEditingController _searchController = TextEditingController();

  // Resolved lazily in initState to avoid Get.find running at field-init
  // time (before the provider is registered), which caused:
  //   "DocTypePickerProvider" not found. You need to call Get.put(...).
  late DocTypePickerProvider _provider;

  bool _isLoading = false;
  String _error = '';
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    // Register the provider on-demand if it hasn't been put yet
    // (e.g. when the bottom sheet is opened before any binding registers it).
    if (!Get.isRegistered<DocTypePickerProvider>()) {
      Get.put(DocTypePickerProvider());
    }
    _provider = Get.find<DocTypePickerProvider>();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    // If config has a temporary loader, use it (dev/testing path)
    if (widget.config.loader != null) {
      setState(() {
        _isLoading = true;
        _error = '';
      });
      try {
        final rows = await widget.config.loader!(_searchController.text);
        if (mounted) {
          setState(() {
            _rows = rows;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = e.toString();
          });
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
      return;
    }

    // Production path: use DocTypePickerProvider
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final result = await _provider.queryDocType(
        doctype: widget.config.doctype,
        fields: widget.config.resolvedFields,
        filters: widget.config.filters,
        searchText: _searchController.text.trim(),
        cacheKey: widget.config.cacheKey,
        forceRefresh: forceRefresh,
      );

      if (mounted) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(result['data'] ?? []);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSelect(Map<String, dynamic> row) {
    Navigator.of(context).pop(row);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mq = MediaQuery.of(context);
    final isWide = mq.size.width >= 600;

    return Container(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28.0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
            alignment: Alignment.center,
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.config.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                if (widget.config.allowRefresh)
                  IconButton(
                    onPressed: () => _load(forceRefresh: true),
                    icon: const Icon(Icons.refresh),
                    style: IconButton.styleFrom(
                      backgroundColor: cs.surfaceContainerHigh,
                      foregroundColor: cs.onSurfaceVariant,
                    ),
                    tooltip: 'Refresh',
                  ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    backgroundColor: cs.surfaceContainerHigh,
                    foregroundColor: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _load(),
            ),
          ),
          const Divider(height: 1),
          // Body
          Expanded(
            child: _buildBody(isWide, cs),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool isWide, ColorScheme cs) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: cs.error.withOpacity(0.7)),
              const SizedBox(height: 12),
              Text(
                _error,
                style: TextStyle(color: cs.error, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
                      const SizedBox(height: 24),
            Icon(Icons.inbox_outlined,
                size: 48, color: cs.onSurfaceVariant.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(
              'No ${widget.config.doctype} found',              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
                      const SizedBox(height: 8),
          Text(
            'Try adjusting your search or tap refresh',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          ],
        ),
      );
    }

    if (isWide) {
      return _buildTableList();
    }
    return _buildStackedList(cs);
  }

  Widget _buildTableList() {
    final columns = widget.config.columns;
    return ListView.builder(
      itemCount: _rows.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          // Header row
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: columns
                  .map(
                    (c) => Expanded(
                      flex: c.flex,
                      child: Text(
                        c.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                        textAlign: c.align,
                      ),
                    ),
                  )
                  .toList(),
            ),
          );
        }
        final row = _rows[index - 1];
        final selectable =
            widget.config.selectabilityResolver?.call(row) ?? true;
        return InkWell(
          onTap: selectable ? () => _onSelect(row) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: columns
                  .map(
                    (c) => Expanded(
                      flex: c.flex,
                      child: Text(
                        c.resolve(row),
                        overflow: TextOverflow.ellipsis,
                        textAlign: c.align,
                        style: TextStyle(
                          fontWeight:
                              c.isPrimary ? FontWeight.w600 : FontWeight.normal,
                          color: selectable ? null : Colors.grey,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStackedList(ColorScheme cs) {
    final primary = widget.config.columns.firstWhere(
      (c) => c.isPrimary,
      orElse: () => widget.config.columns.first,
    );
    final secondary = widget.config.columns.firstWhere(
      (c) => c.isSecondary && c.fieldname != primary.fieldname,
      orElse: () => primary,
    );

    return ListView.builder(
      itemCount: _rows.length,
      itemBuilder: (context, index) {
        final row = _rows[index];
        final selectable =
            widget.config.selectabilityResolver?.call(row) ?? true;
        final subtitleParts = <String>[];
        for (final f in widget.config.subtitleFields) {
          final v = row[f];
          if (v != null && '$v'.trim().isNotEmpty) {
            final formatted =
                widget.config.subtitleFormatter?.call(f, '$v') ?? '$v';
            if (formatted != null && formatted.isNotEmpty) {
              subtitleParts.add(formatted);
            }
          }
        }

        return ListTile(
          enabled: selectable,
          title: Text(
            primary.resolve(row),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFamily: 'ShureTechMono',
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (secondary.fieldname != primary.fieldname)
                Text(secondary.resolve(row)),
              if (subtitleParts.isNotEmpty)
                Text(
                  subtitleParts.join(' \u2022 '),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          onTap: selectable ? () => _onSelect(row) : null,
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
