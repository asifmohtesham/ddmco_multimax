import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/wedge_burst_assembler.dart';

/// Bridges Bluetooth HID keyboard-wedge scanners (e.g. Netum C750) into the
/// app's single scan sink.
///
/// Registers a global [HardwareKeyboard] handler, assembles key bursts via
/// [WedgeBurstAssembler], and on a completed Enter-terminated burst calls
/// [DataWedgeService.injectScan] — giving HID scans full parity with the
/// native Zebra/DataWedge path across every existing `ever()`-worker flow.
///
/// Consume policy (decided synchronously per key, since the inter-key gap is
/// only known from the second key onward):
///   - mid-burst chars (gap < maxGapMs)  -> consumed (kept out of focused fields)
///   - first char of a burst (idle gap)  -> passed through
///   - an Enter that completes a burst   -> consumed (no stray submit / focus move)
class HidWedgeService extends GetxService {
  HidWedgeService({WedgeBurstAssembler? assembler, DataWedgeService? dataWedge})
      : _assembler = assembler ?? WedgeBurstAssembler(),
        _dataWedgeOverride = dataWedge;

  final WedgeBurstAssembler _assembler;
  final DataWedgeService? _dataWedgeOverride;

  DataWedgeService get _dataWedge =>
      _dataWedgeOverride ?? Get.find<DataWedgeService>();

  @override
  void onInit() {
    super.onInit();
    HardwareKeyboard.instance.addHandler(handleKeyEvent);
  }

  @override
  void onClose() {
    HardwareKeyboard.instance.removeHandler(handleKeyEvent);
    super.onClose();
  }

  /// Handler registered with [HardwareKeyboard]. Returns `true` to consume.
  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final ts = event.timeStamp.inMilliseconds;

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _assembler.terminate(ts);
      if (code != null) {
        _dataWedge.injectScan(code);
        return true;
      }
      return false;
    }

    final ch = event.character;
    if (ch != null && _isPrintable(ch)) {
      return _assembler.addChar(ch, ts);
    }

    // Modifier keys (Shift, CapsLock, etc.) carry no character and are part of
    // producing the NEXT character — e.g. Shift for an uppercase barcode digit.
    // Ignore them so they don't fragment an in-progress burst.
    if (_isModifier(event.logicalKey)) {
      return false;
    }

    _assembler.reset();
    return false;
  }

  bool _isPrintable(String ch) {
    if (ch.isEmpty) return false;
    final c = ch.codeUnitAt(0);
    return c >= 0x20 && c != 0x7f; // exclude control chars and DEL
  }

  static final Set<LogicalKeyboardKey> _modifierKeys = {
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
  };

  bool _isModifier(LogicalKeyboardKey key) => _modifierKeys.contains(key);
}
