import 'dart:async';

import 'package:flutter/material.dart';

/// Lets a tapped active-filter chip open its screen's filter sheet on that
/// filter, ready to edit, the way `showReportFilterSheet(focusKey:)` does for
/// report screens.
///
/// The screen wraps the sheet it opens in a [FilterFocusScope] naming the
/// filter; the sheet wraps each filter's section in a [FilterFocusTarget].
/// The matching target scrolls into view as the sheet opens and starts
/// editing: its [FilterFocusTarget.onActivate] runs (opening a picker, say),
/// or, without one, the first editable text field inside it takes focus with
/// the caret at the end. A target for a choice group (status chips) only
/// scrolls into view: the choices are then one tap away.
class FilterFocusScope extends InheritedWidget {
  FilterFocusScope({super.key, required String? focusKey, required super.child})
      : _request = _FocusRequest(focusKey);

  final _FocusRequest _request;

  /// The filter the sheet was opened for, or null.
  String? get focusKey => _request.key;

  /// Wraps [sheet] so the target for [focusKey] activates; a null key
  /// returns [sheet] unchanged.
  static Widget wrap(Widget sheet, {String? focusKey}) => focusKey == null
      ? sheet
      : FilterFocusScope(focusKey: focusKey, child: sheet);

  static FilterFocusScope? _of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FilterFocusScope>();

  @override
  bool updateShouldNotify(FilterFocusScope oldWidget) => false;
}

/// One request per opened sheet, so a target that is rebuilt or remounted
/// (inside an `Obx`, say) never re-opens its picker.
class _FocusRequest {
  _FocusRequest(this.key);
  final String? key;
  bool consumed = false;
}

/// A filter's section in a filter sheet; see [FilterFocusScope].
class FilterFocusTarget extends StatefulWidget {
  const FilterFocusTarget({
    super.key,
    required this.filterKey,
    this.alsoMatches = const [],
    this.onActivate,
    required this.child,
  });

  /// The key the screen's chip passes (usually the filter's fieldname).
  final String filterKey;

  /// Other chip keys this section edits (e.g. a range's from/to keys).
  final List<String> alsoMatches;

  /// Starts editing the filter; defaults to focusing the first editable text
  /// field in [child].
  final FutureOr<void> Function()? onActivate;

  final Widget child;

  @override
  State<FilterFocusTarget> createState() => _FilterFocusTargetState();
}

class _FilterFocusTargetState extends State<FilterFocusTarget> {
  @override
  void initState() {
    super.initState();
    final request = FilterFocusScope._of(context)?._request;
    final key = request?.key;
    if (request == null || request.consumed || key == null) return;
    if (key != widget.filterKey && !widget.alsoMatches.contains(key)) return;
    request.consumed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _activate());
  }

  Future<void> _activate() async {
    if (!mounted) return;
    await Scrollable.ensureVisible(context,
        alignment: 0.2, duration: const Duration(milliseconds: 200));
    if (!mounted) return;
    final onActivate = widget.onActivate;
    if (onActivate != null) {
      await onActivate();
      return;
    }
    final editable = _firstEditable(context);
    if (editable == null) return;
    editable.focusNode.requestFocus();
    // Caret at the end, ready to amend the current value.
    editable.controller.selection =
        TextSelection.collapsed(offset: editable.controller.text.length);
  }

  /// The first text field under [context] the user can type in.
  static EditableText? _firstEditable(BuildContext context) {
    EditableText? found;
    void visit(Element e) {
      if (found != null) return;
      final w = e.widget;
      if (w is EditableText && !w.readOnly) {
        found = w;
        return;
      }
      e.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
