import 'dart:async';
import 'dart:collection'; // Required for Queue
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class DataWedgeService extends GetxService {
  // Define the EventChannel name. Ensure this matches your MainActivity.kt
  static const EventChannel _eventChannel = EventChannel('com.ddmco.multimax/scan');

  StreamSubscription? _scanSubscription;

  // Observable to listen to in controllers
  final scannedCode = ''.obs;

  // Queue to handle burst scans (MultiBarcode) sequentially
  final Queue<String> _scanQueue = Queue<String>();
  bool _isProcessing = false;

  @override
  void onInit() {
    super.onInit();
    _initDataWedgeListener();
  }

  void _initDataWedgeListener() {
    try {
      _scanSubscription = _eventChannel.receiveBroadcastStream().listen(
            (dynamic event) {
          // 1. Handle Single String (Existing Functionality)
          if (event is String) {
            _enqueueScan(event);
          }
          // 2. Handle List (New NextGen SimulScan Functionality)
          else if (event is List) {
            for (var item in event) {
              if (item is String) {
                _enqueueScan(item);
              }
            }
          }
          // 3. Handle Map (Existing Functionality)
          else if (event is Map) {
            final code = event['scanData'] as String?;
            if (code != null) {
              _enqueueScan(code);
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

  /// Processes the queue one item at a time to ensure listeners catch every code.
  Future<void> _processQueue() async {
    _isProcessing = true;

    while (_scanQueue.isNotEmpty) {
      final code = _scanQueue.removeFirst();

      // Update the observable
      scannedCode.value = code;

      // Wait for the duration required by your listeners (Debounce logic).
      // 800ms gives enough time for a 500ms debounce in the controller to fire.
      await Future.delayed(const Duration(milliseconds: 800));

      // Reset the code to trigger "cleared" state if needed, or prepare for next change
      scannedCode.value = '';

      // Small buffer before next scan to ensure state changes are distinct
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _isProcessing = false;
  }

  @override
  void onClose() {
    _scanSubscription?.cancel();
    super.onClose();
  }
}