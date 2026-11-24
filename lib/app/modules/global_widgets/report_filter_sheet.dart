import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/link_title_cache.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/filter_focus.dart';

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

  /// Multi-value DocType picker (ERPNext `MultiSelectList`): selected names
  /// render as removable chips with an "Add" affordance that opens a picker
  /// for selecting multiple records. The controller holds the values joined by
  /// [kMultiValueSeparator] — read them back with [splitMultiValue].
  /// Requires [ReportFilterField.linkDoctype] to be set.
  doctypeMultiLink,

  /// On/off switch. The controller holds '1' when on and is empty when off.
  switchToggle,
}

/// Separator between values in a [ReportFilterType.doctypeMultiLink]
/// controller. Newline can't appear in a Frappe document name.
const kMultiValueSeparator = '\n';

/// Splits a multi-link controller's text into its non-empty values.
List<String> splitMultiValue(String text) => text
    .split(kMultiValueSeparator)
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

/// Joins [values] for storage in a multi-link controller.
String joinMultiValue(Iterable<String> values) =>
    values.where((s) => s.trim().isNotEmpty).join(kMultiValueSeparator);

/// Describes one on/off switch rendered inside [showReportFilterSheet]
/// (ERPNext `Check` filter). Backed by its own [TextEditingController]:
/// `'1'` when on, empty when off.
class ReportFilterToggle {
  final String key;
  final String label;
  final IconData? icon;

  const ReportFilterToggle({
    required this.key,
    required this.label,
    this.icon,
  });
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

  /// Optional text below a multi-link field or switch.
  final String? helperText;

  /// Whether the field is required (shows * in label, validated on Run).
  final bool required;

  /// Optional [FocusNode] — pass one when the caller needs to track which
  /// field is focused (e.g. to route DataWedge barcode scans to the right
  /// [TextEditingController]).  Ignored when null.
  final FocusNode? focusNode;

  /// DocType name used by [ReportFilterType.doctypeLink] to populate the
  /// picker sheet (e.g. `'Warehouse'`).  Ignored for all other types.
  final String? linkDoctype;

  /// Optional server-side filters applied when loading the doctype link list.
  /// Uses the same `Map<String, dynamic>` format as [ApiProvider.getList]:
  /// `{'fieldname': value}` for equality, `{'fieldname': ['op', value]}` for
  /// other operators.  Ignored for all non-[ReportFilterType.doctypeLink] types.
  final Map<String, dynamic>? linkFilters;

  /// For a [ReportFilterType.doctypeLink] whose `name` is an opaque ID, the
  /// field holding its human title (Employee → `'employee_name'`). The picker
  /// then lists and searches by title with the ID beneath, and the field shows
  /// the title; the controller — and the report filter — still hold the ID.
  final String? linkTitleField;

  const ReportFilterField({
    required this.key,
    required this.label,
    this.type = ReportFilterType.text,
    this.prefixIcon,
    this.hint,
    this.helperText,
    this.required = false,
    this.focusNode,
    this.linkDoctype,
    this.linkFilters,
    this.linkTitleField,
  });
}

/// Describes one option within a [ReportFilterChipGroup].
class ReportFilterChipOption {
  final String value;  // stored value written to the controller
  final String label;  // display text on the chip
  final IconData? icon;

  const ReportFilterChipOption({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// Describes a group of mutually-exclusive [ChoiceChip]s rendered as a
/// horizontal wrap inside [showReportFilterSheet].
///
/// Backed by a plain [TextEditingController] (empty string = no selection).
/// Setting a chip writes its [ReportFilterChipOption.value] into the
/// controller; tapping the selected chip again clears it (toggle-off).
class ReportFilterChipGroup {
  /// Key used in the controller map — must be unique across all fields and
  /// chip groups passed to [showReportFilterSheet].
  final String key;

  /// Section heading drawn above the chip row.
  final String label;

  final List<ReportFilterChipOption> options;

  const ReportFilterChipGroup({
    required this.key,
    required this.label,
    required this.options,
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

/// Opens a content-sized modal bottom sheet that renders [fields]
/// using [controllers].  Calls [onRun] (and pops the sheet) when the user
/// taps **Run Report**.  Optionally validates that all [ReportFilterField.required]
/// fields are non-empty before calling [onRun]. [validate] can return an
/// inline error message for invalid filter combinations.
/// [runBusy] connects the Run control to the report's in-flight state.
///
/// ### Usage
/// ```dart
/// showReportFilterSheet(
///   context: context,
///   title: 'Batch-Wise Balance History Filters',
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
  RxBool? runBusy,
  String? Function()? validate,
  VoidCallback? onClear,
  Map<String, String> sectionLabels = const {},
  // ── NEW ──────────────────────────────────────────────────────────────────
  /// Optional chip groups appended below [fields] in the sheet.
  /// Each group's controller must be present in [controllers].
  List<ReportFilterChipGroup> chipGroups = const [],
  // ─────────────────────────────────────────────────────────────────────────
  /// Optional on/off toggles rendered as one FilterChip row under
  /// [togglesLabel], after [chipGroups]. Each toggle's controller must be
  /// present in [controllers].
  List<ReportFilterToggle> toggles = const [],
  String togglesLabel = 'Options',
  /// Key of the field the user asked to edit (e.g. by tapping its active
  /// filter chip). The sheet brings that field into view and starts editing
  /// it: a text field takes focus, a date or link field opens its picker.
  /// A chip group's or toggle's key brings its choices into view.
  String? focusKey,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FilterFocusScope.wrap(focusKey: focusKey, _ReportFilterSheet(
      title:         title,
      fields:        fields,
      controllers:   controllers,
      onRun:         onRun,
      runBusy:       runBusy,
      validate:      validate,
      onClear:       onClear,
      sectionLabels: sectionLabels,
      chipGroups:    chipGroups,    // ← NEW
      toggles:       toggles,
      togglesLabel:  togglesLabel,
      focusKey:      focusKey,
    )),
  );
}

// ---------------------------------------------------------------------------
// _ReportFilterSheet
// ---------------------------------------------------------------------------

class _ReportFilterSheet extends StatelessWidget {
  static const _maxHeightFraction = 0.9;

  final String                             title;
  final List<ReportFilterField>            fields;
  final Map<String, TextEditingController> controllers;
  final VoidCallback                       onRun;
  final RxBool?                            runBusy;
  final String? Function()?                validate;
  final VoidCallback?                      onClear;
  final Map<String, String>                sectionLabels;
  final List<ReportFilterChipGroup>        chipGroups;
  final List<ReportFilterToggle>           toggles;
  final String                             togglesLabel;
  final String?                            focusKey;

  const _ReportFilterSheet({
    required this.title,
    required this.fields,
    required this.controllers,
    required this.onRun,
    this.runBusy,
    this.validate,
    this.onClear,
    this.sectionLabels = const {},
    this.chipGroups    = const [],
    this.toggles       = const [],
    this.togglesLabel  = 'Options',
    this.focusKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: LayoutBuilder(builder: (ctx, constraints) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: constraints.maxHeight * _maxHeightFraction,
          ),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                          if (runBusy?.value ?? false) return;
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
              // Built eagerly (not a lazy ListView) so a field far down the
              // sheet exists to be scrolled to when its chip asks for it.
              Flexible(
                child: SingleChildScrollView(
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── text / date / browse fields (unchanged) ──────────────────
                    for (final field in fields) ...[
                      if (sectionLabels.containsKey(field.key))
                        _SheetSubheading(sectionLabels[field.key]!),
                      const SizedBox(height: 4),
                      _FieldWidget(
                        field:      field,
                        controller: controllers[field.key]!,
                        activate:   field.key == focusKey,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── ChoiceChip groups (NEW) ───────────────────────────────────
                    for (final group in chipGroups)
                      FilterFocusTarget(
                        filterKey: group.key,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SheetSubheading(group.label),
                            const SizedBox(height: 6),
                            _ChipGroupWidget(
                              group:      group,
                              controller: controllers[group.key]!,
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),

                    // ── On/off toggles (one FilterChip row) ───────────────────────
                    if (toggles.isNotEmpty)
                      FilterFocusTarget(
                        filterKey: toggles.first.key,
                        alsoMatches: [for (final t in toggles) t.key],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SheetSubheading(togglesLabel),
                            const SizedBox(height: 6),
                            _ToggleChipsWidget(
                              toggles:     toggles,
                              controllers: controllers,
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                  ],
                ),
                ),
              ),

              // ── action buttons ────────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    MediaQuery.paddingOf(ctx).bottom + 12),
                child: Row(
                  children: [
                    Expanded(child: _runButton(ctx, cs)),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _runButton(BuildContext ctx, ColorScheme cs) {
    Widget button([ValueChanged<String>? showValidation]) {
      void run() {
        if (runBusy?.value ?? false) return;
        final missing = fields
            .where((f) =>
                f.required &&
                (controllers[f.key]?.text.trim().isEmpty ?? true))
            .map((f) => f.label.replaceAll('*', '').trim())
            .toList();
        if (missing.isNotEmpty) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text('Required: ${missing.join(', ')}'),
              backgroundColor: cs.error,
            ),
          );
          return;
        }
        if (showValidation != null) {
          final error = validate?.call();
          if (error != null) {
            showValidation(error);
            return;
          }
        }
        Navigator.of(ctx).pop();
        onRun();
      }

      const icon = Icon(Icons.play_arrow_rounded);
      final style = FilledButton.styleFrom(padding: const EdgeInsets.all(14));
      if (runBusy case final busy?) {
        return AsyncFilledButton(
          busy: busy,
          onPressed: run,
          icon: icon,
          label: 'Run Report',
          style: style,
        );
      }
      return FilledButton.icon(
        onPressed: run,
        icon: icon,
        label: const Text('Run Report', style: TextStyle(fontSize: 15)),
        style: style,
      );
    }

    if (validate == null) return button();

    String? validationError;
    return StatefulBuilder(
      builder: (_, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (validationError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                validationError!,
                style: TextStyle(color: cs.error),
              ),
            ),
          button((message) => setState(() => validationError = message)),
        ],
      ),
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

  /// Start editing this field as soon as the sheet opens.
  final bool activate;

  const _FieldWidget({
    required this.field,
    required this.controller,
    this.activate = false,
  });

  @override
  State<_FieldWidget> createState() => _FieldWidgetState();
}

class _FieldWidgetState extends State<_FieldWidget> {
  // Tracks whether the controller has text so suffix icons rebuild correctly.
  bool _hasText = false;

  /// Used to focus a plain text field on [_FieldWidget.activate] when the
  /// caller did not supply its own node.
  FocusNode? _ownFocus;

  FocusNode? get _focusNode => widget.field.focusNode ?? _ownFocus;

  /// What a title-backed link field shows (the title); the real controller
  /// keeps the ID the report is filtered by.
  TextEditingController? _display;

  bool get _hasTitle =>
      widget.field.type == ReportFilterType.doctypeLink &&
      (widget.field.linkTitleField?.isNotEmpty ?? false) &&
      (widget.field.linkDoctype?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onTextChanged);
    if (_hasTitle) {
      _display = TextEditingController();
      _syncDisplay();
    }
    if (widget.activate) {
      if (widget.field.focusNode == null) _ownFocus = FocusNode();
      WidgetsBinding.instance.addPostFrameCallback((_) => _activate());
    }
  }

  /// Shows the remembered title for the current ID, or the ID while its
  /// title is looked up.
  void _syncDisplay() {
    final display = _display;
    if (display == null) return;
    final id = widget.controller.text.trim();
    final doctype = widget.field.linkDoctype!;
    final title = id.isEmpty ? null : LinkTitleCache.peek(doctype, id);
    display.text = title ?? id;
    if (id.isEmpty || title != null) return;
    final api = Get.isRegistered<ApiProvider>()
        ? Get.find<ApiProvider>()
        : ApiProvider();
    LinkTitleCache.resolve(doctype, widget.field.linkTitleField!, id, api)
        .then((resolved) {
      if (!mounted || resolved == null) return;
      if (widget.controller.text.trim() != id) return;
      setState(() => display.text = resolved); // helper text shows the ID now
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _display?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  /// Brings the field into view and starts editing it the way a tap would.
  Future<void> _activate() async {
    if (!mounted) return;
    await Scrollable.ensureVisible(context,
        alignment: 0.3, duration: const Duration(milliseconds: 200));
    if (!mounted) return;
    final field = widget.field;
    switch (field.type) {
      case ReportFilterType.datePicker:
        await _pickDate(context, widget.controller);
      case ReportFilterType.doctypeLink:
      case ReportFilterType.doctypeMultiLink:
        await _openDoctypeSheet(context, field, widget.controller);
      case ReportFilterType.switchToggle:
        break;
      case ReportFilterType.text:
      case ReportFilterType.batchBrowse:
        _focusNode?.requestFocus();
        // Caret at the end, ready to amend the current value.
        widget.controller.selection = TextSelection.collapsed(
            offset: widget.controller.text.length);
    }
  }

  void _onTextChanged() {
    _syncDisplay();
    final nowHasText = widget.controller.text.isNotEmpty;
    // Multi-link chips are derived from the full text, so every change repaints.
    if (nowHasText != _hasText ||
        widget.field.type == ReportFilterType.doctypeMultiLink) {
      setState(() => _hasText = nowHasText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final field      = widget.field;
    final controller = widget.controller;

    if (field.type == ReportFilterType.switchToggle) {
      final helperText = field.helperText;
      return Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(field.label),
          subtitle: helperText == null ? null : Text(helperText),
          value: controller.text == '1',
          onChanged: (checked) => controller.text = checked ? '1' : '',
        ),
      );
    }

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
        focusNode:  _focusNode,
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

    // ── doctypeMultiLink ───────────────────────────────────────────────────
    // Removable value chips + "Add" button; values live newline-joined in
    // the controller so the sheet's controller contract stays text-only.
    if (field.type == ReportFilterType.doctypeMultiLink) {
      final values = splitMultiValue(controller.text);
      final theme = Theme.of(context);
      final helperText = field.helperText;
      return InputDecorator(
        decoration: InputDecoration(
          labelText:  field.label,
          helper: helperText == null
              ? null
              : Text(
                  helperText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
          border:     const OutlineInputBorder(),
          prefixIcon: Icon(field.prefixIcon ?? Icons.list_alt_outlined),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 8),
        ),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final v in values)
              InputChip(
                label: Text(v),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onDeleted: () => controller.text = joinMultiValue(
                    values.where((x) => x != v)),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: Text(values.isEmpty ? 'Tap to select' : 'Add'),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onPressed: () => _openDoctypeSheet(context, field, controller),
            ),
          ],
        ),
      );
    }

    // ── doctypeLink ────────────────────────────────────────────────────────
    // Read-only tap-to-pick field. Opens _DoctypeLinkSheet.
    if (field.type == ReportFilterType.doctypeLink) {
      final id = controller.text.trim();
      final showingTitle =
          _display != null && id.isNotEmpty && _display!.text != id;
      return TextField(
        controller: _display ?? controller,
        focusNode:  field.focusNode,
        readOnly:   true,
        onTap: () => _openDoctypeSheet(context, field, controller),
        decoration: InputDecoration(
          labelText:  field.label,
          hintText:   field.hint ?? 'Tap to select',
          // The ID the report is filtered by, under the name it belongs to.
          helperText: showingTitle ? id : null,
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
      focusNode:  _focusNode,
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

    final isMultiple = field.type == ReportFilterType.doctypeMultiLink;
    final initialSelection = isMultiple ? splitMultiValue(ctrl.text) : null;
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DoctypeLinkSheet(
        doctype:  doctype,
        title:    field.label,
        filters:  field.linkFilters,
        titleField: field.linkTitleField,
        initialSelection: initialSelection,
      ),
    );

    if (!mounted || selected == null) return;
    ctrl.text = isMultiple ? joinMultiValue(selected) : selected.single;
  }
}

// ---------------------------------------------------------------------------
// _ToggleChipsWidget — one FilterChip per ReportFilterToggle, each bound to
// its own controller ('1' = on). Rebuilds when any bound controller changes
// (e.g. "Clear" resetting them from outside the sheet).
// ---------------------------------------------------------------------------

class _ToggleChipsWidget extends StatefulWidget {
  final List<ReportFilterToggle>           toggles;
  final Map<String, TextEditingController> controllers;

  const _ToggleChipsWidget({
    required this.toggles,
    required this.controllers,
  });

  @override
  State<_ToggleChipsWidget> createState() => _ToggleChipsWidgetState();
}

class _ToggleChipsWidgetState extends State<_ToggleChipsWidget> {
  Iterable<TextEditingController> get _bound =>
      widget.toggles.map((t) => widget.controllers[t.key]!);

  @override
  void initState() {
    super.initState();
    for (final c in _bound) {
      c.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    for (final c in _bound) {
      c.removeListener(_rebuild);
    }
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final t in widget.toggles)
          Builder(builder: (_) {
            final ctrl = widget.controllers[t.key]!;
            final on   = ctrl.text == '1';
            return FilterChip(
              avatar: t.icon != null ? Icon(t.icon, size: 16) : null,
              label: Text(t.label),
              selected: on,
              onSelected: (picked) => ctrl.text = picked ? '1' : '',
              selectedColor: cs.secondaryContainer,
              checkmarkColor: cs.onSecondaryContainer,
              labelStyle: TextStyle(
                color: on ? cs.onSecondaryContainer : cs.onSurface,
                fontWeight: on ? FontWeight.w600 : FontWeight.normal,
              ),
              side: BorderSide(color: on ? cs.secondary : cs.outlineVariant),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            );
          }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _DoctypeLinkSheet — searchable DocType list picker
// ---------------------------------------------------------------------------

class _DoctypeLinkSheet extends StatefulWidget {
  final String                  doctype;
  final String                  title;
  final Map<String, dynamic>?   filters;

  /// See [ReportFilterField.linkTitleField].
  final String?                 titleField;

  /// A non-null list enables multi-selection, including when it starts empty.
  final List<String>? initialSelection;

  const _DoctypeLinkSheet({
    required this.doctype,
    required this.title,
    this.filters,
    this.titleField,
    this.initialSelection,
  });

  @override
  State<_DoctypeLinkSheet> createState() => _DoctypeLinkSheetState();
}

class _DoctypeLinkSheetState extends State<_DoctypeLinkSheet> {
  final _searchCtrl  = TextEditingController();
  final _searchFocus = FocusNode();
  late final _selection = widget.initialSelection?.toSet();
  // The app's shared provider (session cookies, base URL) when registered.
  final _apiProvider = Get.isRegistered<ApiProvider>()
      ? Get.find<ApiProvider>()
      : ApiProvider();
  Timer? _debounce;

  List<LinkOption> _items = [];
  bool         _loading = true;
  String?      _errorMsg;

  @override
  void initState() {
    super.initState();
    _fetchItems('');
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _fetchItems(q),
    );
  }

  Future<void> _fetchItems(String q) async {
    setState(() {
      _loading  = true;
      _errorMsg = null;
    });
    try {
      // Shared link-option fetch: adds the doctype's active-record filter
      // (disabled = 0 / enabled = 1) so disabled records never show here.
      final titleField = widget.titleField;
      final options = titleField == null || titleField.isEmpty
          ? [
              for (final name in await _apiProvider.searchLinkOptions(
                widget.doctype,
                query:   q,
                filters: widget.filters,
                limit:   50,
              ))
                LinkOption(name: name, title: ''),
            ]
          : await _apiProvider.searchLinkOptionsWithTitle(
              widget.doctype,
              titleField: titleField,
              query:      q,
              filters:    widget.filters,
              limit:      50,
            );
      if (mounted) {
        setState(() {
          _items   = options;
          _loading = false;
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

  @override
  Widget build(BuildContext context) {
    final cs            = Theme.of(context).colorScheme;
    final textTheme     = Theme.of(context).textTheme;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final selection = _selection;

    return AnimatedPadding(
      padding:  EdgeInsets.only(bottom: keyboardHeight),
      duration: const Duration(milliseconds: 150),
      curve:    Curves.easeOut,
      child: DraggableScrollableSheet(
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

              // ── title ───────────────────────────────────────────────────
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
                    if (selection != null)
                      TextButton(
                        onPressed: () =>
                            Navigator.of(ctx).pop(selection.toList()),
                        child: const Text('Done'),
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
                  autofocus:  selection == null,
                  decoration: InputDecoration(
                    hintText:    (widget.titleField?.isNotEmpty ?? false)
                        ? 'Search ${widget.doctype} by name or ID…'
                        : 'Search ${widget.doctype}…',
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
                            onRetry: () => _fetchItems(_searchCtrl.text.trim()),
                          )
                        : _items.isEmpty
                            ? Center(
                                child: Text(
                                  _searchCtrl.text.trim().isEmpty
                                      ? 'No ${widget.doctype} records found'
                                      : 'No results for "${_searchCtrl.text}"',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              )
                            // ListTile inks on the nearest Material; without
                            // this the sheet's coloured box hides the ripple.
                            : Material(
                                type: MaterialType.transparency,
                                child: ListView.builder(
                                  controller: scrollCtrl,
                                  itemCount: _items.length,
                                  itemBuilder: (_, i) {
                                    final option = _items[i];
                                    final subtitle = option.hasDistinctTitle
                                        ? Text(option.name)
                                        : null;
                                    if (selection != null) {
                                      return CheckboxListTile(
                                        dense: true,
                                        title: Text(option.display),
                                        subtitle: subtitle,
                                        value: selection.contains(option.name),
                                        onChanged: (checked) {
                                          setState(() {
                                            if (checked == true) {
                                              selection.add(option.name);
                                            } else {
                                              selection.remove(option.name);
                                            }
                                          });
                                        },
                                      );
                                    }
                                    return ListTile(
                                      dense: true,
                                      title: Text(option.display),
                                      subtitle: subtitle,
                                      onTap: () =>
                                          Navigator.of(ctx).pop([option.name]),
                                      trailing: const Icon(
                                          Icons.chevron_right, size: 18),
                                    );
                                  },
                                ),
                              ),
              ),
            ],
          ),
        );
      },
      ),
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

// ---------------------------------------------------------------------------
// _ChipGroupWidget — mutually-exclusive ChoiceChip row for a chip group
// ---------------------------------------------------------------------------

class _ChipGroupWidget extends StatefulWidget {
  final ReportFilterChipGroup  group;
  final TextEditingController  controller;

  const _ChipGroupWidget({
    required this.group,
    required this.controller,
  });

  @override
  State<_ChipGroupWidget> createState() => _ChipGroupWidgetState();
}

class _ChipGroupWidgetState extends State<_ChipGroupWidget> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.controller.text;
    widget.controller.addListener(_syncFromController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    super.dispose();
  }

  /// Keeps local state in sync when the controller is cleared externally
  /// (e.g. when the user taps "Clear All Filters").
  void _syncFromController() {
    final v = widget.controller.text;
    if (v != _selected) setState(() => _selected = v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final option in widget.group.options)
          ChoiceChip(
            avatar: option.icon != null ? Icon(option.icon, size: 16) : null,
            label: Text(option.label),
            selected: _selected == option.value,
            onSelected: (picked) {
              setState(() {
                // Toggle-off: tapping the active chip deselects it.
                _selected = (picked && _selected != option.value)
                    ? option.value
                    : '';
                widget.controller.text = _selected;
              });
            },
            selectedColor: cs.secondaryContainer,
            labelStyle: TextStyle(
              color: _selected == option.value
                  ? cs.onSecondaryContainer
                  : cs.onSurface,
              fontWeight: _selected == option.value
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
            side: BorderSide(
              color: _selected == option.value
                  ? cs.secondary
                  : cs.outlineVariant,
            ),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
      ],
    );
  }
}

