import 'package:flutter/material.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

// ---------------------------------------------------------------------------
// ReportFilterField descriptor
// ---------------------------------------------------------------------------

enum ReportFilterType {
  /// Plain text input.
  text,

  /// Read-only field that opens a [DatePickerDialog] on tap.
  datePicker,

  /// Editable text field with a barcode-scan suffix icon.
  /// Tapping the scan icon requests focus on [ReportFilterField.focusNode]
  /// so DataWedge (or any hardware scanner) routes its output here.
  /// The user can also type directly into the field.
  batchBrowse,

  /// Read-only field that opens a searchable DocType picker sheet on tap.
  /// Requires [ReportFilterField.linkDoctype] to be set.
  doctypeLink,
}

/// Describes a single filter row inside [showReportFilterSheet].
class ReportFilterField {
  /// Key used in the controller map and in [activeFilters].
  final String key;

  /// Human-readable label shown on the [TextField].
  final String label;

  final ReportFilterType type;
  final IconData? prefixIcon;

  /// Optional hint text.
  final String? hint;

  /// Whether the field is required (shows * in label, validated on Run).
  final bool required;

  /// Optional [FocusNode] — pass one when the caller needs to track which
  /// field is focused (e.g. to route DataWedge barcode scans to the right
  /// [TextEditingController]).  Ignored when null.
  final FocusNode? focusNode;

  /// DocType name used by [ReportFilterType.doctypeLink] to populate the
  /// picker sheet (e.g. `'Warehouse'`).  Ignored for all other types.
  final String? linkDoctype;

  const ReportFilterField({
    required this.key,
    required this.label,
    this.type = ReportFilterType.text,
    this.prefixIcon,
    this.hint,
    this.required = false,
    this.focusNode,
    this.linkDoctype,
  });
}

// ---------------------------------------------------------------------------
// Helper: count active (non-empty) filters
// ---------------------------------------------------------------------------

/// Returns the number of [controllers] whose text is non-empty.
/// Use this to drive the badge on the filter icon in the app bar.
int activeFilterCount(Map<String, TextEditingController> controllers) =>
    controllers.values.where((c) => c.text.trim().isNotEmpty).length;

// ---------------------------------------------------------------------------
// showReportFilterSheet
// ---------------------------------------------------------------------------

/// Opens a [DraggableScrollableSheet] bottom sheet that renders [fields]
/// using [controllers].  Calls [onRun] (and pops the sheet) when the user
/// taps **Run Report**.  Optionally validates that all [ReportFilterField.required]
/// fields are non-empty before calling [onRun].
///
/// ### Usage
/// ```dart
/// showReportFilterSheet(
///   context: context,
///   title: 'Batch-Wise Balance Filters',
///   fields: [
///     ReportFilterField(key: 'item_code', label: 'Item Code *',
///         type: ReportFilterType.text, required: true),
///     ReportFilterField(key: 'from_date', label: 'From',
///         type: ReportFilterType.datePicker),
///     ReportFilterField(key: 'batch_no', label: 'Batch No',
///         type: ReportFilterType.batchBrowse,
///         focusNode: myBatchFocusNode),
///     ReportFilterField(key: 'warehouse', label: 'Warehouse',
///         type: ReportFilterType.doctypeLink,
///         linkDoctype: 'Warehouse'),
///   ],
///   controllers: controller.filterControllers,
///   onRun: controller.runReport,
///   onClear: controller.clearFilters,
/// );
/// ```
Future<void> showReportFilterSheet({
  required BuildContext context,
  required String title,
  required List<ReportFilterField> fields,
  required Map<String, TextEditingController> controllers,
  required VoidCallback onRun,
  VoidCallback? onClear,

  /// Optional section breaks: map of field key → section label drawn above it.
  Map<String, String> sectionLabels = const {},
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportFilterSheet(
      title:         title,
      fields:        fields,
      controllers:   controllers,
      onRun:         onRun,
      onClear:       onClear,
      sectionLabels: sectionLabels,
    ),
  );
}

// ---------------------------------------------------------------------------
// _ReportFilterSheet
// ---------------------------------------------------------------------------

class _ReportFilterSheet extends StatelessWidget {
  final String                             title;
  final List<ReportFilterField>            fields;
  final Map<String, TextEditingController> controllers;
  final VoidCallback                       onRun;
  final VoidCallback?                      onClear;
  final Map<String, String>                sectionLabels;

  const _ReportFilterSheet({
    required this.title,
    required this.fields,
    required this.controllers,
    required this.onRun,
    this.onClear,
    this.sectionLabels = const {},
  });

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize:     0.4,
      maxChildSize:     0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // ── drag handle ──────────────────────────────────────────────
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── title row ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.filter_alt_outlined,
                        color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (onClear != null)
                      TextButton.icon(
                        onPressed: () {
                          onClear!();
                          Navigator.of(ctx).pop();
                        },
                        icon: const Icon(Icons.clear_all, size: 16),
                        label: const Text('Clear'),
                        style: TextButton.styleFrom(
                          foregroundColor: cs.error,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8),
                        ),
                      ),
                  ],
                ),
              ),
              Divider(
                  height: 1,
                  thickness: 1,
                  color: cs.outlineVariant,
                  indent: 20,
                  endIndent: 20),
              const SizedBox(height: 4),

              // ── fields ────────────────────────────────────────────────────
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  children: [
                    for (final field in fields) ...[
                      if (sectionLabels.containsKey(field.key))
                        _SheetSubheading(sectionLabels[field.key]!),
                      const SizedBox(height: 4),
                      _FieldWidget(
                        field:      field,
                        controller: controllers[field.key]!,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),

              // ── action buttons ────────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    MediaQuery.of(ctx).viewInsets.bottom +
                        MediaQuery.of(ctx).padding.bottom +
                        12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          // Validate required fields
                          final missing = fields
                              .where((f) =>
                                  f.required &&
                                  (controllers[f.key]?.text.trim().isEmpty ??
                                      true))
                              .map((f) => f.label.replaceAll('*', '').trim())
                              .toList();
                          if (missing.isNotEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Required: ${missing.join(', ')}'),
                                backgroundColor: cs.error,
                              ),
                            );
                            return;
                          }
                          Navigator.of(ctx).pop();
                          onRun();
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Run Report',
                            style: TextStyle(fontSize: 15)),
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.all(14)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

class _SheetSubheading extends StatelessWidget {
  final String label;
  const _SheetSubheading(this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade500,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
                height: 1,
                thickness: 1,
                color: cs.outlineVariant),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _FieldWidget — StatefulWidget so suffix icons react to controller changes
// ---------------------------------------------------------------------------

class _FieldWidget extends StatefulWidget {
  final ReportFilterField     field;
  final TextEditingController controller;

  const _FieldWidget({
    required this.field,
    required this.controller,
  });

  @override
  State<_FieldWidget> createState() => _FieldWidgetState();
}

class _FieldWidgetState extends State<_FieldWidget> {
  // Tracks whether the controller has text so suffix icons rebuild correctly.
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final nowHasText = widget.controller.text.isNotEmpty;
    if (nowHasText != _hasText) {
      setState(() => _hasText = nowHasText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final field      = widget.field;
    final controller = widget.controller;

    // ── datePicker ─────────────────────────────────────────────────────────
    if (field.type == ReportFilterType.datePicker) {
      return TextField(
        controller: controller,
        focusNode:  field.focusNode,
        readOnly:   true,
        onTap: () => _pickDate(context, controller),
        decoration: InputDecoration(
          labelText:  field.label,
          hintText:   field.hint,
          border:     const OutlineInputBorder(),
          prefixIcon: Icon(field.prefixIcon ?? Icons.calendar_today_outlined),
          suffixIcon: const Icon(Icons.edit_calendar_outlined, size: 18),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 12),
        ),
      );
    }

    // ── batchBrowse ────────────────────────────────────────────────────────
    // Editable field; suffix icon focuses the node for DataWedge routing.
    // A clear button appears once the field has content.
    if (field.type == ReportFilterType.batchBrowse) {
      return TextField(
        controller: controller,
        focusNode:  field.focusNode,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText:  field.label,
          hintText:   field.hint ?? 'Scan or type batch no.',
          border:     const OutlineInputBorder(),
          prefixIcon: Icon(field.prefixIcon ?? Icons.qr_code_2_outlined),
          suffixIcon: _hasText
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Clear',
                  onPressed: () => controller.clear(),
                )
              : IconButton(
                  icon: const Icon(Icons.qr_code_scanner_outlined, size: 20),
                  tooltip: 'Scan barcode',
                  onPressed: () {
                    // Request focus so DataWedge output lands in this field.
                    field.focusNode?.requestFocus();
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 12),
        ),
      );
    }

    // ── doctypeLink ────────────────────────────────────────────────────────
    // Read-only tap-to-pick field. Opens _DoctypeLinkSheet.
    if (field.type == ReportFilterType.doctypeLink) {
      return TextField(
        controller: controller,
        focusNode:  field.focusNode,
        readOnly:   true,
        onTap: () => _openDoctypeSheet(context, field, controller),
        decoration: InputDecoration(
          labelText:  field.label,
          hintText:   field.hint ?? 'Tap to select',
          border:     const OutlineInputBorder(),
          prefixIcon: Icon(field.prefixIcon ?? Icons.list_alt_outlined),
          suffixIcon: _hasText
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Clear',
                  onPressed: () => controller.clear(),
                )
              : const Icon(Icons.arrow_drop_down),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 12),
        ),
      );
    }

    // ── text (default) ─────────────────────────────────────────────────────
    return TextField(
      controller: controller,
      focusNode:  field.focusNode,
      decoration: InputDecoration(
        labelText:  field.label,
        hintText:   field.hint,
        border:     const OutlineInputBorder(),
        prefixIcon: field.prefixIcon != null ? Icon(field.prefixIcon) : null,
        suffixIcon: _hasText
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                tooltip: 'Clear',
                onPressed: () => controller.clear(),
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 12),
      ),
    );
  }

  // ── Date picker helper ──────────────────────────────────────────────────
  Future<void> _pickDate(
      BuildContext context, TextEditingController ctrl) async {
    final now    = DateTime.now();
    final parsed = DateTime.tryParse(ctrl.text);
    final picked = await showDatePicker(
      context:     context,
      initialDate: parsed ?? now,
      firstDate:   DateTime(now.year - 10),
      lastDate:    DateTime(now.year + 2),
    );
    if (picked != null) {
      ctrl.text =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }

  // ── DocType link picker ─────────────────────────────────────────────────
  Future<void> _openDoctypeSheet(
    BuildContext context,
    ReportFilterField field,
    TextEditingController ctrl,
  ) async {
    final doctype = field.linkDoctype;
    if (doctype == null || doctype.isEmpty) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DoctypeLinkSheet(
        doctype: doctype,
        title:   field.label,
      ),
    );

    if (selected != null) {
      ctrl.text = selected;
    }
  }
}

// ---------------------------------------------------------------------------
// _DoctypeLinkSheet — searchable DocType list picker
// ---------------------------------------------------------------------------

class _DoctypeLinkSheet extends StatefulWidget {
  final String doctype;
  final String title;

  const _DoctypeLinkSheet({
    required this.doctype,
    required this.title,
  });

  @override
  State<_DoctypeLinkSheet> createState() => _DoctypeLinkSheetState();
}

class _DoctypeLinkSheetState extends State<_DoctypeLinkSheet> {
  final _searchCtrl    = TextEditingController();
  final _searchFocus   = FocusNode();
  final _apiProvider   = ApiProvider();

  List<String> _allItems    = [];
  List<String> _filtered    = [];
  bool         _loading     = true;
  String?      _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() {
      _loading  = true;
      _errorMsg = null;
    });
    try {
      final rows = await _apiProvider.getList(
        null,
        doctype:  widget.doctype,
        fields:   ['name'],
        limit:    500,
        orderBy:  'name asc',
      );
      final names = rows.map((r) => r['name'].toString()).toList();
      if (mounted) {
        setState(() {
          _allItems = names;
          _filtered = names;
          _loading  = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading  = false;
          _errorMsg = 'Failed to load ${widget.doctype}: $e';
        });
      }
    }
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _allItems
          : _allItems
              .where((n) => n.toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize:     0.4,
      maxChildSize:     0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // ── drag handle ──────────────────────────────────────────────
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── title ────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.list_alt_outlined,
                        color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Select ${widget.title}',
                        style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: cs.outlineVariant,
                indent: 20,
                endIndent: 20,
              ),

              // ── search box ───────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode:  _searchFocus,
                  autofocus:  true,
                  decoration: InputDecoration(
                    hintText:    'Search ${widget.doctype}…',
                    prefixIcon:  const Icon(Icons.search, size: 20),
                    border:      const OutlineInputBorder(),
                    isDense:     true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                  ),
                ),
              ),

              // ── list ─────────────────────────────────────────────────────
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMsg != null
                        ? _ErrorState(
                            message: _errorMsg!,
                            onRetry: _loadItems,
                          )
                        : _filtered.isEmpty
                            ? Center(
                                child: Text(
                                  'No results for "${_searchCtrl.text}"',
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollCtrl,
                                itemCount:  _filtered.length,
                                itemBuilder: (_, i) {
                                  final name = _filtered[i];
                                  return ListTile(
                                    dense:   true,
                                    title:   Text(name),
                                    onTap:   () =>
                                        Navigator.of(ctx).pop(name),
                                    trailing: const Icon(
                                        Icons.chevron_right,
                                        size: 18),
                                  );
                                },
                              ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// _ErrorState — retry widget for _DoctypeLinkSheet load failures
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  final String      message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon:  const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
