import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';

/// ERPNext v15 status indicator pill. Colors come from the [AppColors] status
/// ramp: background = `<hue>500` @13% over the surface, text = `<hue>700` in
/// light / `<hue>300` in dark, with a leading `<hue>500` dot. Resolves to the
/// active brightness so it renders correctly in both themes.
class StatusPill extends StatelessWidget {
  final String status;
  final bool _isPosUpload;

  /// Use the colour of another status while keeping [status] as the label.
  final String? colorStatus;

  /// Compact 14dp-high variant for collapsed toolbars.
  final bool compact;

  /// Use readable, wrapping text when space is constrained.
  final bool wrapLabel;

  const StatusPill({
    super.key,
    required this.status,
    this.colorStatus,
    this.compact = false,
    this.wrapLabel = false,
  }) : _isPosUpload = false;

  /// POS labels outside the canonical states use the neutral ramp.
  const StatusPill.posUpload({
    super.key,
    required this.status,
    this.compact = false,
  }) : colorStatus = null,
       wrapLabel = false,
       _isPosUpload = true;

  static const _neutralRamp = (
    AppColors.gray500,
    AppColors.gray700,
    AppColors.gray300,
  );

  /// The status ramp triple `(base500, text700, text300)` for a status string.
  static (Color, Color, Color) _ramp(
    String status, {
    bool isPosUpload = false,
  }) {
    if (isPosUpload && !PosUpload.statusOptions.contains(status)) {
      return _neutralRamp;
    }
    switch (status) {
      case 'Draft':
      case 'Cancelled':
      case 'Canceled':
      case 'Open':
      case 'Stopped':
      case 'Rejected':
      case 'Expired':
      case 'Overdue':
      case 'Absent':
      case 'Delivery Return':
        return (AppColors.red500, AppColors.red700, AppColors.red300);
      case 'Submitted':
      case 'Enabled':
      case 'Stock Reserved':
      case 'Material Transferred':
      case 'Holiday':
      case 'On Leave':
      case 'Out for Delivery':
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
      case 'To Deliver and Bill':
      case 'To Deliver':
      case 'Stock Partially Reserved':
      case 'Material Returned from WIP':
      case 'Late':
      case 'Upcoming':
        return (AppColors.orange500, AppColors.orange700, AppColors.orange300);
      case 'Partially Billed':
      case 'Partly Billed':
      case 'In Transit':
      case 'Partially Ordered':
      case 'Partially Received':
      case 'Half Day':
      case 'No check-out':
      case 'Missing punch':
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
      case 'Present':
      case 'Delivered':
        return (AppColors.green500, AppColors.green700, AppColors.green300);
      case 'Work From Home':
        return (AppColors.purple500, AppColors.purple700, AppColors.purple300);
      case 'In Progress':
      case 'Disabled':
      case 'Passive':
      case 'Return':
      case 'Return Issued':
      case 'Goods In Transit':
      case 'To Pay':
      default:
        return _neutralRamp;
    }
  }

  static Color _background(Color base, Brightness brightness) =>
      Color.alphaBlend(
        base.withValues(alpha: 0.13),
        AppScheme.of(brightness).fg,
      );

  /// `(background, textColour)` for [status] at the given [brightness].
  static (Color, Color) colourForStatus(
    String status, {
    Brightness brightness = Brightness.light,
  }) {
    final (base, text700, text300) = _ramp(status);
    return (
      _background(base, brightness),
      brightness == Brightness.dark ? text300 : text700,
    );
  }

  /// The leading-dot color (`<hue>500`) for [status].
  static Color dotColorForStatus(String status) => _ramp(status).$1;

  Widget _buildPill(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final effectiveStatus = colorStatus ?? status;
    final (dot, text700, text300) = _ramp(
      effectiveStatus,
      isPosUpload: _isPosUpload,
    );
    final textColour = brightness == Brightness.dark ? text300 : text700;
    final dotSize = compact ? 6.0 : 7.0;

    return Container(
      constraints: compact ? const BoxConstraints(minHeight: 14) : null,
      // ds.css .pill padding 5/11/5/9 (less left because of the dot); compact scales down.
      padding: compact
          ? const EdgeInsets.fromLTRB(7, 2, 9, 2)
          : const EdgeInsets.fromLTRB(9, 5, 11, 5),
      decoration: BoxDecoration(
        color: _background(dot, brightness),
        border: _isPosUpload
            ? Border.all(color: dot.withValues(alpha: 0.35))
            : null,
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
                fontSize: compact && !wrapLabel ? 9 : 11,
                height: 1.0,
              ),
              maxLines: _isPosUpload ? 1 : null,
              softWrap: wrapLabel ? true : null,
              overflow: wrapLabel ? TextOverflow.clip : TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Cross-fades the whole pill (background + dot + text together) so a
    // status transition (e.g. Pending -> Completed) reads as one change
    // instead of a hard replace next to the surrounding document content.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: KeyedSubtree(
        key: ValueKey(status),
        child: _buildPill(context),
      ),
    );
  }
}
