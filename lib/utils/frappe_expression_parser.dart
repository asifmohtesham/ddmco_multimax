import 'package:flutter/foundation.dart';

class FrappeExpressionParser {
  /// Evaluates specific Frappe "depends_on" syntax.
  /// Supported patterns:
  /// 1. "eval:doc.status == 'Open'"
  /// 2. "doc.my_field" (Truthy check)
  /// 3. "my_field" (Implicit doc.field)
  static bool evaluate(String? expression, Map<String, dynamic> doc) {
    if (expression == null || expression.isEmpty) return true;

    try {
      String exp = expression.trim();

      // Remove "eval:" prefix if present
      if (exp.startsWith('eval:')) {
        exp = exp.substring(5).trim();
      }

      // 1. EQUALITY Check (doc.field == 'Value')
      if (exp.contains('==')) {
        final parts = exp.split('==');
        final left = _parseValue(parts[0].trim(), doc);
        final right = _parseValue(parts[1].trim(), doc);
        return left.toString() == right.toString();
      }

      // 2. NOT EQUAL Check (doc.field != 'Value')
      if (exp.contains('!=')) {
        final parts = exp.split('!=');
        final left = _parseValue(parts[0].trim(), doc);
        final right = _parseValue(parts[1].trim(), doc);
        return left.toString() != right.toString();
      }

      // 3. TRUTHY Check (doc.is_group)
      final val = _parseValue(exp, doc);
      if (val is bool) return val;
      if (val is int) return val != 0;
      if (val is String) return val.isNotEmpty && val != "0";
      return val != null;
    } catch (e) {
      debugPrint("Expression Eval Error: $expression -> $e");
      return true; // Default to visible on error to avoid blocking UI
    }
  }

  static dynamic _parseValue(String token, Map<String, dynamic> doc) {
    // Handle string literals
    if ((token.startsWith("'") && token.endsWith("'")) ||
        (token.startsWith('"') && token.endsWith('"'))) {
      return token.substring(1, token.length - 1);
    }

    // Handle Numbers
    if (RegExp(r'^-?[\d.]+$').hasMatch(token)) {
      return num.tryParse(token);
    }

    // Handle Booleans
    if (token == 'true' || token == '1') return true;
    if (token == 'false' || token == '0') return false;

    // Handle Doc Fields (doc.field or just field)
    String field = token;
    if (token.startsWith('doc.')) {
      field = token.substring(4);
    }

    return doc[field];
  }
}
