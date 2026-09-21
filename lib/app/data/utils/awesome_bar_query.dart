import 'package:get/get.dart';

/// Route-argument key an Awesome Bar "Find *x* in *DocType*" option uses to
/// hand the list screen its initial search text.
const String kAwesomeBarQueryArg = 'awesomeBarQuery';

/// The query a "Find *x* in …" option passed to this list, or `null`.
///
/// Reads [args] when given, else `Get.arguments`. Blank / non-String values
/// are treated as absent so a list never applies an empty search.
String? awesomeBarQueryArg([dynamic args]) {
  final a = args ?? Get.arguments;
  if (a is Map) {
    final q = a[kAwesomeBarQueryArg];
    if (q is String && q.trim().isNotEmpty) return q.trim();
  }
  return null;
}
