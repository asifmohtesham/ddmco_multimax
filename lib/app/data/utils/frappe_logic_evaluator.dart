class FrappeLogicEvaluator {
  static bool evaluate(String? expression, Map<String, dynamic> doc) {
    if (expression == null || expression.trim().isEmpty) return true;

    String expr = expression.trim();

    // 1. Simple Field Presence Check (e.g., "is_sub_contracted")
    if (!expr.startsWith("eval:")) {
      return _isTruthy(doc[expr]);
    }

    // 2. Parse "eval:" expressions
    String js = expr.substring(5).trim(); // Remove "eval:"

    try {
      // Handle Negation: "eval:!doc.my_field"
      if (js.startsWith("!doc.")) {
        String field = js.substring(5).trim();
        return !_isTruthy(doc[field]);
      }

      // Handle Equality: "eval:doc.field == 'value'"
      if (js.contains("==")) {
        List<String> parts = js.split("==");
        dynamic leftVal = _extractValue(parts[0].trim(), doc);
        dynamic rightVal = _parsePrimitive(parts[1].trim());
        return leftVal.toString() == rightVal.toString();
      }

      // Handle Inequality: "eval:doc.field != 'value'"
      if (js.contains("!=")) {
        List<String> parts = js.split("!=");
        dynamic leftVal = _extractValue(parts[0].trim(), doc);
        dynamic rightVal = _parsePrimitive(parts[1].trim());
        return leftVal.toString() != rightVal.toString();
      }

      // Handle basic Boolean check: "eval:doc.my_field"
      if (js.startsWith("doc.") && !js.contains(" ") && !js.contains("=")) {
        return _isTruthy(doc[js.substring(4).trim()]);
      }

      // Fallback for complex JS we can't parse easily: return true (show field)
      return true;
    } catch (e) {
      print("Error evaluating depends_on: $expr -> $e");
      return true;
    }
  }

  static bool _isTruthy(dynamic val) {
    if (val == null) return false;
    if (val is int) return val != 0;
    if (val is double) return val != 0.0;
    if (val is String) return val.isNotEmpty && val != "0";
    if (val is bool) return val;
    if (val is List) return val.isNotEmpty;
    return true;
  }

  static dynamic _extractValue(String term, Map<String, dynamic> doc) {
    if (term.startsWith("doc.")) {
      return doc[term.substring(4)];
    }
    return _parsePrimitive(term);
  }

  static dynamic _parsePrimitive(String term) {
    if ((term.startsWith("'") && term.endsWith("'")) ||
        (term.startsWith('"') && term.endsWith('"'))) {
      return term.substring(1, term.length - 1);
    }
    if (term == "true") return true;
    if (term == "false") return false;
    return num.tryParse(term) ?? term;
  }
}