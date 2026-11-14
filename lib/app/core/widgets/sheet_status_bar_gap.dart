import 'package:flutter/material.dart';

/// Height of the status bar, for a widget inside a `Get.bottomSheet` route.
///
/// Read it from the view, never from `MediaQuery`: GetX pushes the sheet route
/// with `removeTop: true`, which zeroes both `padding.top` and `viewPadding.top`
/// in the sheet's MediaQuery, so those read 0 there.
///
/// Use [SheetStatusBarGap] to wrap a sheet, or add this as a `margin` on a
/// sheet that already has an outermost Container.
double sheetStatusBarInset(BuildContext context) =>
    MediaQueryData.fromView(View.of(context)).padding.top;

/// Keeps a bottom sheet's content clear of the status bar.
///
/// `Get.bottomSheet(..., isScrollControlled: true)` lets content take the full
/// available height, so a tall sheet (long list, or a form with the keyboard
/// open) runs under the status bar and its title becomes unreadable. GetX
/// pushes the route with `removeTop: true`, which zeroes both `padding.top`
/// and `viewPadding.top` inside the sheet — a `SafeArea(top: true)` there
/// collapses to nothing — so the inset is read from the view instead.
///
/// Costs nothing on a short sheet: the route bottom-aligns content that
/// shrink-wraps, so the reserved strip is simply never used.
class SheetStatusBarGap extends StatelessWidget {
  const SheetStatusBarGap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: sheetStatusBarInset(context)),
      child: child,
    );
  }
}
