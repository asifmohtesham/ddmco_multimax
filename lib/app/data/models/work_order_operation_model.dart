/// Model for the **Work Order Operation** child DocType.
///
/// ERPNext path: Manufacturing → Work Order → operations (child table)
/// DocType name : `Work Order Operation`  (istable: 1)
/// Parent       : `Work Order`
///
/// Each row represents one manufacturing operation step attached to a
/// Work Order.  It links to the [operation] master (Operation DocType)
/// and carries planned / actual time, cost, and completion tracking.
///
/// [pendingQty] is intentionally a method rather than a stored field.
/// The parent Work Order qty is not available inside this model, so
/// callers (controllers) must supply it.  This prevents stale state.
class WorkOrderOperation {
  // ── Identity ────────────────────────────────────────────────────────────────
  /// The child-row document name (e.g. `abc123xyz`).
  /// Used as `operation_id` when creating a Job Card.
  final String name;

  /// Link → Operation master DocType.
  /// The human-readable operation name (e.g. "Cutting", "Welding").
  final String operation;

  // ── Status & completion ──────────────────────────────────────────────────────
  /// One of [statusPending], [statusWip], [statusCompleted].
  final String status;

  /// Qty of finished goods for which this operation is complete.
  final double completedQty;

  /// Qty lost to process loss (read-only, set by Job Card submit).
  final double processLossQty;

  // ── Workstation ──────────────────────────────────────────────────────────────
  /// Link → Workstation Type (optional).
  final String? workstationType;

  /// Link → Workstation (optional).
  final String? workstation;

  // ── BOM link ─────────────────────────────────────────────────────────────────
  /// Link → BOM. Populated when `use_multi_level_bom` is enabled.
  final String? bom;

  // ── Sequencing ───────────────────────────────────────────────────────────────
  /// Sequence ID — controls the order Job Cards must be completed.
  final int sequenceId;

  // ── Planned time & cost ──────────────────────────────────────────────────────
  /// Planned start datetime string (ISO 8601). Read-only.
  final String? plannedStartTime;

  /// Planned end datetime string (ISO 8601). Read-only.
  final String? plannedEndTime;

  /// Estimated operation time **in minutes** (required field).
  final double timeInMins;

  /// Hour rate for cost calculation. Read-only (from Workstation).
  final double hourRate;

  /// Planned operating cost = (hourRate / 60) * timeInMins. Read-only.
  final double plannedOperatingCost;

  /// Max qty processed per Job Card batch. Read-only.
  final double batchSize;

  // ── Actual time & cost (read-only, updated by Job Card submit) ───────────────
  /// Actual start datetime string. Null until first time log.
  final String? actualStartTime;

  /// Actual end datetime string. Null until Job Card is submitted.
  final String? actualEndTime;

  /// Actual operation time in minutes (sum of time logs).
  final double actualOperationTime;

  /// Actual operating cost = (hourRate / 60) * actualOperationTime.
  final double actualOperatingCost;

  // ── Description ──────────────────────────────────────────────────────────────
  /// Optional operation description (HTML from Text Editor field).
  final String? description;

  // ── Status constants ─────────────────────────────────────────────────────────
  static const String statusPending   = 'Pending';
  static const String statusWip       = 'Work in Progress';
  static const String statusCompleted = 'Completed';

  const WorkOrderOperation({
    required this.name,
    required this.operation,
    required this.status,
    required this.completedQty,
    required this.processLossQty,
    this.workstationType,
    this.workstation,
    this.bom,
    required this.sequenceId,
    this.plannedStartTime,
    this.plannedEndTime,
    required this.timeInMins,
    required this.hourRate,
    required this.plannedOperatingCost,
    required this.batchSize,
    this.actualStartTime,
    this.actualEndTime,
    required this.actualOperationTime,
    required this.actualOperatingCost,
    this.description,
  });

  // ── Computed ─────────────────────────────────────────────────────────────────

  /// Qty still to be manufactured for this operation.
  ///
  /// [woQty] is the parent Work Order's `qty` field — supplied by the
  /// controller after fetch to keep this model free of parent references.
  ///
  /// Clamped to [0, woQty] to guard against over-completion edge cases.
  double pendingQty(double woQty) =>
      (woQty - completedQty - processLossQty).clamp(0.0, woQty);

  bool get isPending   => status == statusPending;
  bool get isWip       => status == statusWip;
  bool get isCompleted => status == statusCompleted;

  // ── Deserialization ──────────────────────────────────────────────────────────

  factory WorkOrderOperation.fromJson(Map<String, dynamic> json) {
    return WorkOrderOperation(
      name:                 json['name']                   as String? ?? '',
      operation:            json['operation']              as String? ?? '',
      status:               json['status']                 as String? ?? statusPending,
      completedQty:         (json['completed_qty']         as num?)?.toDouble() ?? 0.0,
      processLossQty:       (json['process_loss_qty']      as num?)?.toDouble() ?? 0.0,
      workstationType:      json['workstation_type']       as String?,
      workstation:          json['workstation']            as String?,
      bom:                  json['bom']                    as String?,
      sequenceId:           (json['sequence_id']           as num?)?.toInt()    ?? 0,
      plannedStartTime:     json['planned_start_time']     as String?,
      plannedEndTime:       json['planned_end_time']       as String?,
      timeInMins:           (json['time_in_mins']          as num?)?.toDouble() ?? 0.0,
      hourRate:             (json['hour_rate']             as num?)?.toDouble() ?? 0.0,
      plannedOperatingCost: (json['planned_operating_cost'] as num?)?.toDouble() ?? 0.0,
      batchSize:            (json['batch_size']            as num?)?.toDouble() ?? 0.0,
      actualStartTime:      json['actual_start_time']      as String?,
      actualEndTime:        json['actual_end_time']        as String?,
      actualOperationTime:  (json['actual_operation_time'] as num?)?.toDouble() ?? 0.0,
      actualOperatingCost:  (json['actual_operating_cost'] as num?)?.toDouble() ?? 0.0,
      description:          json['description']            as String?,
    );
  }

  // ── Serialization ────────────────────────────────────────────────────────────
  // Only the fields relevant for the `make_job_card` API payload.
  // Read-only fields (planned/actual times, costs) are excluded.

  Map<String, dynamic> toJobCardPayload({required double qty}) => {
    'name':        name,
    'operation':   operation,
    if (workstation != null) 'workstation': workstation,
    'qty':         qty,
    'pending_qty': qty,
    'sequence_id': sequenceId,
    'batch_size':  batchSize,
  };

  @override
  String toString() =>
      'WorkOrderOperation(name: $name, operation: $operation, '
      'status: $status, completedQty: $completedQty, sequenceId: $sequenceId)';
}
