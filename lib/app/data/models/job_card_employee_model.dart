/// Represents a selected employee entry on a Job Card.
///
/// In ERPNext v15 employee tracking is via `Job Card Time Log` rows.
/// The API returns each entry as a dict with at minimum
/// `employee` (the link value) and optionally `employee_name`.
class JobCardEmployee {
  final String employee;
  final String? employeeName;

  const JobCardEmployee({
    required this.employee,
    this.employeeName,
  });

  factory JobCardEmployee.fromJson(Map<String, dynamic> json) {
    return JobCardEmployee(
      employee:     json['employee']      as String? ?? '',
      employeeName: json['employee_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'employee': employee,
  };

  @override
  String toString() => 'JobCardEmployee(employee: $employee, name: $employeeName)';
}
