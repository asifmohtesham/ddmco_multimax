import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

typedef _SocketFactory = dynamic Function(String url, dynamic opts);

class FrappeSocket {
  final _SocketFactory? _socketFactory;
  dynamic _socket;
  bool _connected = false;

  FrappeSocket({_SocketFactory? socketFactory}) : _socketFactory = socketFactory;

  void connect({
    required String baseUrl,
    required String cookieHeader,
    required String doctype,
    required String docname,
    required void Function() onDocUpdate,
    void Function()? onConnected,
  }) {
    if (_connected) return;
    _connected = true;

    final opts = IO.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .setExtraHeaders({'Cookie': cookieHeader})
        .disableAutoConnect()
        .build();

    // Capture as local so closures below never read the nullable field.
    final sock = _socketFactory != null
        ? _socketFactory!(baseUrl, opts)
        : IO.io(baseUrl, opts);
    _socket = sock;

    sock.on('connect', (_) {
      _debugLog('connected — subscribing to $doctype/$docname');
      sock.emit('doc_subscribe', [doctype, docname]);
      onConnected?.call();
    });

    sock.on('doc_update', (data) {
      if (data is Map &&
          data['doctype'] == doctype &&
          data['name'] == docname) {
        onDocUpdate();
      }
    });

    sock.on('connect_error', (e) => _debugLog('connect error: $e'));
    sock.on('error',         (e) => _debugLog('socket error: $e'));

    sock.connect();
  }

  void _debugLog(String msg) {
    if (kDebugMode) debugPrint('[FrappeSocket] $msg');
  }

  void dispose() {
    if (_socket != null) {
      _socket!.off('connect');
      _socket!.off('doc_update');
      _socket!.off('connect_error');
      _socket!.off('error');
      _socket!.emit('doc_unsubscribe', []);
      _socket!.disconnect();
      _socket = null;
    }
    _connected = false;
  }
}
