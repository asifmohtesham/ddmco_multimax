import 'dart:async';

import 'package:flutter/foundation.dart';
// Keep the shared Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';

import 'report_field.dart';
import 'report_fields_controller.dart';
import 'report_fields_sheet.dart';

typedef AnchorRow = ({Object id, int index, Rect paintedBounds});

abstract interface class ReportFieldsAnchor {
  void captureBeforeLayout();
  void restoreAfterLayout();
  void setRouteVisible(bool visible);
  void cancelForUserScroll();
  void dispose();
}

ReportFieldsAnchor createReportFieldsAnchor({
  required ScrollController scroll,
  required Iterable<AnchorRow> Function() mountedRows,
  required Rect? Function() viewport,
  required int? Function(Object id) indexOf,
  required Iterable<Object> Function(Object id) fallbacks,
}) => _FieldsAnchor(scroll, mountedRows, viewport, indexOf, fallbacks);

class _FieldsAnchor implements ReportFieldsAnchor {
  _FieldsAnchor(
    this.scroll,
    this.mountedRows,
    this.viewport,
    this.indexOf,
    this.fallbacks,
  );

  final ScrollController scroll;
  final Iterable<AnchorRow> Function() mountedRows;
  final Rect? Function() viewport;
  final int? Function(Object) indexOf;
  final Iterable<Object> Function(Object) fallbacks;

  ({List<Object> ids, int index, double offset, ScrollPosition position})?
  _target;
  bool _visible = true;
  bool _scheduled = false;
  bool _disposed = false;
  int _attempts = 0;
  int _settledFrames = 0;

  ScrollPosition? get _position =>
      scroll.positions.length == 1 && scroll.position.hasContentDimensions
      ? scroll.position
      : null;

  @override
  void captureBeforeLayout() {
    if (_disposed || _target != null) return;
    final position = _position;
    final view = viewport();
    if (position == null ||
        position.pixels <= position.minScrollExtent ||
        view == null) {
      return;
    }
    final rows = mountedRows().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    for (final row in rows) {
      if (row.paintedBounds.overlaps(view)) {
        _target = (
          ids: [row.id, ...fallbacks(row.id)],
          index: row.index,
          offset: row.paintedBounds.top - view.top,
          position: position,
        );
        _attempts = 0;
        _settledFrames = 0;
        return;
      }
    }
  }

  @override
  void restoreAfterLayout() {
    if (_disposed || !_visible || _scheduled || _target == null) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed && _visible) _restore();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _restore() {
    final target = _target;
    final position = _position;
    final view = viewport();
    if (target == null ||
        !identical(target.position, position) ||
        view == null) {
      _target = null;
      return;
    }
    if (++_attempts > 24 || position == null) {
      _target = null;
      return;
    }

    final rows = mountedRows().toList();
    if (rows.isEmpty) {
      _target = null;
      return;
    }
    final mounted = {for (final row in rows) row.id: row};
    final available = target.ids.where(
      (id) => mounted.containsKey(id) || indexOf(id) != null,
    );
    final id = available.firstOrNull ?? target.ids.first;
    final row = mounted[id];
    double delta;
    if (row != null) {
      final box = row.paintedBounds;
      final offset = identical(id, target.ids.first) || id == target.ids.first
          ? target.offset
          : 0.0;
      final desiredTop = offset <= -box.height ? view.top : view.top + offset;
      delta = box.top - desiredTop;
    } else {
      final index = indexOf(id) ?? target.index;
      final nearest = rows.reduce(
        (a, b) => (a.index - index).abs() <= (b.index - index).abs() ? a : b,
      );
      final averageHeight =
          rows.fold<double>(0, (sum, r) => sum + r.paintedBounds.height) /
          rows.length;
      delta =
          nearest.paintedBounds.top -
          view.top +
          (index - nearest.index) * averageHeight;
    }
    final pixels = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((pixels - position.pixels).abs() < .5) {
      if (delta.abs() >= .5 || ++_settledFrames >= 3) {
        _target = null;
      } else {
        restoreAfterLayout();
      }
      return;
    }
    _settledFrames = 0;
    position.jumpTo(pixels);
    restoreAfterLayout();
  }

  @override
  void setRouteVisible(bool visible) {
    _visible = visible;
    if (visible) restoreAfterLayout();
  }

  @override
  void cancelForUserScroll() => _target = null;

  @override
  void dispose() {
    _disposed = true;
    _target = null;
  }
}

/// Paint boundaries and stable occurrence IDs for a results scroll view.
class ReportFieldsResults extends StatefulWidget {
  const ReportFieldsResults({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.result,
    required this.builder,
    this.occurrenceIds = const [],
    this.fallbacks,
    this.interactive,
    this.thumbVisibility,
    this.viewController,
  });

  final ReportFieldsController controller;
  final ScrollController scrollController;
  final Object? result;
  final List<Object> occurrenceIds;
  final Iterable<Object> Function(Object)? fallbacks;
  final bool? interactive;
  final bool? thumbVisibility;
  final ReportFieldsController? viewController;
  final Widget Function(BuildContext context, ReportFieldsOccurrences anchors)
  builder;

  @override
  State<ReportFieldsResults> createState() => _ReportFieldsResultsState();
}

class ReportFieldsOccurrences {
  ReportFieldsOccurrences._(this._state);

  final _ReportFieldsResultsState _state;

  Widget header(Widget child) =>
      KeyedSubtree(key: _state._headerKey, child: child);

  Widget footer(Widget child) =>
      KeyedSubtree(key: _state._footerKey, child: child);

  /// Excludes the painted portion of a heading pinned below the main header.
  Widget topObstruction(Widget child) =>
      _TopObstruction(scope: _state, child: child);

  Widget row(Object id, int index, Widget child) => _Occurrence(
    key: ValueKey(id),
    scope: _state,
    id: id,
    index: index,
    child: child,
  );
}

class _ReportFieldsResultsState extends State<ReportFieldsResults> {
  final _headerKey = GlobalKey();
  final _footerKey = GlobalKey();
  final _obstructions = <_TopObstructionState>{};
  final _rows = <_OccurrenceState>{};
  late final _handles = ReportFieldsOccurrences._(this);
  late ReportFieldsAnchor _anchor;
  late Worker _worker;
  Worker? _viewWorker;
  late FieldsState _last;
  late int _ownerGeneration;
  bool? _visible;
  bool _dragging = false;
  Map<Object, int> _indices = const {};

  @override
  void initState() {
    super.initState();
    _indexOccurrences();
    _connect();
  }

  void _indexOccurrences() {
    _indices = {
      for (final (index, id) in widget.occurrenceIds.indexed) id: index,
    };
  }

  void _connect() {
    _anchor = createReportFieldsAnchor(
      scroll: widget.scrollController,
      mountedRows: () sync* {
        for (final occurrence in _rows) {
          final box = _paintedBox(occurrence.context.findRenderObject());
          if (box != null) {
            yield (
              id: occurrence.widget.id,
              index: occurrence.widget.index,
              paintedBounds: box,
            );
          }
        }
      },
      viewport: _viewport,
      indexOf: (id) => _indices[id],
      fallbacks: (id) sync* {
        if (widget.fallbacks case final parent?) yield* parent(id);
        if (_indices[id] case final index?) {
          for (var step = 1; step <= 3; step++) {
            if (index + step < widget.occurrenceIds.length) {
              yield widget.occurrenceIds[index + step];
            }
            if (index >= step) yield widget.occurrenceIds[index - step];
          }
        }
      },
    );
    _last = widget.controller.state.value;
    _ownerGeneration = widget.controller.ownerGeneration;
    _worker = ever(widget.controller.state, (next) {
      final owner = widget.controller.ownerGeneration;
      if (_ownerGeneration != owner) {
        _anchor.cancelForUserScroll();
      } else if (!_dragging && _visibilityChanged(_last, next)) {
        _anchor.captureBeforeLayout();
        _anchor.restoreAfterLayout();
      }
      _ownerGeneration = owner;
      _last = next;
    });
    final viewController = widget.viewController;
    if (viewController != null) {
      var lastView = viewController.state.value;
      var viewOwner = viewController.ownerGeneration;
      _viewWorker = ever(viewController.state, (next) {
        if (viewOwner != viewController.ownerGeneration) {
          _anchor.cancelForUserScroll();
        } else if (!_dragging && _visibilityChanged(lastView, next)) {
          _anchor.captureBeforeLayout();
          _anchor.restoreAfterLayout();
        }
        viewOwner = viewController.ownerGeneration;
        lastView = next;
      });
    }
  }

  bool _visibilityChanged(FieldsState before, FieldsState after) {
    final fields = {
      ...before.definition.fields.map((field) => field.key),
      ...after.definition.fields.map((field) => field.key),
      ...before.snapshot.overrides.keys,
      ...after.snapshot.overrides.keys,
    };
    return fields.any((key) => before.shows(key) != after.shows(key));
  }

  Rect? _viewport() {
    final scroll = widget.scrollController;
    if (scroll.positions.length != 1) return null;
    final viewport = _paintedBox(
      scroll.position.context.notificationContext?.findRenderObject(),
    );
    if (viewport == null) return null;
    final header = _headerKey.currentContext?.findRenderObject();
    final headerExtent = header is RenderSliver
        ? header.geometry?.paintExtent ?? 0
        : 0.0;
    final footer = _paintedBox(_footerKey.currentContext?.findRenderObject());
    final headerBottom = viewport.top + headerExtent;
    var top = headerBottom;
    for (final obstruction in _obstructions) {
      final bounds = _paintedBox(obstruction.context.findRenderObject());
      if (bounds != null &&
          bounds.overlaps(viewport) &&
          bounds.top <= headerBottom &&
          bounds.bottom > top) {
        top = bounds.bottom;
      }
    }
    final bottom = footer == null || !footer.overlaps(viewport)
        ? viewport.bottom
        : footer.top;
    return bottom > top
        ? Rect.fromLTRB(viewport.left, top, viewport.right, bottom)
        : null;
  }

  static Rect? _paintedBox(RenderObject? object) {
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return null;
    }
    final bounds = MatrixUtils.transformRect(
      object.getTransformTo(null),
      Offset.zero & object.size,
    );
    return bounds.isFinite ? bounds : null;
  }

  @override
  void didUpdateWidget(ReportFieldsResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller ||
        widget.viewController != oldWidget.viewController ||
        widget.scrollController != oldWidget.scrollController) {
      _worker.dispose();
      _viewWorker?.dispose();
      _anchor.dispose();
      _connect();
      _anchor.setRouteVisible(_visible ?? true);
    }
    if (widget.result != oldWidget.result) {
      _anchor.cancelForUserScroll();
    }
    if (!listEquals(widget.occurrenceIds, oldWidget.occurrenceIds)) {
      _indexOccurrences();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    if (_visible == visible) return;
    final wasCovered = _visible == false;
    _visible = visible;
    _anchor.setRouteVisible(visible);
    if (visible && wasCovered) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(widget.controller.bind());
          unawaited(widget.viewController?.bind());
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth != 0) return false;
            final fromDrag = switch (notification) {
              ScrollStartNotification(:final dragDetails) =>
                dragDetails != null,
              ScrollUpdateNotification(:final dragDetails) =>
                dragDetails != null,
              OverscrollNotification(:final dragDetails) => dragDetails != null,
              _ => false,
            };
            if (fromDrag) {
              _dragging = true;
              _anchor.cancelForUserScroll();
            } else if (notification is ScrollEndNotification) {
              _dragging = false;
            }
            return false;
          },
          child: Scrollbar(
            controller: widget.scrollController,
            interactive: widget.interactive,
            thumbVisibility: widget.thumbVisibility,
            child: widget.builder(context, _handles),
          ),
        ),
      ),
      ReportFieldsFeedback(controller: widget.controller, atBottom: true),
      if (widget.viewController case final view?)
        ReportFieldsFeedback(controller: view, atBottom: true),
    ],
  );

  @override
  void dispose() {
    _worker.dispose();
    _viewWorker?.dispose();
    _anchor.dispose();
    super.dispose();
  }
}

class _TopObstruction extends StatefulWidget {
  const _TopObstruction({required this.scope, required this.child});

  final _ReportFieldsResultsState scope;
  final Widget child;

  @override
  State<_TopObstruction> createState() => _TopObstructionState();
}

class _TopObstructionState extends State<_TopObstruction> {
  @override
  void initState() {
    super.initState();
    widget.scope._obstructions.add(this);
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    widget.scope._obstructions.remove(this);
    super.dispose();
  }
}

class _Occurrence extends StatefulWidget {
  const _Occurrence({
    super.key,
    required this.scope,
    required this.id,
    required this.index,
    required this.child,
  });

  final _ReportFieldsResultsState scope;
  final Object id;
  final int index;
  final Widget child;

  @override
  State<_Occurrence> createState() => _OccurrenceState();
}

class _OccurrenceState extends State<_Occurrence> {
  @override
  void initState() {
    super.initState();
    widget.scope._rows.add(this);
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    widget.scope._rows.remove(this);
    super.dispose();
  }
}
