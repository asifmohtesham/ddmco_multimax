import 'package:get/get.dart';

class ConnectToInstanceController extends GetxController {
  static String normaliseUrl(String raw) {
    String url = raw.trim();
    if (url.isEmpty) return '';
    if (!url.startsWith('http')) url = 'https://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  static bool looksLikeUrl(String value) {
    if (value.isEmpty) return false;
    return value.startsWith('http') || value.contains('.');
  }
}
