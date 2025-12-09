import 'dart:async';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class DataWedgeService extends GetxService {
  // Define the EventChannel name. Ensure this matches your MainActivity.kt
  static const EventChannel _eventChannel = EventChannel('com.ddmco.multimax/scan');

  StreamSubscription? _scanSubscription;

  // Observable to listen to in controllers
  final scannedCode = ''.obs;

  @override
  void onInit() {
    super.onInit();
    _initDataWedgeListener();
  }

  void _initDataWedgeListener() {
    try {
      _scanSubscription = _eventChannel.receiveBroadcastStream().listen(
            (dynamic event) {
          if (event is String) {
            scannedCode.value = event;
            // Debounce or reset logic can be handled here if needed
            // Resetting after a short delay allows re-scanning same code if logic depends on change
            Future.delayed(const Duration(milliseconds: 500), () => scannedCode.value = '');
          } else if (event is Map) {
            // Handle map if native sends more details like symbology
            final code = event['scanData'] as String?;
            if (code != null) {
              scannedCode.value = code;
              Future.delayed(const Duration(milliseconds: 500), () => scannedCode.value = '');
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

  @override
  void onClose() {
    _scanSubscription?.cancel();
    super.onClose();
  }
}