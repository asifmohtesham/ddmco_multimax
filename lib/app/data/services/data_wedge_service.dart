import 'dart:async';
import 'dart:collection'; // Required for Queue
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class DataWedgeService extends GetxService {
  // Define the EventChannel name. Ensure this matches your MainActivity.kt
  static const EventChannel _eventChannel = EventChannel('com.ddmco.multimax/scan');
  // New MethodChannel matching Kotlin
  static const MethodChannel _methodChannel = MethodChannel('com.ddmco.multimax/command');

  StreamSubscription? _scanSubscription;

  // Observable to listen to in controllers
  final scannedCode = ''.obs;

  // Queue to handle burst scans (SimulScan/Workflow) sequentially
  final Queue<String> _scanQueue = Queue<String>();
  bool _isProcessing = false;

  @override
  void onInit() {
    super.onInit();
    _initDataWedgeListener();
  }

  /// Fetches the DataWedge version via MethodChannel.
  /// Returns 'Unavailable' if timed out (e.g., on generic devices).
  Future<String?> getVersion() async {
    try {
      final String? version = await _methodChannel
          .invokeMethod<String>('getDWVersion')
          .timeout(const Duration(milliseconds: 1500)); // 1.5s Timeout
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
            // 1. Standard Single Scan
            _enqueueScan(event);
          } else if (event is List) {
            // 2. MultiBarcode / SimulScan List
            // Extract all valid strings from the list (handles Strings and Maps)
            List<String> detectedCodes = [];

            for (var item in event) {
              if (item is String) {
                detectedCodes.add(item);
              } else if (item is Map) {
                // Handle Map from Workflow if applicable
                final val = item['string_data'] ?? item['scanData'];
                if (val is String) detectedCodes.add(val);
              }
            }

            // --- PRIORITY SORTING LOGIC ---
            // Ensure EAN-8 (Item) is processed BEFORE Batch No.
            // This prevents the "Batch" from being set on a null Item.
            detectedCodes.sort((a, b) {
              final aIsEan8 = _isLikelyEan8(a);
              final bIsEan8 = _isLikelyEan8(b);

              if (aIsEan8 && !bIsEan8) return -1; // 'a' (EAN8) comes first
              if (!aIsEan8 && bIsEan8) return 1;  // 'b' (EAN8) comes first
              return 0; // Keep original order if both or neither are EAN8
            });

            // Enqueue sorted codes
            for (var code in detectedCodes) {
              _enqueueScan(code);
            }

          } else if (event is Map) {
            // 3. Fallback for single complex object
            if (event.containsKey('data_string_list')) {
              final list = event['data_string_list'];
              if (list is List) {
                // Recursively handle list if wrapped in map
                // (Simplified here for brevity, assuming direct list usually)
                for (var s in list) if (s is String) _enqueueScan(s);
              }
            } else if (event.containsKey('scanData')) {
              _enqueueScan(event['scanData'] as String);
            }
          }
        },
        onError: (dynamic error) {
          print('DataWedge Error: $error');
        },
      );
    } catch (e) {
      print('Failed to start DataWedge listener: $e');
    }
  }

  /// Adds a scan to the queue and starts processing if idle.
  void _enqueueScan(String code) {
    if (code.isEmpty) return;

    _scanQueue.add(code);

    if (!_isProcessing) {
      _processQueue();
    }
  }

  /// Processes the queue one item at a time with delays to satisfy UI debounce.
  Future<void> _processQueue() async {
    _isProcessing = true;

    while (_scanQueue.isNotEmpty) {
      final code = _scanQueue.removeFirst();

      // Update the observable
      scannedCode.value = code;

      // WAIT: Give Controllers enough time to trigger their debounce (usually 500ms)
      // 800ms ensures the first code (EAN8) is fully "accepted" before the next one arrives.
      await Future.delayed(const Duration(milliseconds: 800));

      // RESET: clear logic to allow re-scanning identical codes if needed
      scannedCode.value = '';

      // BUFFER: Small gap before next code
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _isProcessing = false;
  }

  /// Simple helper to identify EAN-8 for sorting purposes.
  /// Matches ScanService logic: 8 chars long and numeric.
  bool _isLikelyEan8(String code) {
    return code.length == 8 && RegExp(r'^\d+$').hasMatch(code);
  }

  @override
  void onClose() {
    _scanSubscription?.cancel();
    super.onClose();
  }
}