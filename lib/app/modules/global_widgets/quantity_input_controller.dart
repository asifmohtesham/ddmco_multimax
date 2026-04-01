import 'dart:async';
import 'package:get/get.dart';

/// Scoped controller that owns the press-and-hold repeat [Timer].
///
/// One instance is created per [_QtyActionButton] using a unique tag so
/// multiple buttons on the same sheet never share state.  GetX deletes it
/// automatically when [autoRemove] is true on [GetBuilder].
///
/// Note: [HapticFeedback] is intentionally NOT called here.  The widget
/// layer fires [HapticFeedback.lightImpact] once on [onTapDown] (initial
/// press only).  Keeping haptics in the widget prevents double-vibration
/// on repeat ticks.
class QuantityInputController extends GetxController {
  Timer? _repeatTimer;

  /// Start firing [action] immediately, then every 150 ms while held.
  void startRepeat(void Function() action) {
    action();
    _repeatTimer?.cancel();
    _repeatTimer =
        Timer.periodic(const Duration(milliseconds: 150), (_) => action());
  }

  /// Stop the repeat timer (finger lifted or gesture cancelled).
  void stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void onClose() {
    _repeatTimer?.cancel();
    super.onClose();
  }
}
