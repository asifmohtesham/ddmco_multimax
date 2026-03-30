import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/job_card_model.dart';
import 'package:multimax/app/data/models/job_card_time_log_model.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'job_card_form_controller.dart';

class JobCardFormScreen extends GetView<JobCardFormController> {
  const JobCardFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final jc = controller.jobCard.value;
      return Scaffold(
        appBar: MainAppBar(
          title: jc?.name ?? 'Job Card',
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
    return RefreshIndicator(
      onRefresh: controller.fetchDocument,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeaderCard(jc: jc),
            const SizedBox(height: 24),

            Obx(() => _StatusActionsRow(
                  jc:         controller.jobCard.value ?? jc,
                  controller: controller,
                )),
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
            // the edit icon.
            Obx(() {
              final current = controller.jobCard.value ?? jc;
              return _TimeLogsSection(
                logs:    current.timeLogs,
                isDraft: current.isEditable,
                onEdit:  controller.editTimeLog,
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
  final JobCard jc;
  const _HeaderCard({required this.jc});

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
                    StatusPill(status: jc.status),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: cs.outlineVariant),
          const SizedBox(height: 14),
          _DetailRow(
            icon: Icons.work_outline,
            label: 'Work Order',
            value: jc.workOrder,
          ),
          if ((jc.workstation ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            _DetailRow(
              icon: Icons.precision_manufacturing_outlined,
              label: 'Workstation',
              value: jc.workstation!,
            ),
          ],
          if ((jc.itemName ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            _DetailRow(
              icon: Icons.inventory_2_outlined,
              label: 'Item',
              value: jc.itemName!,
            ),
          ],
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
// Status action buttons
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
    final cs      = Theme.of(context).colorScheme;
    final loading = controller.isUpdatingStatus.value;

    if (jc.isCompleted || jc.isCancelled || jc.isSubmitted) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        if (jc.isOpen)
          Expanded(
            child: FilledButton.icon(
              onPressed: loading
                  ? null
                  : () => controller.updateStatus(
                      JobCard.statusWorkInProgress),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(14),
                backgroundColor: cs.primary,
              ),
              icon: loading
                  ? _spinner(Colors.white)
                  : const Icon(Icons.play_arrow_rounded),
              label: const Text('Start', style: TextStyle(fontSize: 15)),
            ),
          ),
        if (jc.isWorkInProgress) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: loading
                  ? null
                  : () => controller.updateStatus(JobCard.statusOpen),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(14),
                side: BorderSide(color: cs.primary),
              ),
              icon: loading
                  ? _spinner(cs.primary)
                  : const Icon(Icons.pause_rounded),
              label: const Text('Pause', style: TextStyle(fontSize: 15)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: loading
                  ? null
                  : () => controller.updateStatus(JobCard.statusCompleted),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(14),
                backgroundColor: cs.tertiary,
                foregroundColor: cs.onTertiary,
              ),
              icon: loading
                  ? _spinner(cs.onTertiary)
                  : const Icon(Icons.check_circle_outline),
              label:
                  const Text('Complete', style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
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
            ),
          );
        }),
        const SizedBox(height: 16),

        if (!controller.hasLinkedEmployee)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No Employee record is linked to your account. '
                    'Time logs will be recorded without an employee. '
                    'Contact your HR administrator.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),

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
                  controller.isAddingTimeLog.value ? 'Saving…' : 'Add Time Log',
                  style: const TextStyle(fontSize: 15),
                ),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(14)),
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
  final List<JobCardTimeLog>       logs;
  final bool                       isDraft;
  final void Function(JobCardTimeLog) onEdit;

  const _TimeLogsSection({
    required this.logs,
    required this.isDraft,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
            label: 'Time Logs (${logs.length})',
            icon: Icons.history_outlined),
        const SizedBox(height: 12),

        if (logs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'No time logs recorded yet',
                style: textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          )
        else
          ...logs.map(
            (log) => _TimeLogRow(
              log:     log,
              isDraft: isDraft,
              onEdit:  onEdit,
            ),
          ),
      ],
    );
  }
}

class _TimeLogRow extends StatelessWidget {
  final JobCardTimeLog             log;
  final bool                       isDraft;
  final void Function(JobCardTimeLog) onEdit;

  const _TimeLogRow({
    required this.log,
    required this.isDraft,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Duration badge ──
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Icon(Icons.timer_outlined,
                    size: 16, color: cs.onPrimaryContainer),
                const SizedBox(height: 2),
                Text(
                  log.formattedDuration,
                  style: textTheme.labelSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // ── Details ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatRange(log.fromTime, log.toTime),
                  style: textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.check_box_outlined,
                        size: 14, color: cs.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Qty: ${_fmtQty(log.completedQty)}',
                      style: textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if ((log.employeeName ?? log.employee ?? '').isNotEmpty)
                      ...[
                        const SizedBox(width: 12),
                        Icon(Icons.person_outline,
                            size: 14, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            log.employeeName ?? log.employee!,
                            style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                  ],
                ),
                if (log.isRunning)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.circle,
                            size: 8, color: Colors.green.shade600),
                        const SizedBox(width: 4),
                        Text(
                          'Running',
                          style: textTheme.labelSmall?.copyWith(
                              color: Colors.green.shade700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── Edit icon (draft only) ──
          if (isDraft)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Edit time log',
              icon: Icon(Icons.edit_outlined,
                  size: 18, color: cs.primary),
              onPressed: () => onEdit(log),
            ),
        ],
      ),
    );
  }

  String _formatRange(String? from, String? to) {
    if (from == null) return '—';
    final f = _truncate(from);
    if (to == null) return '$f → running';
    return '$f → ${_truncate(to)}';
  }

  String _truncate(String dt) =>
      dt.length >= 16 ? dt.substring(0, 16) : dt;

  String _fmtQty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);
}

// ────────────────────────────────────────────────────────────────────────────
// Small shared widgets
// ────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(
              color: cs.primary.withValues(alpha: 0.2), thickness: 1),
        ),
      ],
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Text('$label: ',
            style:
                textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        Expanded(
          child: Text(
            value,
            style: textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
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

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: cs.error),
          const SizedBox(height: 16),
          Text('Failed to load Job Card',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
