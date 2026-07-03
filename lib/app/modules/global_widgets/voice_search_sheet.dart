import 'package:flutter/material.dart';

import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/services/stt_voice_search_engine.dart';
import 'package:multimax/app/data/services/voice_search_engine.dart';

/// Modal bottom sheet that captures one voice dictation and returns the final
/// transcript (or `null` if cancelled / unavailable).
class VoiceSearchSheet extends StatefulWidget {
  const VoiceSearchSheet({super.key, required this.engine});

  final VoiceSearchEngine engine;

  /// Opens the sheet and resolves to the recognized transcript, or `null`.
  static Future<String?> show(BuildContext context,
      {VoiceSearchEngine? engine}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (_) => VoiceSearchSheet(engine: engine ?? SttVoiceSearchEngine()),
    );
  }

  @override
  State<VoiceSearchSheet> createState() => _VoiceSearchSheetState();
}

class _VoiceSearchSheetState extends State<VoiceSearchSheet> {
  VoiceEngineState _state = VoiceEngineState.listening;
  String _text = '';
  bool _busy = false; // re-entrancy guard for stop().
  bool _closed = false; // guards against a terminal state firing twice.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    await widget.engine.start(
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() => _text = text);
        if (isFinal) _finish(text);
      },
      onState: (state) {
        if (!mounted) return;
        setState(() => _state = state);
        if (state == VoiceEngineState.done) {
          _finish(_text); // engine ended; commit whatever we have
        }
      },
    );
  }

  void _finish(String text) {
    if (_closed) return;
    _closed = true;
    final trimmed = text.trim();
    Navigator.of(context).pop(trimmed.isEmpty ? null : trimmed);
  }

  Future<void> _stop() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.engine.stop();
    // A final result / done state will pop; nothing else to do here.
  }

  Future<void> _cancel() async {
    await widget.engine.cancel();
    if (!_closed && mounted) {
      _closed = true;
      Navigator.of(context).pop(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: scheme.fg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, 20 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusIcon(scheme),
            const SizedBox(height: 16),
            Text(
              _headline(),
              style: TextStyle(color: scheme.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (_isListening)
              Text(
                _text.isEmpty ? '…' : _text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Text(
                _detail(),
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.text, fontSize: 15),
              ),
            const SizedBox(height: 20),
            _actionRow(scheme),
          ],
        ),
      ),
    );
  }

  bool get _isListening => _state == VoiceEngineState.listening;

  Widget _statusIcon(AppScheme scheme) {
    final bad = _state == VoiceEngineState.permissionDenied ||
        _state == VoiceEngineState.notAvailable ||
        _state == VoiceEngineState.error;
    final color = bad ? Theme.of(context).colorScheme.error : scheme.primary;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        shape: BoxShape.circle,
      ),
      child: Icon(bad ? Icons.mic_off : Icons.mic, color: color, size: 34),
    );
  }

  String _headline() {
    switch (_state) {
      case VoiceEngineState.listening:
        return 'Listening…';
      case VoiceEngineState.done:
        return 'Done';
      case VoiceEngineState.permissionDenied:
        return 'Microphone blocked';
      case VoiceEngineState.notAvailable:
        return 'Voice unavailable';
      case VoiceEngineState.error:
        return 'Try again';
    }
  }

  String _detail() {
    switch (_state) {
      case VoiceEngineState.permissionDenied:
        return 'Microphone permission is needed. Enable it in Settings and try again.';
      case VoiceEngineState.notAvailable:
        return "Voice input isn't available on this device.";
      case VoiceEngineState.error:
        return "Didn't catch that. Tap the mic to try again.";
      default:
        return '';
    }
  }

  Widget _actionRow(AppScheme scheme) {
    if (_isListening) {
      return FilledButton.icon(
        onPressed: _busy ? null : _stop,
        icon: _busy
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(scheme.onPrimary),
                ),
              )
            : const Icon(Icons.stop, size: 18),
        label: const Text('Done'),
      );
    }
    return TextButton(
      onPressed: _cancel,
      child: const Text('Close'),
    );
  }
}
