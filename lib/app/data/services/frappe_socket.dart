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
  }) {
    if (_connected) return;
    _connected = true;

    final opts = IO.OptionBuilder()
        .setTransports(['websocket'])
        .setExtraHeaders({'Cookie': cookieHeader})
        .disableAutoConnect()
        .build();

    _socket = _socketFactory != null
        ? _socketFactory!(baseUrl, opts)
        : IO.io(baseUrl, opts);

    _socket.onConnect(() {
      _socket.emit('doc_subscribe', [doctype, docname]);
    });

    _socket.on('doc_update', (data) {
      if (data is Map &&
          data['doctype'] == doctype &&
          data['name'] == docname) {
        onDocUpdate();
      }
    });

    _socket.onConnectError((e) {});
    _socket.onError((e) {});

    _socket.connect();
  }

  void dispose() {
    _socket?.emit('doc_unsubscribe', []);
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connected = false;
  }
}
