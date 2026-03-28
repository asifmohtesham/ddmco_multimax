import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// ReportFilterField descriptor
// ---------------------------------------------------------------------------

enum ReportFilterType {
  /// Plain text input.
  text,
  /// Read-only field that opens a [DatePickerDialog] on tap.
  datePicker,
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

  const ReportFilterField({
    required this.key,
    required this.label,
    this.type = ReportFilterType.text,
    this.prefixIcon,
    this.hint,
    this.required = false,
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
      title:          title,
      fields:         fields,
      controllers:    controllers,
      onRun:          onRun,
      onClear:        onClear,
      sectionLabels:  sectionLabels,
    ),
  );
}

// ---------------------------------------------------------------------------
// _ReportFilterSheet
// ---------------------------------------------------------------------------

class _ReportFilterSheet extends StatelessWidget {
  final String                              title;
  final List<ReportFilterField>             fields;
  final Map<String, TextEditingController>  controllers;
  final VoidCallback                        onRun;
  final VoidCallback?                       onClear;
  final Map<String, String>                 sectionLabels;

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
                                  (controllers[f.key]?.text.trim().isEmpty ??  true))
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

class _FieldWidget extends StatelessWidget {
  final ReportFilterField            field;
  final TextEditingController        controller;
  const _FieldWidget({
    required this.field,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    if (field.type == ReportFilterType.datePicker) {
      return TextField(
        controller: controller,
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

    // Default: text
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText:  field.label,
        hintText:   field.hint,
        border:     const OutlineInputBorder(),
        prefixIcon: field.prefixIcon != null ? Icon(field.prefixIcon) : null,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 12),
      ),
    );
  }

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
}
