import 'package:flutter/material.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

/// Visual state of a single timeline checkpoint node.
enum CheckpointState {
  /// The checkpoint has happened — solid node, with time + detail.
  reached,

  /// The checkpoint has not happened yet — hollow, greyed node.
  upcoming,

  /// The data for this checkpoint is still being fetched — spinner node.
  loading,
}

/// A single node on the POS Upload progress timeline.
///
/// [timestamp] is the raw server creation string (or null when [state] is not
/// [CheckpointState.reached]); the widget renders it via
/// [FormattingHelper.getRelativeTime] so this object stays pure and the unit
/// tests are not time-dependent.
class TimelineCheckpoint {
  final String title;
  final String? docName;
  final String statusLabel;
  final String? timestamp;
  final String? detail;
  final CheckpointState state;

  /// 0..1 completion ratio for the Delivery Note checkpoint; null when not
  /// applicable (other checkpoints, or ordered qty is zero/unknown).
  final double? progress;

  const TimelineCheckpoint({
    required this.title,
    required this.statusLabel,
    required this.state,
    this.docName,
    this.timestamp,
    this.detail,
    this.progress,
  });
}

/// Builds the ordered list of progress checkpoints for a POS Upload.
///
/// Pure and widget-free so it can be unit-tested with primitives. The caller
/// (the [PosUploadTimeline] widget) reads these values off the controller.
///
/// DN-linked uploads (ML/KA) get three nodes: POS Upload → Delivery Note →
/// Packing Slips. Stock-Entry-linked uploads (MX/KX) get two: POS Upload →
/// Stock Entry. Because a Delivery Note and a Packing Slip can be created in
/// parallel, each node's reached-state is independent of the others.
List<TimelineCheckpoint> buildPosUploadTimeline({
  required bool isStockEntryUpload,
  // Node 1 — POS Upload itself.
  required String posUploadCreation,
  required int itemCount,
  // Linked document (Delivery Note or Stock Entry).
  required bool isLoadingLinked,
  required bool hasLinkedDoc,
  required String linkedDocName,
  required String linkedDocCreation,
  // Delivery-Note-only quantities.
  double? orderedQty,
  double? deliveredQty,
  // Packing Slip layer (DN path only).
  required bool isLoadingPackingSlips,
  required int packingSlipCount,
  required String? earliestPackingSlipCreation,
  required int packedItems,
  required int totalSerials,
}) {
  final node1 = TimelineCheckpoint(
    title: 'POS Upload Created',
    statusLabel: 'Pending',
    state: CheckpointState.reached,
    timestamp: posUploadCreation,
    detail: '$itemCount items',
  );

  if (isStockEntryUpload) {
    return [node1, _linkedNode('Stock Entry', 'Linked', isLoadingLinked, hasLinkedDoc, linkedDocName, linkedDocCreation)];
  }

  // ── Delivery Note node (#2) ──────────────────────────────────────────────
  final CheckpointState dnState = isLoadingLinked
      ? CheckpointState.loading
      : (hasLinkedDoc ? CheckpointState.reached : CheckpointState.upcoming);

  double? progress;
  String? dnDetail;
  if (dnState == CheckpointState.reached) {
    if (orderedQty != null && orderedQty > 0 && deliveredQty != null) {
      progress = (deliveredQty / orderedQty).clamp(0.0, 1.0);
      final pct = (progress * 100).round();
      dnDetail =
          '${FormattingHelper.formatQty(deliveredQty)} / ${FormattingHelper.formatQty(orderedQty)} qty · $pct%';
    } else if (deliveredQty != null) {
      dnDetail = '${FormattingHelper.formatQty(deliveredQty)} qty';
    }
  }

  final node2 = TimelineCheckpoint(
    title: 'Delivery Note',
    statusLabel: 'In Progress',
    state: dnState,
    docName: dnState == CheckpointState.reached ? linkedDocName : null,
    timestamp: dnState == CheckpointState.reached ? linkedDocCreation : null,
    detail: dnDetail,
    progress: progress,
  );

  // ── Packing Slips node (#3) ──────────────────────────────────────────────
  final CheckpointState psState = isLoadingPackingSlips
      ? CheckpointState.loading
      : (packingSlipCount > 0
          ? CheckpointState.reached
          : CheckpointState.upcoming);

  final node3 = TimelineCheckpoint(
    title: 'Packing Slips',
    statusLabel: 'Packing',
    state: psState,
    timestamp:
        psState == CheckpointState.reached ? earliestPackingSlipCreation : null,
    detail: psState == CheckpointState.reached
        ? '$packingSlipCount slip${packingSlipCount == 1 ? '' : 's'} · $packedItems / $totalSerials items packed'
        : null,
  );

  return [node1, node2, node3];
}

TimelineCheckpoint _linkedNode(
  String title,
  String reachedLabel,
  bool isLoading,
  bool hasLinkedDoc,
  String linkedDocName,
  String linkedDocCreation,
) {
  final state = isLoading
      ? CheckpointState.loading
      : (hasLinkedDoc ? CheckpointState.reached : CheckpointState.upcoming);
  return TimelineCheckpoint(
    title: title,
    statusLabel: reachedLabel,
    state: state,
    docName: state == CheckpointState.reached ? linkedDocName : null,
    timestamp: state == CheckpointState.reached ? linkedDocCreation : null,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Rendering
// ─────────────────────────────────────────────────────────────────────────────

/// Vertical timeline rail rendering a list of [TimelineCheckpoint]s.
///
/// Purely presentational — the reactive wiring (reading controller state and
/// calling [buildPosUploadTimeline]) lives in the caller, so this widget is
/// trivially widget-testable with hand-built checkpoint lists.
class PosUploadTimeline extends StatelessWidget {
  final List<TimelineCheckpoint> checkpoints;
  const PosUploadTimeline({super.key, required this.checkpoints});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < checkpoints.length; i++)
          _TimelineRow(
            checkpoint: checkpoints[i],
            isLast: i == checkpoints.length - 1,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final TimelineCheckpoint checkpoint;
  final bool isLast;
  const _TimelineRow({required this.checkpoint, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Rail (dot + connecting line) ──────────────────────────────────
          SizedBox(
            width: 28,
            child: Column(
              children: [
                _Dot(state: checkpoint.state),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: cs.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          // ── Content ───────────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16, left: 4),
              child: _content(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reached = checkpoint.state == CheckpointState.reached;
    final loading = checkpoint.state == CheckpointState.loading;
    final muted = cs.onSurfaceVariant;

    final rows = <Widget>[
      Text(
        checkpoint.title,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: (reached || loading) ? null : muted,
        ),
      ),
    ];

    if (reached) {
      final rel = FormattingHelper.getRelativeTime(checkpoint.timestamp);
      rows.add(Text(
        '${checkpoint.statusLabel} · $rel',
        style: theme.textTheme.labelSmall
            ?.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
      ));
      if (checkpoint.docName != null && checkpoint.docName!.isNotEmpty) {
        rows.add(Text(checkpoint.docName!, style: theme.textTheme.bodySmall));
      }
      if (checkpoint.detail != null) {
        rows.add(Text(
          checkpoint.detail!,
          style: theme.textTheme.labelSmall?.copyWith(color: muted),
        ));
      }
      if (checkpoint.progress != null) {
        rows.add(Padding(
          padding: const EdgeInsets.only(top: 4, right: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
                value: checkpoint.progress, minHeight: 4),
          ),
        ));
      }
    } else if (loading) {
      rows.add(Text('${checkpoint.statusLabel}…',
          style: theme.textTheme.labelSmall?.copyWith(color: muted)));
    } else {
      rows.add(Text('Awaiting',
          style: theme.textTheme.labelSmall?.copyWith(color: muted)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          Padding(padding: const EdgeInsets.only(bottom: 2), child: r),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final CheckpointState state;
  const _Dot({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (state == CheckpointState.loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 1),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final reached = state == CheckpointState.reached;
    return Container(
      margin: const EdgeInsets.only(top: 2),
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: reached ? cs.primary : Colors.transparent,
        border: Border.all(color: reached ? cs.primary : cs.outline, width: 2),
      ),
      child: reached ? Icon(Icons.check, size: 10, color: cs.onPrimary) : null,
    );
  }
}
