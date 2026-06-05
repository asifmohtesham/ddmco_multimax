import 'package:flutter/material.dart';

class StatusPill extends StatelessWidget {
  final String status;

  /// When true, renders a compact 14dp-high variant for collapsed toolbars.
  final bool compact;

  const StatusPill({super.key, required this.status, this.compact = false});

  // ── Frappe v15 indicator-pill tokens ─────────────────────────────────────
  // Resolved from: --bg-{colour} / --text-on-{colour} in _colors.scss +
  // css_variables.scss.  Colour names match the $indicator-colors list in
  // indicator.scss — there is no "amber" pill class in Frappe.
  //
  // --bg-red   (red-100)    / --text-on-red   (red-700)
  static const _redBg    = Color(0xFFFFF0F0);
  static const _redText  = Color(0xFFB52A2A);
  // --bg-blue  (blue-100)   / --text-on-blue  (blue-700)
  static const _blueBg   = Color(0xFFEDF6FD);
  static const _blueText = Color(0xFF0070CC);
  // --bg-orange (orange-100) / --text-on-orange (orange-700)
  static const _orangeBg   = Color(0xFFFFF1E7);
  static const _orangeText = Color(0xFFBD3E0C);
  // --bg-yellow (yellow-100) / --text-on-yellow (yellow-700)
  static const _yellowBg   = Color(0xFFFFF7D3);
  static const _yellowText = Color(0xFFAB6E05);
  // --bg-green (green-100)  / --text-on-green (green-800)
  static const _greenBg   = Color(0xFFE4F5E9);
  static const _greenText = Color(0xFF16794C);
  // --bg-gray  (gray-100)   / --text-on-gray  (gray-700)  — default
  static const _grayBg   = Color(0xFFF3F3F3);
  static const _grayText = Color(0xFF525252);

  /// Returns `(background, textColour)` for the given ERPNext status string.
  ///
  /// Tokens sourced from Frappe v15 `_colors.scss` / `css_variables.scss`.
  /// Status→colour mapping sourced from `indicator.js` and per-DocType
  /// `*_list.js` files in frappe/frappe and frappe/erpnext (version-15 branch).
  static (Color, Color) colourForStatus(String status) {
    switch (status) {
      // ── Red: docstatus=0 Draft, docstatus=2 Cancelled, danger keywords ───
      case 'Draft':
      case 'Cancelled':
      case 'Canceled': // US spelling used in stock_entry_list.js
      case 'Open':
      case 'Stopped':
      case 'Rejected':
      case 'Expired':
      case 'Overdue':
        return (_redBg, _redText);

      // ── Blue: docstatus=1 Submitted, Enabled, job_card Material Transferred
      case 'Submitted':
      case 'Enabled':
      case 'Stock Reserved':
      case 'Material Transferred':
        return (_blueBg, _blueText);

      // ── Orange: __unsaved (Not Saved), warning / in-progress states ───────
      case 'Not Saved':
      case 'Not Started': // work_order_list.js: submitted-but-not-started
      case 'To Bill':
      case 'On Hold':
      case 'Hold':
      case 'In Process':
      case 'Work In Progress': // job_card_list.js
      case 'Pending':
      case 'To Receive and Bill':
      case 'To Receive':
      case 'Stock Partially Reserved':
      case 'Material Returned from WIP':
        return (_orangeBg, _orangeText);

      // ── Yellow: partially-fulfilled states ────────────────────────────────
      case 'Partially Billed':
      case 'Partly Billed':
      case 'In Transit':
      case 'Partially Ordered':
      case 'Partially Received':
        return (_yellowBg, _yellowText);

      // ── Green: terminal / successful states ───────────────────────────────
      case 'Completed':
      case 'Active':
      case 'Paid':
      case 'Settled':
      case 'Closed':
      case 'Ordered':
      case 'Transferred':
      case 'Issued':
      case 'Received':
      case 'Goods Transferred':
        return (_greenBg, _greenText);

      // ── Gray: return / neutral / unknown (guess_style default) ───────────
      case 'In Progress':
      case 'Disabled':
      case 'Passive':
      case 'Return':
      case 'Return Issued':
      case 'Goods In Transit':
      case 'To Pay':
      default:
        return (_grayBg, _grayText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, textColour) = colourForStatus(status);
    return Container(
      constraints: compact ? const BoxConstraints(minHeight: 14) : null,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        status,
        style: TextStyle(
          color:      textColour,
          fontWeight: compact ? FontWeight.w700 : FontWeight.w600,
          fontSize:   compact ? 9 : 11,
          height:     1.0,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
