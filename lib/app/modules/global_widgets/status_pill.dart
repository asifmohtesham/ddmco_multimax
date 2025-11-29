import 'package:flutter/material.dart';

class StatusPill extends StatelessWidget {
  final String status;

  const StatusPill({super.key, required this.status});

  Color _getBackgroundColor(String status) {
    switch (status) {
      case 'Completed':
      case 'Submitted': // Often green as well
        return const Color(0xFFE5F8ED); // Frappe Green Light
      case 'Draft':
        return const Color(0xFFFFF5F5); // Frappe Red Light
      case 'Cancelled':
        return const Color(0xFFFDECEC); // Frappe Red Light
      case 'To Bill':
      case 'Pending':
        return const Color(0xFFFFF3E1); // Frappe Orange Light
      case 'In Progress':
        return const Color(0xFFEBF5FF); // Frappe Blue Light
      default:
        return const Color(0xFFF0F4F7); // Frappe Grey Light
    }
  }

  Color _getTextColor(String status) {
    switch (status) {
      case 'Completed':
      case 'Submitted':
        return const Color(0xFF36A564); // Frappe Green
      case 'Draft':
        return const Color(0xFFE54D4D); // Frappe Red
      case 'Cancelled':
        return const Color(0xFFB34242); // Frappe Red Darker
      case 'To Bill':
      case 'Pending':
        return const Color(0xFFFFA00A); // Frappe Orange
      case 'In Progress':
        return const Color(0xFF3688E5); // Frappe Blue
      default:
        return const Color(0xFF5A6673); // Frappe Grey
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: _getBackgroundColor(status),
        borderRadius: BorderRadius.circular(12.0), // Rounded corners like Frappe
      ),
      child: Text(
        status,
        style: TextStyle(
          color: _getTextColor(status),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
