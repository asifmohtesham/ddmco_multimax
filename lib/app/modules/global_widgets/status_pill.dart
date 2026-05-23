import 'package:flutter/material.dart';

class StatusPill extends StatelessWidget {
  final String status;

  /// When true, renders a compact 14dp-high variant for collapsed toolbars.
  final bool compact;

  const StatusPill({super.key, required this.status, this.compact = false});

  // ── Frappe UI design tokens (ERPNext v16 verbatim) ────────────────────────
  // surface-red-2 / ink-red-4
  static const _redBg    = Color(0xFFFFE7E7);
  static const _redText  = Color(0xFFCC2929);
  // surface-blue-2 / ink-blue-2
  static const _blueBg   = Color(0xFFE6F4FF);
  static const _blueText = Color(0xFF0289F7);
  // surface-amber-1 / ink-amber-3
  static const _amberBg   = Color(0xFFFDFAED);
  static const _amberText = Color(0xFFDB7706);
  // yellow/100 / yellow/700
  static const _yellowBg   = Color(0xFFFFF7D3);
  static const _yellowText = Color(0xFFAB6E05);
  // surface-green-2 / ink-green-3
  static const _greenBg   = Color(0xFFE4FAEB);
  static const _greenText = Color(0xFF278F5E);
  // surface-gray-2 / ink-gray-6  (default for unknown statuses)
  static const _grayBg   = Color(0xFFF3F3F3);
  static const _grayText = Color(0xFF525252);

  /// Returns `(background, textColour)` for the given ERPNext status string.
  ///
  /// Colour sources:
  /// - Red:    indicator.js docstatus==0/2; work_order_list.js; guess_style danger
  /// - Blue:   indicator.js docstatus==1; work_order_list.js
  /// - Amber:  delivery_note_list.js; purchase_order_list.js; work_order_list.js;
  ///           material_request_list.js; stock_entry_list.js; indicator.js __unsaved
  /// - Yellow: delivery_note_list.js; purchase_receipt_list.js;
  ///           material_request_list.js
  /// - Green:  all list views; guess_style success
  /// - Gray:   guess_style (no keyword match); explicit list view returns
  static (Color, Color) colourForStatus(String status) {
    switch (status) {
      // ── Red ───────────────────────────────────────────────────────────────
      case 'Draft':
      case 'Cancelled':
      case 'Open':
      case 'Not Started':
      case 'Stopped':
      case 'Rejected':
      case 'Expired':
      case 'Overdue':
        return (_redBg, _redText);

      // ── Blue ──────────────────────────────────────────────────────────────
      case 'Submitted':
      case 'Stock Reserved':
        return (_blueBg, _blueText);

      // ── Amber (orange) ────────────────────────────────────────────────────
      case 'To Bill':
      case 'On Hold':
      case 'Hold':
      case 'In Process':
      case 'Pending':
      case 'Not Saved':
      case 'To Receive and Bill':
      case 'To Receive':
      case 'Stock Partially Reserved':
      case 'Material Returned from WIP':
        return (_amberBg, _amberText);

      // ── Yellow ────────────────────────────────────────────────────────────
      case 'Partially Billed':
      case 'Partly Billed':
      case 'In Transit':
      case 'Partially Ordered':
      case 'Partially Received':
        return (_yellowBg, _yellowText);

      // ── Green ─────────────────────────────────────────────────────────────
      case 'Completed':
      case 'Active':
      case 'Paid':
      case 'Settled':
      case 'Enabled':
      case 'Closed':
      case 'Ordered':
      case 'Transferred':
      case 'Issued':
      case 'Received':
      case 'Goods Transferred':
        return (_greenBg, _greenText);

      // ── Gray (default) ────────────────────────────────────────────────────
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
