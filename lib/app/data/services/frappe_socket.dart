import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

typedef _SocketFactory = dynamic Function(String url, dynamic opts);

class FrappeSocket {
  final _SocketFactory? _socketFactory;
  dynamic _socket;
  bool _connected = false;
  DateTime? _lastDocUpdateFired;

  FrappeSocket({_SocketFactory? socketFactory}) : _socketFactory = socketFactory;

  void connect({
    required String baseUrl,
    required String cookieHeader,
    required String doctype,
    required String docname,
    required void Function() onDocUpdate,
    void Function()? onConnected,
    void Function()? onDisconnected,
  }) {
    if (_connected) return;
    _connected = true;

    // Frappe v15 uses /{sitename} as the socket.io namespace so each site on a
    // shared server has its own event stream.  The sitename matches the hostname
    // in standard single-site deployments.  Connecting to root "/" lets the
    // socket.io handshake succeed but the auth middleware rejects the namespace,
    // so every emit is silently dropped.
    final siteName = Uri.parse(baseUrl).host;
    final socketUrl = '$baseUrl/$siteName';

    // Frappe's auth middleware also checks that Origin matches Host.  Browser
    // clients set Origin automatically; we must do it explicitly.
    final opts = IO.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .setExtraHeaders({
          'Cookie': cookieHeader,
          'Origin': baseUrl,
        })
        .disableAutoConnect()
        .build();

    // Capture as local so closures never read the nullable field.
    final sock = _socketFactory != null
        ? _socketFactory!(socketUrl, opts)
        : IO.io(socketUrl, opts);
    _socket = sock;

    _debugLog('init: cookie_present=${cookieHeader.isNotEmpty} url=$socketUrl');

    sock.on('connect', (_) {
      _debugLog('connected — subscribing to $doctype/$docname');
      // Primary: doc-level room (Frappe v14+).
      sock.emit('doc_subscribe', [doctype, docname]);
      // Fallback: doctype list room — less strict auth, same data.
      sock.emit('doctype_subscribe', [doctype]);
      onConnected?.call();
    });

    sock.on('disconnect', (reason) {
      _debugLog('disconnected: $reason');
      onDisconnected?.call();
    });

    // Primary event path (doc room).
    sock.on('doc_update', (data) {
      _debugLog('doc_update raw: $data (${data.runtimeType})');
      if (data is Map &&
          data['doctype'] == doctype &&
          (data['name'] == docname || data['docname'] == docname)) {
        _fireDocUpdate(onDocUpdate);
      }
    });

    // Fallback event path (doctype list room).
    sock.on('list_update', (data) {
      _debugLog('list_update raw: $data (${data.runtimeType})');
      if (data is Map &&
          data['doctype'] == doctype &&
          (data['name'] == docname || data['docname'] == docname)) {
        _fireDocUpdate(onDocUpdate);
      }
    });

    sock.on('connect_error', (e) => _debugLog('connect error: $e'));
    sock.on('error',         (e) => _debugLog('socket error: $e'));

    sock.connect();
  }

  // Deduplicate: if both doc_update and list_update fire for the same save,
  // only the first one within a 2-second window calls back.
  void _fireDocUpdate(void Function() onDocUpdate) {
    final now = DateTime.now();
    if (_lastDocUpdateFired != null &&
        now.difference(_lastDocUpdateFired!).inSeconds < 2) {
      return;
    }
    _lastDocUpdateFired = now;
    onDocUpdate();
  }

  void _debugLog(String msg) {
    if (kDebugMode) debugPrint('[FrappeSocket] $msg');
  }

  void dispose() {
    if (_socket != null) {
      _socket!.off('connect');
      _socket!.off('disconnect');
      _socket!.off('doc_update');
      _socket!.off('list_update');
      _socket!.off('connect_error');
      _socket!.off('error');
      _socket!.emit('doc_unsubscribe', []);
      _socket!.disconnect();
      _socket = null;
    }
    _connected = false;
    _lastDocUpdateFired = null;
  }
}
