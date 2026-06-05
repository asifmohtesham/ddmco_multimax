/// Represents one row of the **Table MultiSelect** field `employee` on Job Card.
///
/// ERPNext fieldtype: Table MultiSelect → options: "Job Card Time Log"
/// The API returns each selected employee as a dict with at minimum
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
