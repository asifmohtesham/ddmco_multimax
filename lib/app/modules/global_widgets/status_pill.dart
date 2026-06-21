import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// ERPNext v15 status indicator pill. Colors come from the [AppColors] status
/// ramp: background = `<hue>500` @13% over the surface, text = `<hue>700` in
/// light / `<hue>300` in dark, with a leading `<hue>500` dot. Resolves to the
/// active brightness so it renders correctly in both themes.
class StatusPill extends StatelessWidget {
  final String status;

  /// Compact 14dp-high variant for collapsed toolbars.
  final bool compact;

  const StatusPill({super.key, required this.status, this.compact = false});

  /// The status ramp triple `(base500, text700, text300)` for a status string.
  static (Color, Color, Color) _ramp(String status) {
    switch (status) {
      case 'Draft':
      case 'Cancelled':
      case 'Canceled':
      case 'Open':
      case 'Stopped':
      case 'Rejected':
      case 'Expired':
      case 'Overdue':
        return (AppColors.red500, AppColors.red700, AppColors.red300);
      case 'Submitted':
      case 'Enabled':
      case 'Stock Reserved':
      case 'Material Transferred':
        return (AppColors.blue500, AppColors.blue700, AppColors.blue300);
      case 'Not Saved':
      case 'Not Started':
      case 'To Bill':
      case 'On Hold':
      case 'Hold':
      case 'In Process':
      case 'Work In Progress':
      case 'Pending':
      case 'To Receive and Bill':
      case 'To Receive':
      case 'Stock Partially Reserved':
      case 'Material Returned from WIP':
        return (AppColors.orange500, AppColors.orange700, AppColors.orange300);
      case 'Partially Billed':
      case 'Partly Billed':
      case 'In Transit':
      case 'Partially Ordered':
      case 'Partially Received':
        return (AppColors.yellow500, AppColors.yellow700, AppColors.yellow300);
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
        return (AppColors.green500, AppColors.green700, AppColors.green300);
      case 'In Progress':
      case 'Disabled':
      case 'Passive':
      case 'Return':
      case 'Return Issued':
      case 'Goods In Transit':
      case 'To Pay':
      default:
        return (AppColors.gray500, AppColors.gray700, AppColors.gray300);
    }
  }

  /// `(background, textColour)` for [status] at the given [brightness].
  static (Color, Color) colourForStatus(String status,
      {Brightness brightness = Brightness.light}) {
    final (base, text700, text300) = _ramp(status);
    final fg = AppScheme.of(brightness).fg;
    final bg = Color.alphaBlend(base.withValues(alpha: 0.13), fg);
    return (bg, brightness == Brightness.dark ? text300 : text700);
  }

  /// The leading-dot color (`<hue>500`) for [status].
  static Color dotColorForStatus(String status) => _ramp(status).$1;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final (bg, textColour) = colourForStatus(status, brightness: brightness);
    final dot = dotColorForStatus(status);
    final dotSize = compact ? 6.0 : 7.0;

    return Container(
      constraints: compact ? const BoxConstraints(minHeight: 14) : null,
      // ds.css .pill padding 5/11/5/9 (less left because of the dot); compact scales down.
      padding: compact
          ? const EdgeInsets.fromLTRB(7, 2, 9, 2)
          : const EdgeInsets.fromLTRB(9, 5, 11, 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          SizedBox(width: compact ? 5 : 7),
          Flexible(
            child: Text(
              status,
              style: TextStyle(
                color: textColour,
                fontWeight: compact ? FontWeight.w700 : FontWeight.w600,
                fontSize: compact ? 9 : 11,
                height: 1.0,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
