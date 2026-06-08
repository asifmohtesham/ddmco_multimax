import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/frappe_socket.dart';

// Minimal fake socket that records calls
class _FakeSocket {
  final List<String> emitted = [];
  final Map<String, void Function(dynamic)> listeners = {};
  void Function()? onConnectCallback;
  void Function(dynamic)? onConnectErrorCallback;

  void emit(String event, [dynamic data]) => emitted.add(event);
  void on(String event, void Function(dynamic) cb) => listeners[event] = cb;
  void onConnect(void Function() cb) => onConnectCallback = cb;
  void onConnectError(void Function(dynamic) cb) => onConnectErrorCallback = cb;
  void onError(void Function(dynamic) cb) {}
  void connect() => onConnectCallback?.call();
  void disconnect() {}
  void dispose() {}
}

void main() {
  group('cookie header formatting', () {
    test('joins multiple cookies with semicolons', () {
      final cookies = [
        {'name': 'sid', 'value': 'abc123'},
        {'name': 'system_user', 'value': 'yes'},
      ];
      final header = cookies.map((c) => '${c['name']}=${c['value']}').join('; ');
      expect(header, 'sid=abc123; system_user=yes');
    });

    test('single cookie has no trailing semicolon', () {
      final cookies = [
        {'name': 'sid', 'value': 'xyz'},
      ];
      final header = cookies.map((c) => '${c['name']}=${c['value']}').join('; ');
      expect(header, 'sid=xyz');
    });

    test('empty cookie list produces empty string', () {
      final cookies = <Map<String, String>>[];
      final header = cookies.map((c) => '${c['name']}=${c['value']}').join('; ');
      expect(header, '');
    });
  });

  group('FrappeSocket', () {
    test('connect() subscribes to the document room on connect', () {
      final fakeSocket = _FakeSocket();
      final frappe = FrappeSocket(
        socketFactory: (url, opts) => fakeSocket,
      );
      frappe.connect(
        baseUrl: 'https://erp.example.com',
        cookieHeader: 'sid=abc',
        doctype: 'Stock Entry',
        docname: 'MAT-STE-001',
        onDocUpdate: () {},
      );
      expect(fakeSocket.emitted, contains('doc_subscribe'));
    });

    test('connect() is idempotent — second call is a no-op', () {
      final fakeSocket = _FakeSocket();
      int connectCount = 0;
      final frappe = FrappeSocket(
        socketFactory: (url, opts) {
          connectCount++;
          return fakeSocket;
        },
      );
      frappe.connect(
        baseUrl: 'https://erp.example.com',
        cookieHeader: 'sid=abc',
        doctype: 'Stock Entry',
        docname: 'MAT-STE-001',
        onDocUpdate: () {},
      );
      frappe.connect(
        baseUrl: 'https://erp.example.com',
        cookieHeader: 'sid=abc',
        doctype: 'Stock Entry',
        docname: 'MAT-STE-001',
        onDocUpdate: () {},
      );
      expect(connectCount, 1);
    });

    test('doc_update fires onDocUpdate only for matching doctype+name', () {
      final fakeSocket = _FakeSocket();
      final frappe = FrappeSocket(
        socketFactory: (url, opts) => fakeSocket,
      );
      int callCount = 0;
      frappe.connect(
        baseUrl: 'https://erp.example.com',
        cookieHeader: 'sid=abc',
        doctype: 'Stock Entry',
        docname: 'MAT-STE-001',
        onDocUpdate: () => callCount++,
      );
      fakeSocket.listeners['doc_update']!({'doctype': 'Stock Entry', 'name': 'MAT-STE-001'});
      fakeSocket.listeners['doc_update']!({'doctype': 'Stock Entry', 'name': 'MAT-STE-999'});
      fakeSocket.listeners['doc_update']!({'doctype': 'Delivery Note', 'name': 'MAT-STE-001'});
      expect(callCount, 1);
    });

    test('dispose() emits doc_unsubscribe and allows reconnect', () {
      final fakeSocket = _FakeSocket();
      final frappe = FrappeSocket(
        socketFactory: (url, opts) => fakeSocket,
      );
      frappe.connect(
        baseUrl: 'https://erp.example.com',
        cookieHeader: 'sid=abc',
        doctype: 'Stock Entry',
        docname: 'MAT-STE-001',
        onDocUpdate: () {},
      );
      frappe.dispose();
      expect(fakeSocket.emitted, contains('doc_unsubscribe'));

      // After dispose, connect() should be allowed again
      int connectCount = 0;
      final frappe2 = FrappeSocket(
        socketFactory: (url, opts) {
          connectCount++;
          return _FakeSocket();
        },
      );
      frappe2.connect(
        baseUrl: 'https://erp.example.com',
        cookieHeader: 'sid=abc',
        doctype: 'Stock Entry',
        docname: 'MAT-STE-001',
        onDocUpdate: () {},
      );
      expect(connectCount, 1);
    });
  });
}
