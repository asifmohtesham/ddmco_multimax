import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/job_card_model.dart';
import 'package:multimax/app/data/models/job_card_time_log_model.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'job_card_form_controller.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_bottom_sheet.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_config.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_column.dart';

class JobCardFormScreen extends GetView<JobCardFormController> {
  const JobCardFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final jc    = controller.jobCard.value;
      final title = jc?.name ?? 'Job Card';
      // Use the reactive observable so the AppBar subtitle updates live
      // whenever the employee is changed via the picker, without requiring
      // a full widget rebuild from jobCard.value.
      final assignedTo = controller.headerEmployeeName.value.isNotEmpty
          ? controller.headerEmployeeName.value
          : (jc?.primaryEmployeeDisplay ?? '');

      return Scaffold(
        appBar: MainAppBar(
          title: title,
          titleWidget: _JobCardAppBarTitle(
            title:      title,
            assignedTo: assignedTo.isEmpty ? null : assignedTo,
          ),
          status: jc?.status,
          onSave:     null,
          isSaving:   false,
          isDirty:    false,
          saveResult: SaveResult.idle,
        ),

        body: controller.isLoading.value
            ? const Center(child: CircularProgressIndicator())
            : jc == null
            ? _ErrorState(onRetry: controller.fetchDocument)
            : _JobCardFormBody(controller: controller, jc: jc),

        bottomNavigationBar: Obx(() {                    // ← outer Obx reads isLoading.value
          if (controller.isLoading.value || jc == null) return const SizedBox.shrink();
          return Builder(
            builder: (context) {
              final current = controller.jobCard.value ?? jc;   // ← same inner .value read, now inside the same Obx
              final mq = MediaQuery.of(context);
              return SafeArea(
                top: false,
                child: IntrinsicHeight(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      16, 10, 16,
                      (mq.padding.bottom > 0 ? mq.padding.bottom : 8),
                    ),
                    child: _StatusActionsRow(
                      jc:         current,
                      controller: controller,
                    ),
                  ),
                ),
              );
            },
          );
        }),
      );
    });
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Body
// ────────────────────────────────────────────────────────────────────────────

class _JobCardFormBody extends StatelessWidget {
  final JobCardFormController controller;
  final JobCard jc;
  const _JobCardFormBody({required this.controller, required this.jc});

  @override
  Widget build(BuildContext context) {
    // Reserve clearance below last item for the sticky bottom bar.
    // kBottomNavigationBarHeight (56) + typical action row (~64) + safe-area.
    final bottomClearance = MediaQuery.of(context).padding.bottom + 120.0;

    return RefreshIndicator(
      onRefresh: controller.fetchDocument,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomClearance),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeaderCard(jc: jc, controller: controller),
            const SizedBox(height: 24),

            // ── NEW: Expected schedule dates ────────────────────────────────────
            _ScheduleDatesRow(controller: controller),

            // ── NEW: Live elapsed timer (WIP only) ──────────────────────────────
            _ActiveTimerBanner(controller: controller),

            const SizedBox(height: 12),

            // Editable header fields — only when draft (docstatus == 0)
            Obx(() {
              final current = controller.jobCard.value ?? jc;
              if (!current.isEditable) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _EditableHeaderSection(controller: controller),
                ],
              );
            }),

            const SizedBox(height: 24),

            Obx(() {
              final current = controller.jobCard.value ?? jc;
              if (!current.isEditable ||
                  current.isCompleted ||
                  current.isCancelled) {
                return const SizedBox.shrink();
              }
              return _AddTimeLogSection(controller: controller);
            }),

            // Time logs list — passes isDraft so rows know whether to show
            // the edit and delete icons.
            Obx(() {
              final current = controller.jobCard.value ?? jc;
              return _TimeLogsSection(
                logs:     current.timeLogs,
                isDraft:  current.isEditable,
                onEdit:   controller.editTimeLog,
                onDelete: controller.deleteTimeLog,
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Header card
// ────────────────────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final JobCard                jc;
  final JobCardFormController  controller;
  const _HeaderCard({required this.jc, required this.controller});

  Color _statusColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (jc.status) {
      JobCard.statusWorkInProgress      => cs.primary,
      JobCard.statusCompleted           => cs.tertiary,
      JobCard.statusMaterialTransferred => cs.secondary,
      JobCard.statusCancelled           => cs.error,
      _                                 => cs.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final clr       = _statusColor(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: clr.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.build_outlined, color: clr, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      jc.operation,
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        StatusPill(status: jc.status),
                        // C5: show a "Submitted" chip when docstatus == 1
                        if (jc.docstatus == 1) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.tertiaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_outline,
                                    size: 11,
                                    color: cs.onTertiaryContainer),
                                const SizedBox(width: 3),
                                Text(
                                  'Submitted',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: cs.onTertiaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: cs.outlineVariant),
          const SizedBox(height: 10),
          // ── Operation Details section header ─────────────────────────────
          _SectionHeader(
            label: 'Operation Details',
            icon: Icons.tune_outlined,
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: cs.outlineVariant),

          // ── Work Order (read-only tile) ──────────────────────────────────
          _ReadOnlyFieldTile(
            icon: Icons.work_outline,
            label: 'Work Order',
            value: jc.workOrder,
          ),
          Divider(height: 1, indent: 52, color: cs.outlineVariant),

          // ── BOM No (read-only tile) ──────────────────────────────────────
          _ReadOnlyFieldTile(
            icon: Icons.account_tree_outlined,
            label: 'BOM No',
            value: jc.bomNo ?? '',
          ),
          Divider(height: 1, indent: 52, color: cs.outlineVariant),

          // ── Production Item (two-line read-only tile) ────────────────────
          _ReadOnlyFieldTile(
            icon: Icons.inventory_2_outlined,
            label: 'Production Item',
            value: jc.productionItem ?? '',
            subtitle: jc.itemName,
          ),
          Divider(height: 1, indent: 52, color: cs.outlineVariant),

          // ── Employees (ChoiceChips — multi-select) ───────────────────────
          _EmployeeChipsSection(jc: jc, controller: controller),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Progress',
                  style: textTheme.labelMedium
                      ?.copyWith(color: cs.onSurfaceVariant)),
              Text(
                '${_fmtQty(jc.totalCompletedQty)} / ${_fmtQty(jc.forQuantity)}',
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: jc.progress,
              minHeight: 8,
              backgroundColor: cs.outlineVariant,
              color: clr,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtQty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);
}

// ────────────────────────────────────────────────────────────────────────────
// Status action buttons  +  Submit button
// ────────────────────────────────────────────────────────────────────────────

class _StatusActionsRow extends StatelessWidget {
  final JobCard                jc;
  final JobCardFormController controller;
  const _StatusActionsRow({
    required this.jc,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ── Already submitted ────────────────────────────────────────────────
    if (jc.docstatus == 1) {
      return _SubmittedBanner();
    }

    // ── Cancelled — nothing to do ────────────────────────────────────────
    if (jc.isCancelled) {
      return const SizedBox.shrink();
    }

    final statusLoading   = controller.isUpdatingStatus.value;
    final submitLoading   = controller.isSubmitting.value;
    final anyLoading      = statusLoading || submitLoading;

    // C5: track whether the status row renders any button so the gap is
    // only inserted when there is actually content above the submit button.
    final bool hasStatusRow = !jc.isCompleted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Start / Resume / Pause / Complete row ──────────────────────────────────
        if (hasStatusRow)
          Row(
            children: [
              // Start — fresh job card, never been started
              if (jc.isOpen)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: anyLoading
                        ? null
                        : () => controller.updateStatus(JobCard.statusWorkInProgress),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(14),
                      backgroundColor: cs.primary,
                    ),
                    icon: statusLoading
                        ? _spinner(Colors.white)
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      statusLoading ? 'Starting...' : 'Start',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ),

              // Resume — previously paused (On Hold)
              if (jc.isOnHold)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: anyLoading
                        ? null
                        : () => controller.updateStatus(JobCard.statusWorkInProgress),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(14),
                      backgroundColor: cs.primary,
                    ),
                    icon: statusLoading
                        ? _spinner(Colors.white)
                        : const Icon(Icons.replay_rounded),
                    label: Text(
                      statusLoading ? 'Resuming...' : 'Resume',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ),

              // Pause + Complete — only while Work In Progress
              if (jc.isWorkInProgress) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: anyLoading ? null : controller.pauseJobCard,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(14),
                      side: BorderSide(color: cs.primary),
                    ),
                    icon: statusLoading
                        ? _spinner(cs.primary)
                        : const Icon(Icons.pause_rounded),
                    label: const Text('Pause', style: TextStyle(fontSize: 15)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: anyLoading
                        ? null
                        : () => controller.updateStatus(JobCard.statusCompleted),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(14),
                      backgroundColor: cs.tertiary,
                      foregroundColor: cs.onTertiary,
                    ),
                    icon: statusLoading
                        ? _spinner(cs.onTertiary)
                        : const Icon(Icons.check_circle_outline),
                    label: const Text('Complete', style: TextStyle(fontSize: 15)),
                  ),
                ),
              ],
            ],
          ),

        // C5: only insert gap when the status row above actually rendered.
        if (hasStatusRow) const SizedBox(height: 12),

        // ── Submit button — shown only after job started + time log added ──
        Obx(() {
          final submitting    = controller.isSubmitting.value;
          final canSubmit     = controller.canSubmit;
          final showHint      = controller.showSubmitHint;

          // If the job hasn't been started or has no time log, show a contextual
          // hint row instead of a confusing disabled button.
          if (showHint) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      jc.isOpen
                          ? 'To submit: 1) Start the job, 2) Add at least one time log.'
                          : 'To submit: add at least one time log, then try again.',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // Preconditions met — show the active submit button.
          return FilledButton.tonalIcon(
            onPressed: canSubmit ? controller.submitJobCard : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.all(14),
            ),
            icon: submitting
                ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: cs.onSecondaryContainer),
            )
                : const Icon(Icons.upload_outlined),
            label: Text(
              submitting ? 'Submitting…' : 'Submit Job Card',
              style: const TextStyle(fontSize: 15),
            ),
          );
        }),
      ],
    );
  }

  Widget _spinner(Color color) => SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
}

// ────────────────────────────────────────────────────────────────────────────
// Submitted banner — shown when docstatus == 1
// ────────────────────────────────────────────────────────────────────────────

class _SubmittedBanner extends StatelessWidget {
  const _SubmittedBanner();

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.tertiary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_outlined,
              size: 22, color: cs.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Submitted',
                  style: textTheme.titleSmall?.copyWith(
                    color: cs.onTertiaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'This Job Card is locked. No further edits are allowed.',
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onTertiaryContainer
                        .withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Add time log section
// ────────────────────────────────────────────────────────────────────────────

class _AddTimeLogSection extends StatelessWidget {
  final JobCardFormController controller;
  const _AddTimeLogSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: 'Add Time Log', icon: Icons.timer_outlined),
        const SizedBox(height: 12),

        _DateTimeField(
          label: 'Start Time *',
          controller: controller.startTimeController,
          onTap: () =>
              controller.pickDateTime(controller.startTimeController),
        ),
        const SizedBox(height: 12),

        _DateTimeField(
          label: 'Complete Time *',
          controller: controller.completeTimeController,
          onTap: () =>
              controller.pickDateTime(controller.completeTimeController),
        ),
        const SizedBox(height: 12),

        Obx(() {
          final remaining = controller.remainingQty;
          final overLimit = controller.isQtyOverLimit.value;
          final forQty    = controller.jobCard.value?.forQuantity ?? 0;

          return TextField(
            controller: controller.completedQtyController,
            keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText:  'Completed Qty *',
              border:     const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.numbers_outlined),
              helperText: !overLimit && forQty > 0
                  ? 'Remaining: ${_fmtQty(remaining)} '
                  '(WO Qty: ${_fmtQty(forQty)})'
                  : null,
              errorText: overLimit
                  ? 'Exceeds Work Order qty (max ${_fmtQty(forQty)}). '
                  'Remaining: ${_fmtQty(remaining)}'
                  : null,
              errorMaxLines: 2,
              suffixIcon: (!overLimit &&
                  forQty > 0 &&
                  remaining > 0)
                  ? TextButton(
                onPressed: () {
                  controller.completedQtyController.text =
                      _fmtQty(remaining);
                  controller.completedQtyController
                      .selection = TextSelection.fromPosition(
                    TextPosition(
                      offset: controller
                          .completedQtyController.text.length,
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 0),
                  tapTargetSize:
                  MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Use remaining'),
              )
                  : null,
            ),
          );
        }),
        const SizedBox(height: 16),

        // C5: theme-aware warning banner — replaced hard-coded Colors.orange.*
        // with ColorScheme tokens so it adapts to light / dark / high-contrast.
        if (!controller.hasLinkedEmployee)
          Builder(builder: (context) {
            final cs = Theme.of(context).colorScheme;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: cs.error.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: cs.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No Employee record is linked to your login. '
                          'Your hours will not be attributed to you in reports. '
                          'Ask HR to link your Employee record.',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

        Obx(() => SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: controller.canAddTimeLog
                    ? controller.addTimeLog
                    : null,
                icon: controller.isAddingTimeLog.value
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_circle_outline),
                label: Text(
                  controller.isAddingTimeLog.value
                      ? 'Adding…'
                      : 'Add Time Log',
                  style: const TextStyle(fontSize: 15),
                ),
                style:
                    FilledButton.styleFrom(padding: const EdgeInsets.all(14)),
              ),
            )),
        const SizedBox(height: 24),
      ],
    );
  }

  String _fmtQty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);
}

// ────────────────────────────────────────────────────────────────────────────
// Time logs list
// ────────────────────────────────────────────────────────────────────────────

class _TimeLogsSection extends StatelessWidget {
  final List<JobCardTimeLog>            logs;
  final bool                            isDraft;
  final void Function(JobCardTimeLog)   onEdit;
  final void Function(JobCardTimeLog)   onDelete;

  const _TimeLogsSection({
    required this.logs,
    required this.isDraft,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
            label: 'Time Logs (${logs.length})',
            icon: Icons.history_outlined),
        const SizedBox(height: 8),
        ...logs.map((log) => _TimeLogRow(
              log: log,
              isDraft: isDraft,
              onEdit: () => onEdit(log),
              onDelete: () => onDelete(log),
            )),
      ],
    );
  }
}

class _TimeLogRow extends StatelessWidget {
  final JobCardTimeLog log;
  final bool          isDraft;
  final VoidCallback  onEdit;
  final VoidCallback  onDelete;

  const _TimeLogRow({
    required this.log,
    required this.isDraft,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time icon
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.timer_outlined,
                size: 18, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 10),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // from → to
                Text(
                  '${_fmt(log.fromTime)} → ${_fmt(log.toTime)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                // duration + qty
                Row(
                  children: [
                    _Chip(
                      icon: Icons.schedule_outlined,
                      label: log.formattedDuration,
                    ),
                    const SizedBox(width: 6),
                    _Chip(
                      icon: Icons.check_circle_outline,
                      label: 'Qty: ${_fmtQty(log.completedQty)}',
                    ),
                  ],
                ),
                if ((log.employee ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  // Full name (primary) — shown when available
                  if ((log.employeeName ?? '').isNotEmpty)
                    Text(
                      log.employeeName!,
                      style: textTheme.labelSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  // Document name (secondary) — always shown when employee is set
                  Text(
                    log.employee!,
                    style: textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Edit / delete (draft only)
          if (isDraft) ...[
            IconButton(
              icon: Icon(Icons.edit_outlined,
                  size: 18, color: cs.primary),
              onPressed: onEdit,
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 18, color: cs.error),
              onPressed: onDelete,
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(String? dt) {
    if (dt == null || dt.isEmpty) return '—';
    return dt.length >= 16 ? dt.substring(0, 16) : dt;
  }

  String _fmtQty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: cs.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(label,
              style: textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String   label;
  final IconData icon;
  const _SectionHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}

class _DateTimeField extends StatelessWidget {
  final String                label;
  final TextEditingController controller;
  final VoidCallback          onTap;
  const _DateTimeField({
    required this.label,
    required this.controller,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      readOnly:   true,
      onTap:      onTap,
      decoration: InputDecoration(
        labelText:  label,
        border:     const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.schedule_outlined),
        suffixIcon: Icon(Icons.edit_calendar_outlined,
            size: 18, color: cs.primary),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 15, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: textTheme.bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        Expanded(
          child: Text(
            value,
            style: textTheme.bodySmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _JobCardAppBarTitle extends StatelessWidget {
  final String title;
  final String? assignedTo;

  const _JobCardAppBarTitle({
    required this.title,
    this.assignedTo,
  });

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final assigned  = (assignedTo ?? '').trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (assigned.isNotEmpty) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_outline,
                size: 14,
                color: cs.onPrimary.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Assigned to: $assigned',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: cs.onPrimary.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 16),
            Text('Failed to load Job Card',
                style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.',
              style: textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Read-only field tile (same visual as _EditableFieldTile, pencil hidden)
// Used for Work Order, BOM No, and Production Item inside _HeaderCard.
// ────────────────────────────────────────────────────────────────────────────

class _ReadOnlyFieldTile extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  /// Optional second line — shown in labelSmall/muted style below the value.
  final String?  subtitle;

  const _ReadOnlyFieldTile({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isEmpty   = value.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isEmpty ? '—' : value,
                  style: textTheme.bodyMedium?.copyWith(
                    color: isEmpty ? cs.onSurfaceVariant : cs.onSurface,
                    fontWeight: isEmpty ? FontWeight.normal : FontWeight.w600,
                  ),
                ),
                if ((subtitle ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // No trailing icon — read-only tiles never show a pencil.
          const SizedBox(width: 40), // preserve alignment with editable tiles
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Employee ChoiceChips section
// Renders one ChoiceChip per jc.employees entry; tapping immediately toggles
// via controller.toggleEmployee().  While isSavingEmployees, all chips are
// disabled.  Only shown when jc.isEditable (docstatus == 0).
// When not editable (submitted), falls back to a plain _ReadOnlyFieldTile.
// ────────────────────────────────────────────────────────────────────────────

class _EmployeeChipsSection extends StatelessWidget {
  final JobCard                jc;
  final JobCardFormController  controller;

  const _EmployeeChipsSection({
    required this.jc,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Submitted / cancelled — plain read-only display.
    if (!jc.isEditable) {
      return _ReadOnlyFieldTile(
        icon:  Icons.people_outline,
        label: 'Employees',
        value: jc.employees.isEmpty
            ? ''
            : jc.employees
            .map((e) => e.employeeName ?? e.employee)
            .join(', '),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.people_outline, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Employees',
                        style: textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        controller.loadAvailableEmployees();
                        Get.bottomSheet(
                          _EmployeePickerSheet(controller: controller),
                          isScrollControlled: true,
                          backgroundColor:
                          Theme.of(context).colorScheme.surface,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20)),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Obx(() {
                  final saving    = controller.isSavingEmployees.value;
                  final current   = controller.jobCard.value ?? jc;
                  final selected  = current.employees
                      .map((e) => e.employee)
                      .toSet();

                  if (current.employees.isEmpty) {
                    return Text(
                      'No employees assigned',
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    );
                  }

                  return Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: current.employees.map((emp) {
                      final isSelected = selected.contains(emp.employee);
                      return ChoiceChip(
                        label: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              emp.employee,
                              style: textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if ((emp.employeeName ?? '').isNotEmpty)
                              Text(
                                emp.employeeName!,
                                style: textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                        selected: isSelected,
                        onSelected: saving
                            ? null
                            : (_) => controller.toggleEmployee(emp.employee, emp.employeeName ?? ''),
                        avatar: saving
                            ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: cs.primary,
                          ),
                        )
                            : null,
                        selectedColor:
                        cs.primaryContainer,
                        checkmarkColor: cs.onPrimaryContainer,
                        labelPadding:
                        const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                      );
                    }).toList(),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Employee Picker Sheet
// Full list of Active employees; assigned ones are visually distinguished.
// Tapping any row immediately PATCHes ERP via controller.toggleEmployee().
// ────────────────────────────────────────────────────────────────────────────

class _EmployeePickerSheet extends StatefulWidget {
  final JobCardFormController controller;
  const _EmployeePickerSheet({required this.controller});

  @override
  State<_EmployeePickerSheet> createState() => _EmployeePickerSheetState();
}

class _EmployeePickerSheetState extends State<_EmployeePickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // ── Drag handle ───────────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
              child: Row(
                children: [
                  Icon(Icons.people_outline, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Assign Employees',
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Get.back(),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // ── Search ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _searchCtrl,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Search employees…',
                  prefixIcon: const Icon(Icons.search_outlined, size: 20),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  )
                      : null,
                ),
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              ),
            ),

            Divider(height: 1, color: cs.outlineVariant),

            // ── List ──────────────────────────────────────────────────────
            Expanded(
              child: Obx(() {
                final available = widget.controller.availableEmployees;
                final jc        = widget.controller.jobCard.value;
                final assigned  = jc?.employees.map((e) => e.employee).toSet()
                    ?? <String>{};
                final saving    = widget.controller.isSavingEmployees.value;

                if (available.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline,
                            size: 40, color: cs.onSurfaceVariant),
                        const SizedBox(height: 10),
                        Text(
                          'No employees found.',
                          style: textTheme.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: widget.controller.loadAvailableEmployees,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final filtered = _query.isEmpty
                    ? available
                    : available.where((e) {
                  final name = (e['employee_name'] ?? '').toString()
                      .toLowerCase();
                  final id   = (e['name'] ?? '').toString()
                      .toLowerCase();
                  return name.contains(_query) || id.contains(_query);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      'No results for "$_query"',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  );
                }

                return ListView.separated(
                  controller: scrollController,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, indent: 56, color: cs.outlineVariant),
                  itemBuilder: (context, i) {
                    final emp        = filtered[i];
                    final empId      = (emp['name'] ?? '').toString();
                    final empName    = (emp['employee_name'] ?? '').toString();
                    final dept       = (emp['department'] ?? '').toString();
                    final isAssigned = assigned.contains(empId);
                    final initial    = empName.isNotEmpty
                        ? empName[0].toUpperCase()
                        : '?';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isAssigned
                            ? cs.primary
                            : cs.surfaceContainerHighest,
                        child: Text(
                          initial,
                          style: TextStyle(
                            color: isAssigned
                                ? cs.onPrimary
                                : cs.onSurfaceVariant,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      title: Text(
                        empName,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        dept.isNotEmpty ? '$empId · $dept' : empId,
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      trailing: saving
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : Icon(
                        isAssigned
                            ? Icons.check_circle
                            : Icons.add_circle_outline,
                        color: isAssigned ? cs.primary : cs.onSurfaceVariant,
                      ),
                      onTap: saving
                          ? null
                          : () => widget.controller
                          .toggleEmployee(empId, empName),
                    );
                  },
                );
              }),
            ),
          ],
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Editable Header Fields
// Mirrors ERPNext's inline-edit UX: read-only display + trailing pencil icon.
// Hidden when docstatus != 0 (document not in draft).
// ────────────────────────────────────────────────────────────────────────────

class _EditableHeaderSection extends StatelessWidget {
  final JobCardFormController controller;
  const _EditableHeaderSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section heading
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: _SectionHeader(
              label: 'Operation and Workstation',
              icon: Icons.tune_outlined,
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),

          // Workstation — Link → Workstation DocType
          Obx(() => _EditableFieldTile(
            icon: Icons.precision_manufacturing_outlined,
            label: 'Workstation',
            value: controller.headerWorkstation.value,
            isSaving: controller.isSavingWorkstation.value,
            onEdit: () => _pickDocType(
              context,
              controller: controller,
              fieldKey: 'workstation',
              config: const DocTypePickerConfig(
                doctype: 'Workstation',
                title: 'Select Workstation',
                columns: [
                  DocTypePickerColumn(
                    fieldname: 'name',
                    label: 'Workstation',
                    isPrimary: true,
                    flex: 2,
                  ),
                  DocTypePickerColumn(
                    fieldname: 'workstation_type',
                    label: 'Type',
                    isSecondary: true,
                    flex: 2,
                  ),
                ],
                subtitleFields: ['production_capacity'],
                searchFields: ['name'],
                cacheKey: 'job_card_workstation_picker',
              ),
              displayField: 'name',
            ),
          )),

          Divider(height: 1, indent: 52, color: cs.outlineVariant),

          // WIP Warehouse — Link → Warehouse DocType
          Obx(() => _EditableFieldTile(
            icon: Icons.warehouse_outlined,
            label: 'WIP Warehouse',
            value: controller.headerWipWarehouse.value,
            isSaving: controller.isSavingWipWarehouse.value,
            onEdit: () => _pickDocType(
              context,
              controller: controller,
              fieldKey: 'wip_warehouse',
              config: const DocTypePickerConfig(
                doctype: 'Warehouse',
                title: 'Select WIP Warehouse',
                columns: [
                  DocTypePickerColumn(
                    fieldname: 'name',
                    label: 'Warehouse',
                    isPrimary: true,
                    flex: 3,
                  ),
                  DocTypePickerColumn(
                    fieldname: 'warehouse_type',
                    label: 'Type',
                    isSecondary: true,
                    flex: 2,
                  ),
                ],
                subtitleFields: ['company'],
                filters: [
                  ['Warehouse', 'is_group', '=', 0],
                ],
                searchFields: ['name'],
                cacheKey: 'job_card_wip_warehouse_picker',
              ),
              displayField: 'name',
            ),
          )),
        ],
      ),
    );
  }

  /// Opens the generic DocType picker sheet and saves the selected value.
  static Future<void> _pickDocType(
      BuildContext context, {
        required JobCardFormController controller,
        required String fieldKey,
        required DocTypePickerConfig config,
        required String displayField,
      }) async {
    final selected = await showDocTypePickerBottomSheet(context, config: config);
    if (selected == null) return;
    final value = (selected[displayField] ?? '').toString();
    if (value.isEmpty) return;
    await controller.saveHeaderField(fieldKey, value);
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Single editable field tile
// Shows current value (or an em-dash placeholder) with a trailing edit icon.
// The edit icon becomes a CircularProgressIndicator while [isSaving] is true.
// ────────────────────────────────────────────────────────────────────────────

class _EditableFieldTile extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final String       value;
  final bool         isSaving;
  final VoidCallback onEdit;

  const _EditableFieldTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.isSaving,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isEmpty   = value.isEmpty;

    return InkWell(
      onTap: isSaving ? null : onEdit,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isEmpty ? '—' : value,
                    style: textTheme.bodyMedium?.copyWith(
                      color: isEmpty ? cs.onSurfaceVariant : cs.onSurface,
                      fontWeight: isEmpty ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Trailing: spinner while saving, pencil when idle
            SizedBox(
              width: 32,
              height: 32,
              child: isSaving
                  ? Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
              )
                  : IconButton(
                icon: Icon(Icons.edit_outlined,
                    size: 17, color: cs.primary),
                onPressed: onEdit,
                tooltip: 'Edit $label',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Active timer banner — shown while job is Work In Progress
// ────────────────────────────────────────────────────────────────────────────

class _ActiveTimerBanner extends StatelessWidget {
  final JobCardFormController controller;
  const _ActiveTimerBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Obx(() {
      final elapsed = controller.elapsedDisplay.value;
      if (elapsed.isEmpty) return const SizedBox.shrink();

      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            // Pulsing timer icon
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1.0),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeInOut,
              builder: (_, v, child) =>
                  Opacity(opacity: v, child: child),
              onEnd: () {},
              child: Icon(Icons.timer_outlined,
                  size: 22, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Job In Progress',
                    style: textTheme.labelMedium?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Elapsed: $elapsed',
                    style: textTheme.headlineSmall?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: controller.canUpdateStatus
                  ? controller.pauseJobCard
                  : null,
              style: OutlinedButton.styleFrom(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                side: BorderSide(color: cs.onPrimaryContainer),
                visualDensity: VisualDensity.compact,
              ),
              icon: Icon(Icons.pause_rounded,
                  size: 16, color: cs.onPrimaryContainer),
              label: Text(
                'Pause',
                style: textTheme.labelSmall?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Expected schedule dates row (read-only)
// ────────────────────────────────────────────────────────────────────────────

class _ScheduleDatesRow extends StatelessWidget {
  final JobCardFormController controller;
  const _ScheduleDatesRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final jc = controller.jobCard.value;
      if (jc == null) return const SizedBox.shrink();

      final start = jc.expectedStartDate;
      final end = jc.expectedEndDate;
      if ((start == null || start.isEmpty) &&
          (end == null || end.isEmpty)) {
        return const SizedBox.shrink();
      }

      final cs = Theme
          .of(context)
          .colorScheme;
      final textTheme = Theme
          .of(context)
          .textTheme;

      // Determine urgency: if expected end is in the past → overdue.
      final bool isOverdue = _isOverdue(end);

      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isOverdue
              ? cs.errorContainer.withValues(alpha: 0.35)
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isOverdue
                ? cs.error.withValues(alpha: 0.4)
                : cs.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isOverdue ? Icons.warning_amber_rounded : Icons
                      .event_outlined,
                  size: 16,
                  color: isOverdue ? cs.error : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  isOverdue ? 'Scheduled (Overdue)' : 'Scheduled Window',
                  style: textTheme.labelSmall?.copyWith(
                    color: isOverdue ? cs.error : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateBlock(
                    label: 'Expected Start',
                    value: _fmtDate(start),
                    icon: Icons.play_circle_outline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateBlock(
                    label: 'Expected End',
                    value: _fmtDate(end),
                    icon: Icons.flag_outlined,
                    highlight: isOverdue,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  bool _isOverdue(String? end) {
    if (end == null || end.isEmpty) return false;
    try {
      final dt = end.contains(' ')
          ? DateFormat('yyyy-MM-dd HH:mm:ss').parse(end)
          : DateFormat('yyyy-MM-dd').parse(end);
      return dt.isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    // Trim to date + time (no seconds) for compact display.
    return raw.length >= 16 ? raw.substring(0, 16) : raw;
  }
}

class _DateBlock extends StatelessWidget {
  final String   label;
  final String   value;
  final IconData icon;
  final bool     highlight;

  const _DateBlock({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon,
                size: 12,
                color: highlight ? cs.error : cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: highlight ? cs.error : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: highlight ? cs.error : cs.onSurface,
          ),
        ),
      ],
    );
  }
}
