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

    _socket = _socketFactory != null
        ? _socketFactory!(baseUrl, opts)
        : IO.io(baseUrl, opts);

    _socket.onConnect(() {
      _socket.emit('doc_subscribe', [doctype, docname]);
      onConnected?.call();
    });

    _socket.on('doc_update', (data) {
      if (data is Map &&
          data['doctype'] == doctype &&
          data['name'] == docname) {
        onDocUpdate();
      }
    });

    _socket.onConnectError((e) => _debugLog('connect error: $e'));
    _socket.onError((e) => _debugLog('socket error: $e'));

    _socket.connect();
  }

  void _debugLog(String msg) {
    if (kDebugMode) debugPrint('[FrappeSocket] $msg');
  }

  void dispose() {
    _socket?.emit('doc_unsubscribe', []);
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connected = false;
  }
}
