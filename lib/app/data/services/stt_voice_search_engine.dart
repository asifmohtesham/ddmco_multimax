import 'dart:ui' as ui;

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:multimax/app/data/services/voice_search_engine.dart';

/// [VoiceSearchEngine] backed by the on-device `speech_to_text` plugin.
class SttVoiceSearchEngine implements VoiceSearchEngine {
  SttVoiceSearchEngine({SpeechToText? speech, String? deviceLocaleId})
      : _speech = speech ?? SpeechToText(),
        _deviceLocaleId = deviceLocaleId ?? _platformLocaleId();

  final SpeechToText _speech;
  final String _deviceLocaleId;

  bool _permissionDenied = false;

  static String _platformLocaleId() {
    final l = ui.PlatformDispatcher.instance.locale;
    return l.countryCode == null || l.countryCode!.isEmpty
        ? l.languageCode
        : '${l.languageCode}_${l.countryCode}';
  }

  @override
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
    required void Function(VoiceEngineState state) onState,
  }) async {
    _permissionDenied = false;

    try {
      final available = await _speech.initialize(
        onError: (SpeechRecognitionError e) {
          // 'error_permission' / 'error_speech_timeout' etc. Permission
          // errors get their own state so the sheet can show the right
          // message.
          if (e.errorMsg.toLowerCase().contains('permission')) {
            _permissionDenied = true;
            onState(VoiceEngineState.permissionDenied);
          } else {
            onState(VoiceEngineState.error);
          }
        },
        onStatus: (String status) {
          // Plugin emits 'listening', 'notListening', 'done'.
          if (status == 'done' || status == 'notListening') {
            onState(VoiceEngineState.done);
          }
        },
      );

      if (!available) {
        onState(_permissionDenied
            ? VoiceEngineState.permissionDenied
            : VoiceEngineState.notAvailable);
        return;
      }

      final locales = await _speech.locales();
      final localeId = resolveLocaleId(
          locales.map((l) => l.localeId).toList(), _deviceLocaleId);

      onState(VoiceEngineState.listening);
      await _speech.listen(
        onResult: (SpeechRecognitionResult r) =>
            onResult(r.recognizedWords, r.finalResult),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          localeId: localeId,
          cancelOnError: true,
        ),
      );
    } catch (_) {
      // Platform-channel failures (e.g. unsupported platform, native
      // exceptions) must never propagate to the caller.
      onState(VoiceEngineState.error);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {
      // Swallow: caller relies on onState for lifecycle, not exceptions.
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } catch (_) {
      // Swallow: caller relies on onState for lifecycle, not exceptions.
    }
  }
}
