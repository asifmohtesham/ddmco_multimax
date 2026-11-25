import 'dart:async';
import 'dart:math' as math;

// Keep the shared Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

import 'report_field.dart';
import 'report_fields_controller.dart';

class ReportFieldsAction extends StatefulWidget {
  const ReportFieldsAction({super.key, required this.controller});

  final ReportFieldsController controller;

  @override
  State<ReportFieldsAction> createState() => _ReportFieldsActionState();
}

class _ReportFieldsActionState extends State<ReportFieldsAction> {
  final _focus = FocusNode(debugLabel: 'Report Fields');
  bool _open = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _show() async {
    if (_open) return;
    _open = true;
    try {
      await showReportFieldsSheet(context, widget.controller);
    } finally {
      _open = false;
      if (mounted && ModalRoute.isCurrentOf(context) == true) {
        _focus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    focusNode: _focus,
    tooltip: 'Fields',
    icon: const Icon(Icons.view_agenda_outlined),
    onPressed: _show,
  );
}

Future<void> showReportFieldsSheet(
  BuildContext context,
  ReportFieldsController controller,
) {
  unawaited(controller.bind());
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.scheme.fg,
    builder: (_) => _FieldsSheet(controller: controller),
  );
}

class _FieldsSheet extends StatelessWidget {
  const _FieldsSheet({required this.controller});

  final ReportFieldsController controller;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .75,
    maxChildSize: .95,
    builder: (context, scroll) => Obx(() {
      final state = controller.state.value;
      final definition = state.definition;
      final theme = Theme.of(context);
      return Scrollbar(
        controller: scroll,
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            _FieldsSheetHeader(
              child: Material(
                color: context.scheme.fg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        20,
                        0,
                        8,
                        0,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                'Fields',
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                          ),
                          Flexible(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                              ),
                              onPressed:
                                  state.binding ||
                                      (!state.sessionOnly &&
                                          !state.snapshot.loaded) ||
                                      state.snapshot.failure ==
                                          FieldsFailure.load ||
                                      state.resetting ||
                                      state.retrying
                                  ? null
                                  : () =>
                                        unawaited(controller.resetToDefaults()),
                              child: const Text(
                                'Reset to defaults',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ReportFieldsFeedback(
                      controller: controller,
                      showProgress: true,
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.only(
                bottom: 16 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              sliver: SliverList.list(
                children: [
                  if (definition.alwaysShown.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(
                        definition.alwaysShown,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.scheme.textMuted,
                        ),
                      ),
                    ),
                  if (definition.fields.isEmpty && !state.binding)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Run the report to see its fields'),
                    ),
                  for (final section in definition.sections)
                    if (definition.fields.any(
                      (f) => f.section == section.id,
                    )) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: Semantics(
                          header: true,
                          child: Text(
                            section.title,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                      ),
                      for (final field in definition.fields)
                        if (field.section == section.id)
                          _tile(context, field, section, state),
                    ],
                ],
              ),
            ),
          ],
        ),
      );
    }),
  );

  Widget _tile(
    BuildContext context,
    ReportField field,
    FieldSection section,
    FieldsState state,
  ) {
    final prerequisite = field.requiresKey;
    final prerequisiteLabel = prerequisite == null
        ? null
        : state.label(prerequisite);
    final details = [
      if (field.hint case final hint?) hint,
      if (field.locked) 'Always shown',
      if (prerequisite != null &&
          prerequisiteLabel != null &&
          !state.shows(prerequisite))
        'Requires $prerequisiteLabel',
      if (state.pendingKeys.contains(field.key)) 'Saving…',
    ];
    final editable = controller.canEdit(field.key);
    final pending = state.pendingKeys.contains(field.key);
    void toggle(bool visible) =>
        unawaited(controller.setVisible(field.key, visible));
    return _FieldFocus(
      key: ValueKey(('field', field.key)),
      canFocus: editable || pending,
      activate: editable ? () => toggle(!state.selected(field.key)) : null,
      builder: (context, focused) => CheckboxListTile(
        key: ValueKey(field.key),
        minTileHeight: 48,
        tileColor: focused ? Theme.of(context).focusColor : null,
        controlAffinity: ListTileControlAffinity.leading,
        title: Semantics(
          label: '${section.title}, ${field.column.label}',
          excludeSemantics: true,
          child: Text(field.column.label),
        ),
        subtitle: details.isEmpty
            ? null
            : Text(
                details.join(' · '),
                style: TextStyle(color: context.scheme.textMuted),
              ),
        value: state.selected(field.key),
        onChanged: editable
            ? (checked) {
                if (checked != null) toggle(checked);
              }
            : null,
      ),
    );
  }
}

class _FieldFocus extends StatefulWidget {
  const _FieldFocus({
    super.key,
    required this.canFocus,
    required this.activate,
    required this.builder,
  });

  final bool canFocus;
  final VoidCallback? activate;
  final Widget Function(BuildContext context, bool focused) builder;

  @override
  State<_FieldFocus> createState() => _FieldFocusState();
}

class _FieldFocusState extends State<_FieldFocus> {
  bool _highlight = false;

  Object? _activate(Intent intent) {
    widget.activate?.call();
    return null;
  }

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    enabled: widget.canFocus,
    descendantsAreFocusable: false,
    onShowFocusHighlight: (visible) {
      if (mounted) setState(() => _highlight = visible);
    },
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: _activate),
      ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
        onInvoke: _activate,
      ),
    },
    child: widget.builder(context, _highlight),
  );
}

class _FieldsSheetHeader extends SingleChildRenderObjectWidget {
  const _FieldsSheetHeader({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFieldsSheetHeader();
}

/// Pins the measured controls when there is room for a field below them.
/// In a short extent the same controls scroll with the list.
class _RenderFieldsSheetHeader extends RenderSliverToBoxAdapter {
  bool _pinned = false;

  @override
  void performLayout() {
    super.performLayout();
    final box = child;
    final extent = geometry!.scrollExtent;
    _pinned = box != null && extent + 48 <= constraints.viewportMainAxisExtent;
    if (!_pinned) return;

    final available = constraints.remainingPaintExtent;
    geometry = SliverGeometry(
      scrollExtent: extent,
      paintExtent: math.min(extent, available),
      layoutExtent: (extent - constraints.scrollOffset).clamp(0.0, available),
      maxPaintExtent: extent,
      maxScrollObstructionExtent: extent,
      cacheExtent: geometry!.cacheExtent,
      hasVisualOverflow: true,
    );
    final parentData = box!.parentData! as SliverPhysicalParentData;
    parentData.paintOffset = Offset.zero;
  }

  @override
  double childMainAxisPosition(RenderBox child) =>
      _pinned ? 0 : super.childMainAxisPosition(child);

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    if (_pinned && constraints.scrollOffset > 0) {
      config.addTagForChildren(RenderViewport.excludeFromScrolling);
    }
  }
}

class ReportFieldsFeedback extends StatelessWidget {
  const ReportFieldsFeedback({
    super.key,
    required this.controller,
    this.showProgress = false,
    this.atBottom = false,
  });

  final ReportFieldsController controller;
  final bool showProgress;
  final bool atBottom;

  @override
  Widget build(BuildContext context) => Obx(() {
    final state = controller.state.value;
    final snapshot = state.snapshot;
    final busy =
        state.binding ||
        state.resetting ||
        state.retrying ||
        state.pendingKeys.isNotEmpty ||
        snapshot.saving;
    final failure = snapshot.failure;
    final message = switch (failure) {
      FieldsFailure.load => 'Could not load field settings',
      FieldsFailure.save => 'Could not save field settings',
      null when !showProgress && ModalRoute.isCurrentOf(context) == false =>
        null,
      null when state.binding => 'Loading field settings…',
      null when busy => 'Saving field settings…',
      null when showProgress && state.sessionOnly =>
        'Field settings apply to this session',
      null => null,
    };
    if (message == null) return const SizedBox.shrink();
    final scheme = context.scheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final errorInk = dark ? AppColors.red300 : AppColors.red700;
    final body = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 12, 4),
      child: Row(
        children: [
          if (busy) ...[
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
          ] else if (failure != null) ...[
            Icon(Icons.error_outline, size: 18, color: errorInk),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: failure == null ? scheme.textMuted : errorInk,
                ),
              ),
            ),
          ),
          if (failure != null)
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: busy ? null : () => unawaited(controller.retry()),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
    if (!atBottom) return body;
    return Material(
      color: scheme.fg,
      elevation: 2,
      child: SafeArea(top: false, child: body),
    );
  });
}
