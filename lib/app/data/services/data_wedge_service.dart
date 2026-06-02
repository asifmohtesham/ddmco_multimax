import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class DataWedgeService extends GetxService {
  static const EventChannel _eventChannel = EventChannel('com.ddmco.multimax/scan');
  static const MethodChannel _methodChannel = MethodChannel('com.ddmco.multimax/command');

  StreamSubscription? _scanSubscription;

  final scannedCode = ''.obs;

  final Queue<String> _scanQueue = Queue<String>();
  bool _isProcessing = false;

  @override
  void onInit() {
    super.onInit();
    _initDataWedgeListener();
  }

  Future<String?> getVersion() async {
    try {
      final String? version = await _methodChannel
          .invokeMethod<String>('getDWVersion')
          .timeout(const Duration(milliseconds: 1500));
      return version;
    } catch (e) {
      return 'Unavailable';
    }
  }

  void _initDataWedgeListener() {
    try {
      _scanSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is String) {
            _enqueueScan(event);
          } else if (event is List) {
            List<String> detectedCodes = [];

            for (var item in event) {
              if (item is String) {
                detectedCodes.add(item);
              } else if (item is Map) {
                final val = item['string_data'] ?? item['scanData'];
                if (val is String) detectedCodes.add(val);
              }
            }

            // EAN-8 first so Item is resolved before Batch
            detectedCodes.sort((a, b) {
              final aIsEan8 = _isLikelyEan8(a);
              final bIsEan8 = _isLikelyEan8(b);
              if (aIsEan8 && !bIsEan8) return -1;
              if (!aIsEan8 && bIsEan8) return 1;
              return 0;
            });

            for (var code in detectedCodes) {
              _enqueueScan(code);
            }
          } else if (event is Map) {
            if (event.containsKey('data_string_list')) {
              final list = event['data_string_list'];
              if (list is List) {
                for (var s in list) if (s is String) _enqueueScan(s);
              }
            } else if (event.containsKey('scanData')) {
              _enqueueScan(event['scanData'] as String);
            }
          }
        },
        onError: (dynamic error) {
          debugPrint('[DataWedge] EventChannel error: $error');
        },
      );

      // Confirms Flutter-side listener is live.
      // In logcat this should appear BEFORE any ScanCheck broadcast lines.
      debugPrint('[DataWedge] EventChannel stream listener attached');
    } catch (e) {
      debugPrint('[DataWedge] Failed to start listener: $e');
    }
  }

  void _enqueueScan(String code) {
    if (code.isEmpty) return;
    _scanQueue.add(code);
    if (!_isProcessing) {
      _processQueue();
    }
  }

  Future<void> _processQueue() async {
    _isProcessing = true;

    while (_scanQueue.isNotEmpty) {
      final code = _scanQueue.removeFirst();

      debugPrint('[DataWedge] Dequeued scan: $code');

      scannedCode.value = code;

      // 800 ms: enough for the ever() worker's debounce to fire
      await Future.delayed(const Duration(milliseconds: 800));

      scannedCode.value = '';

      await Future.delayed(const Duration(milliseconds: 100));
    }

    _isProcessing = false;
  }

  bool _isLikelyEan8(String code) {
    return code.length == 8 && RegExp(r'^\d+$').hasMatch(code);
  }

  @override
  void onClose() {
    _scanSubscription?.cancel();
    super.onClose();
  }
}
