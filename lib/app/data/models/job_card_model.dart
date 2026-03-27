import 'package:multimax/app/data/models/job_card_time_log_model.dart';

/// Model for the **Job Card** DocType.
///
/// ERPNext path: Manufacturing → Job Card
/// Naming series : `PO-JOB.#####`
///
/// A Job Card is created from a Work Order Operation row and represents
/// the actual floor-execution unit for one manufacturing operation step.
/// Workers log time against it; on submit it updates the parent
/// Work Order Operation's [completedQty] and [actualOperationTime].
class JobCard {
  // ── Identity ──────────────────────────────────────────────────────────────
  final String name;
  final String company;

  // ── Work Order linkage ────────────────────────────────────────────────────
  /// Link → Work Order.
  final String workOrder;

  /// Link → Operation master (the operation name, e.g. "Cutting").
  final String operation;

  /// The child-row name of the Work Order Operation this card was made from.
  /// Used by ERPNext to update [completedQty] on the parent WO row.
  final String operationId;

  // ── Workstation ───────────────────────────────────────────────────────────
  final String? workstation;
  final String? workstationType;

  // ── Quantities ────────────────────────────────────────────────────────────
  /// Target qty to manufacture for this Job Card.
  final double forQuantity;

  /// Sum of [completedQty] across all time log rows.
  final double totalCompletedQty;

  /// Qty lost to process loss.
  final double processLossQty;

  /// Qty of raw material transferred to WIP warehouse for this card.
  final double transferredQty;

  // ── Status ────────────────────────────────────────────────────────────────
  /// One of the status constants defined below.
  final String status;

  static const String statusOpen                = 'Open';
  static const String statusWorkInProgress      = 'Work In Progress';
  static const String statusMaterialTransferred = 'Material Transferred';
  static const String statusOnHold              = 'On Hold';
  static const String statusSubmitted           = 'Submitted';
  static const String statusCancelled           = 'Cancelled';
  static const String statusCompleted           = 'Completed';

  // ── Warehouse & dates ─────────────────────────────────────────────────────
  final String? wipWarehouse;
  final String? postingDate;
  final String? expectedStartDate;
  final String? expectedEndDate;
  final String? actualStartDate;
  final String? actualEndDate;

  // ── Scheduling ────────────────────────────────────────────────────────────
  final int    sequenceId;
  final double hourRate;
  final double totalTimeInMins;

  // ── Batch / serial ────────────────────────────────────────────────────────
  final String? batchNo;
  final String? serialNo;
  final String? bomNo;

  // ── Misc ──────────────────────────────────────────────────────────────────
  final String? remarks;
  final String? project;
  final String? productionItem;
  final String? itemName;
  final bool    isCorrectiveJobCard;
  final int     docstatus;

  // ── Child table ───────────────────────────────────────────────────────────
  /// Time log entries recorded against this Job Card.
  final List<JobCardTimeLog> timeLogs;

  const JobCard({
    required this.name,
    required this.company,
    required this.workOrder,
    required this.operation,
    required this.operationId,
    this.workstation,
    this.workstationType,
    required this.forQuantity,
    required this.totalCompletedQty,
    required this.processLossQty,
    required this.transferredQty,
    required this.status,
    this.wipWarehouse,
    this.postingDate,
    this.expectedStartDate,
    this.expectedEndDate,
    this.actualStartDate,
    this.actualEndDate,
    required this.sequenceId,
    required this.hourRate,
    required this.totalTimeInMins,
    this.batchNo,
    this.serialNo,
    this.bomNo,
    this.remarks,
    this.project,
    this.productionItem,
    this.itemName,
    required this.isCorrectiveJobCard,
    required this.docstatus,
    this.timeLogs = const [],
  });

  // ── Computed ──────────────────────────────────────────────────────────────

  bool get isOpen                => status == statusOpen;
  bool get isWorkInProgress      => status == statusWorkInProgress;
  bool get isMaterialTransferred => status == statusMaterialTransferred;
  bool get isOnHold              => status == statusOnHold;
  bool get isCompleted           => status == statusCompleted;
  bool get isCancelled           => status == statusCancelled;
  bool get isSubmitted           => status == statusSubmitted;

  bool get isEditable => docstatus == 0;

  /// Progress as a fraction [0.0, 1.0] for LinearProgressIndicator.
  /// Guards against division by zero when forQuantity is 0.
  double get progress =>
      forQuantity > 0 ? (totalCompletedQty / forQuantity).clamp(0.0, 1.0) : 0.0;

  /// Whether the Job Card has any time log rows recorded.
  bool get hasTimeLogs => timeLogs.isNotEmpty;

  /// Total completed qty across all time logs (mirrors totalCompletedQty
  /// but computed locally — useful before a server refresh).
  double get localCompletedQty =>
      timeLogs.fold(0.0, (sum, log) => sum + log.completedQty);

  // ── Deserialization ───────────────────────────────────────────────────────

  factory JobCard.fromJson(Map<String, dynamic> json) {
    return JobCard(
      name:               json['name']                 as String? ?? '',
      company:            json['company']              as String? ?? '',
      workOrder:          json['work_order']           as String? ?? '',
      operation:          json['operation']            as String? ?? '',
      operationId:        json['operation_id']         as String? ?? '',
      workstation:        json['workstation']          as String?,
      workstationType:    json['workstation_type']     as String?,
      forQuantity:        (json['for_quantity']        as num?)?.toDouble() ?? 0.0,
      totalCompletedQty:  (json['total_completed_qty'] as num?)?.toDouble() ?? 0.0,
      processLossQty:     (json['process_loss_qty']    as num?)?.toDouble() ?? 0.0,
      transferredQty:     (json['transferred_qty']     as num?)?.toDouble() ?? 0.0,
      status:             json['status']               as String? ?? statusOpen,
      wipWarehouse:       json['wip_warehouse']        as String?,
      postingDate:        json['posting_date']         as String?,
      expectedStartDate:  json['expected_start_date']  as String?,
      expectedEndDate:    json['expected_end_date']    as String?,
      actualStartDate:    json['actual_start_date']    as String?,
      actualEndDate:      json['actual_end_date']      as String?,
      sequenceId:         (json['sequence_id']         as num?)?.toInt()    ?? 0,
      hourRate:           (json['hour_rate']           as num?)?.toDouble() ?? 0.0,
      totalTimeInMins:    (json['total_time_in_mins']  as num?)?.toDouble() ?? 0.0,
      batchNo:            json['batch_no']             as String?,
      serialNo:           json['serial_no']            as String?,
      bomNo:              json['bom_no']               as String?,
      remarks:            json['remarks']              as String?,
      project:            json['project']              as String?,
      productionItem:     json['production_item']      as String?,
      itemName:           json['item_name']            as String?,
      isCorrectiveJobCard: (json['is_corrective_job_card'] as int? ?? 0) == 1,
      docstatus:          json['docstatus']            as int? ?? 0,
      timeLogs: (json['time_logs'] as List? ?? [])
          .map((e) => JobCardTimeLog.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // ── Serialization ─────────────────────────────────────────────────────────
  // Only user-editable fields. Read-only server fields are excluded.

  Map<String, dynamic> toJson() => {
    if (remarks != null) 'remarks': remarks,
    if (project != null) 'project': project,
    if (workstation != null) 'workstation': workstation,
  };

  @override
  String toString() =>
      'JobCard(name: $name, workOrder: $workOrder, operation: $operation, '
      'status: $status, forQuantity: $forQuantity, '
      'totalCompletedQty: $totalCompletedQty, docstatus: $docstatus)';
}
