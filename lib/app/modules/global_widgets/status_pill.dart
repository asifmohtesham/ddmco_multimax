import 'package:flutter/material.dart';

class StatusPill extends StatelessWidget {
  final String status;

  const StatusPill({super.key, required this.status});

  static const _successBg = Color(0xFFE5F8ED);
  static const _successText = Color(0xFF36A564);

  static const _dangerBg = Color(0xFFFFF5F5);
  static const _dangerText = Color(0xFFE54D4D);

  static const _warningBg = Color(0xFFFFF3E1);
  static const _warningText = Color(0xFFFFA00A);

  static const _infoBg = Color(0xFFEBF5FF);
  static const _infoText = Color(0xFF3688E5);

  static const _greyBg = Color(0xFFF0F4F7);
  static const _greyText = Color(0xFF5A6673);

  Color _getBackgroundColor(String status) {
    switch (status) {
    // Success (Green)
      case 'Active':
      case 'Enabled':
      case 'Completed':
      case 'Submitted':
      case 'Paid':
      case 'Settled':
        return _successBg;

    // Danger (Red)
      case 'Cancelled':
      case 'Rejected':
      case 'Expired':
      case 'Overdue':
      case 'Draft': // Kept as Red per your existing design, standard Frappe V15 uses Grey
        return _dangerBg;

    // Warning (Orange)
      case 'Not Saved':
      case 'Pending':
      case 'To Bill':
      case 'Hold':
        return _warningBg;

    // Info (Blue)
      case 'In Progress':
      case 'Open':
        return _infoBg;

    // Grey (Neutral)
      case 'Disabled':
      case 'Closed':
      case 'Passive':
      default:
        return _greyBg;
    }
  }

  Color _getTextColor(String status) {
    switch (status) {
    // Success
      case 'Active':
      case 'Enabled':
      case 'Completed':
      case 'Submitted':
      case 'Paid':
      case 'Settled':
        return _successText;

    // Danger
      case 'Cancelled':
      case 'Rejected':
      case 'Expired':
      case 'Overdue':
      case 'Draft':
        return _dangerText;

    // Warning
      case 'Not Saved':
      case 'Pending':
      case 'To Bill':
      case 'Hold':
        return _warningText;

    // Info
      case 'In Progress':
      case 'Open':
        return _infoText;

    // Grey
      case 'Disabled':
      case 'Closed':
      case 'Passive':
      default:
        return _greyText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: _getBackgroundColor(status),
        borderRadius: BorderRadius.circular(12.0),
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