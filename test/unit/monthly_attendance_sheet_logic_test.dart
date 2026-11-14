import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/hr/reports/monthly_attendance_sheet/monthly_attendance_sheet_logic.dart';

/// Fixtures mirror the shapes `frappe.desk.query_report.run` actually returned
/// for "Monthly Attendance Sheet" on hrms 15.64.0 — day columns named
/// `dd-MM-yyyy` with `"1 Tue"` labels, a Shift column, one row per
/// (employee, shift), and Leave Type columns built from the site's own table.
void main() {
  const detailedColumns = [
    {
      'label': 'Employee',
      'fieldname': 'employee',
      'fieldtype': 'Link',
      'options': 'Employee',
      'width': 135,
    },
    {
      'label': 'Employee Name',
      'fieldname': 'employee_name',
      'fieldtype': 'Data',
      'width': 120,
    },
    {'label': 'Shift', 'fieldname': 'shift', 'fieldtype': 'Data', 'width': 120},
    {
      'label': '1 Tue',
      'fieldtype': 'Data',
      'fieldname': '01-09-2026',
      'width': 65,
    },
    {
      'label': '2 Wed',
      'fieldtype': 'Data',
      'fieldname': '02-09-2026',
      'width': 65,
    },
    {
      'label': '3 Thu',
      'fieldtype': 'Data',
      'fieldname': '03-09-2026',
      'width': 65,
    },
  ];

  group('parseDayColumns', () {
    test('takes only the day columns, in server order', () {
      final days = parseDayColumns(detailedColumns);

      expect(days.map((d) => d.key),
          ['01-09-2026', '02-09-2026', '03-09-2026']);
      expect(days.first.label, '1 Tue');
      expect(days.first.dayNumber, '1');
      expect(days.first.date, DateTime(2026, 9, 1));
      expect(days.last.date, DateTime(2026, 9, 3));
    });

    test('is empty for a summarized response, which has no day columns', () {
      expect(
        parseDayColumns(const [
          {'label': 'Employee', 'fieldname': 'employee', 'fieldtype': 'Link'},
          {
            'label': 'Total Present',
            'fieldname': 'total_present',
            'fieldtype': 'Float',
          },
        ]),
        isEmpty,
      );
    });

    test('survives a malformed response without throwing', () {
      expect(parseDayColumns(null), isEmpty);
      expect(parseDayColumns('not a list'), isEmpty);
      expect(parseDayColumns(const [null, 42]), isEmpty);
    });
  });

  group('SheetStatus.fromAbbr', () {
    test('maps every abbreviation the report emits', () {
      expect(SheetStatus.fromAbbr('P'), SheetStatus.present);
      expect(SheetStatus.fromAbbr('A'), SheetStatus.absent);
      expect(SheetStatus.fromAbbr('HD/A'), SheetStatus.halfDayAbsent);
      expect(SheetStatus.fromAbbr('HD/P'), SheetStatus.halfDayPresent);
      expect(SheetStatus.fromAbbr('WFH'), SheetStatus.workFromHome);
      expect(SheetStatus.fromAbbr('L'), SheetStatus.onLeave);
      expect(SheetStatus.fromAbbr('H'), SheetStatus.holiday);
      expect(SheetStatus.fromAbbr('WO'), SheetStatus.weeklyOff);
    });

    test('treats a blank or unknown day as unmarked', () {
      expect(SheetStatus.fromAbbr(''), SheetStatus.unmarked);
      expect(SheetStatus.fromAbbr(null), SheetStatus.unmarked);
      expect(SheetStatus.fromAbbr('ZZ'), SheetStatus.unmarked);
    });
  });

  group('parseDetailed', () {
    test('folds one row per shift into a single employee', () {
      final employees = parseDetailed(const [
        {
          'shift': 'Morning',
          'employee': 'HR-EMP-00001',
          'employee_name': 'Asif Mohtesham',
          '01-09-2026': 'P',
          '02-09-2026': 'P',
          '03-09-2026': 'WO',
        },
        {
          'shift': 'Afternoon',
          'employee': 'HR-EMP-00001',
          'employee_name': 'Asif Mohtesham',
          '01-09-2026': 'A',
          '02-09-2026': 'P',
          '03-09-2026': 'WO',
        },
      ]);

      expect(employees, hasLength(1));
      final employee = employees.single;
      expect(employee.hasMultipleShifts, isTrue);
      expect(employee.shifts.map((s) => s.shift), ['Morning', 'Afternoon']);

      // A day the two shifts disagree on keeps the one needing attention.
      expect(employee.statusOn('01-09-2026'), SheetStatus.absent);
      expect(employee.statusOn('02-09-2026'), SheetStatus.present);
      expect(employee.statusOn('03-09-2026'), SheetStatus.weeklyOff);
    });

    test('counts merged days, attention first', () {
      final employee = parseDetailed(const [
        {
          'shift': 'General',
          'employee': 'HR-EMP-00002',
          'employee_name': 'Chen Wei',
          '01-09-2026': 'P',
          '02-09-2026': 'A',
          '03-09-2026': 'P',
          '04-09-2026': '',
        },
      ]).single;

      expect(employee.counts[SheetStatus.absent], 1);
      expect(employee.counts[SheetStatus.present], 2);
      expect(employee.counts[SheetStatus.unmarked], 1);
      // Absent outranks present, so it leads the map.
      expect(employee.counts.keys.first, SheetStatus.absent);
    });

    test('applies group_by marker rows to the employees that follow', () {
      final employees = parseDetailed(const [
        {'department': 'Production'},
        {
          'shift': 'General',
          'employee': 'HR-EMP-00003',
          'employee_name': 'Ayesha Mohammed',
          '01-09-2026': 'P',
        },
        {'department': 'Sales'},
        {
          'shift': 'General',
          'employee': 'HR-EMP-00004',
          'employee_name': 'Rahul Nair',
          '01-09-2026': 'A',
        },
      ], groupByField: 'department');

      expect(employees.map((e) => e.employee),
          ['HR-EMP-00003', 'HR-EMP-00004']);
      expect(employees.first.group, 'Production');
      expect(employees.last.group, 'Sales');
    });

    test('reads the employee id as the name when employee_name is missing', () {
      final employee = parseDetailed(const [
        {'employee': 'HR-EMP-00009', '01-09-2026': 'P'},
      ]).single;

      expect(employee.employeeName, 'HR-EMP-00009');
      expect(employee.shifts.single.shift, '');
    });
  });

  group('summarized view', () {
    const summarizedColumns = [
      {'label': 'Employee', 'fieldname': 'employee', 'fieldtype': 'Link'},
      {
        'label': 'Employee Name',
        'fieldname': 'employee_name',
        'fieldtype': 'Data',
      },
      {
        'label': 'Total Present',
        'fieldname': 'total_present',
        'fieldtype': 'Float',
      },
      {
        'label': 'Total Leaves',
        'fieldname': 'total_leaves',
        'fieldtype': 'Float',
      },
      {
        'label': 'Total Absent',
        'fieldname': 'total_absent',
        'fieldtype': 'Float',
      },
      {
        'label': 'Total Holidays',
        'fieldname': 'total_holidays',
        'fieldtype': 'Float',
      },
      {
        'label': 'Unmarked Days',
        'fieldname': 'unmarked_days',
        'fieldtype': 'Float',
      },
      {
        'label': 'Leave Without Pay',
        'fieldname': 'leave_without_pay',
        'fieldtype': 'Float',
      },
      {
        'label': 'Sick Leave',
        'fieldname': 'sick_leave',
        'fieldtype': 'Float',
      },
      {
        'label': 'Total Late Entries',
        'fieldname': 'total_late_entries',
        'fieldtype': 'Float',
      },
      {
        'label': 'Total Early Exits',
        'fieldname': 'total_early_exits',
        'fieldtype': 'Float',
      },
    ];

    test('discovers the site Leave Type columns, excluding fixed totals', () {
      final leaveTypes = parseLeaveTypeColumns(summarizedColumns);

      expect(leaveTypes.map((c) => c.fieldname),
          ['leave_without_pay', 'sick_leave']);
      expect(leaveTypes.first.label, 'Leave Without Pay');
      for (final field in kSheetTotalFields) {
        expect(leaveTypes.map((c) => c.fieldname), isNot(contains(field)));
      }
    });

    test('parses numeric values and skips group markers', () {
      final rows = parseSummarized(const [
        {'department': 'Production'},
        {
          'employee': 'HR-EMP-00001',
          'employee_name': 'Asif Mohtesham',
          'total_present': 1,
          'total_leaves': 0,
          'total_absent': 2,
          'total_holidays': 4,
          'unmarked_days': 23,
          'sick_leave': 0,
          'total_late_entries': 1,
          'total_early_exits': 0,
        },
      ], groupByField: 'department');

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.group, 'Production');
      expect(row['total_absent'], 2);
      expect(row['unmarked_days'], 23);
      // A column the response omitted reads as zero, never null.
      expect(row['casual_leave'], 0);
    });
  });

  group('totalsLabel', () {
    test('summarises employees and day counts', () {
      final employees = parseDetailed(const [
        {
          'employee': 'HR-EMP-00001',
          'employee_name': 'Asif Mohtesham',
          '01-09-2026': 'P',
          '02-09-2026': 'A',
        },
        {
          'employee': 'HR-EMP-00002',
          'employee_name': 'Chen Wei',
          '01-09-2026': 'P',
          '02-09-2026': 'P',
        },
      ]);

      final label = totalsLabel(employees);
      expect(label, contains('2 employees'));
      expect(label, contains('3 present'));
      expect(label, contains('1 absent'));
    });

    test('falls back to the plain end marker with no rows', () {
      expect(totalsLabel(const []), 'End of results');
    });
  });
}
