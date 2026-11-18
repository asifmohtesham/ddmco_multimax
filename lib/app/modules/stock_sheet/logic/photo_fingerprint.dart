import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// Maps each photo path to a fingerprint of its content.
typedef PhotoFingerprinter =
    Future<Map<String, String>> Function(List<String> paths);

/// The SHA-256 (hex) of each file's bytes, read off the UI isolate. A file
/// that cannot be read maps to `unreadable:<path>`, so it is unique and kept.
Future<Map<String, String>> fingerprintPhotos(List<String> paths) {
  final copy = List<String>.of(paths);
  return Isolate.run(() {
    final out = <String, String>{};
    for (final path in copy) {
      try {
        out[path] = sha256.convert(File(path).readAsBytesSync()).toString();
      } catch (_) {
        out[path] = 'unreadable:$path';
      }
    }
    return out;
  });
}
