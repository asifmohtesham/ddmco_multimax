import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';

const jobCardSummaryFields = ReportFieldsDefinition(
  id: 'job_card_summary',
  sections: [(id: 'job_card', title: 'Job card')],
  alwaysShown: 'Job card, item, date, status, chart and total always show.',
  fields: [
    ReportField(
      key: 'name',
      column: (fieldname: 'name', label: 'Id'),
      section: 'job_card',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'posting_date',
      column: (fieldname: 'posting_date', label: 'Posting Date'),
      section: 'job_card',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'status',
      column: (fieldname: 'status', label: 'Status'),
      section: 'job_card',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'production_item',
      column: (fieldname: 'production_item', label: 'Production Item'),
      section: 'job_card',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'item_name',
      column: (fieldname: 'item_name', label: 'Item Name'),
      section: 'job_card',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'work_order',
      column: (fieldname: 'work_order', label: 'Work Order'),
      section: 'job_card',
      defaultVisible: true,
    ),
    ReportField(
      key: 'operation',
      column: (fieldname: 'operation', label: 'Operation'),
      section: 'job_card',
      defaultVisible: true,
    ),
    ReportField(
      key: 'workstation',
      column: (fieldname: 'workstation', label: 'Workstation'),
      section: 'job_card',
      defaultVisible: true,
    ),
    ReportField(
      key: 'total_completed_qty',
      column: (fieldname: 'total_completed_qty', label: 'Total Completed Qty'),
      section: 'job_card',
      defaultVisible: true,
    ),
    ReportField(
      key: 'total_time_in_mins',
      column: (
        fieldname: 'total_time_in_mins',
        label: 'Time Required (In Mins)',
      ),
      section: 'job_card',
      defaultVisible: true,
    ),
  ],
);

const jobCardSummaryFieldsAliases = <String, List<String>>{
  'name': ['id'],
  'total_time_in_mins': ['time_required_(in_mins)'],
};
