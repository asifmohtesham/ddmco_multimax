class FrappeLogicEvaluator {
  static bool evaluate(String? expression, Map<String, dynamic> doc, {Map<String, dynamic>? parentDoc}) {
    if (expression == null || expression.trim().isEmpty) return true;

    String expr = expression.trim();

    // 1. Simple Field Presence Check (e.g., "is_sub_contracted")
    if (!expr.startsWith("eval:")) {
      return _isTruthy(doc[expr]);
    }

    // 2. Parse "eval:" expressions
    String js = expr.substring(5).trim(); // Remove "eval:"

    try {
      // Handle Equality
      if (js.contains("==")) {
        List<String> parts = js.split("==");
        dynamic leftVal = _extractValue(parts[0].trim(), doc, parentDoc);
        dynamic rightVal = _extractValue(parts[1].trim(), doc, parentDoc);
        return leftVal.toString() == rightVal.toString();
      }

      // Handle Inequality: "eval:doc.field != 'value'"
      if (js.contains("!=")) {
        List<String> parts = js.split("!=");
        dynamic leftVal = _extractValue(parts[0].trim(), doc, parentDoc);
        dynamic rightVal = _extractValue(parts[1].trim(), doc, parentDoc);
        return leftVal.toString() != rightVal.toString();
      }

      // Handle Negation
      if (js.startsWith("!")) {
        String term = js.substring(1).trim();
        dynamic val = _extractValue(term, doc, parentDoc);
        return !_isTruthy(val);
      }

      // Handle Truthy Check
      dynamic val = _extractValue(js, doc, parentDoc);
      return _isTruthy(val);

    } catch (e) {
      // Fail open (show field) on error
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

  static dynamic _extractValue(String term, Map<String, dynamic> doc, Map<String, dynamic>? parentDoc) {
    if (term.startsWith("doc.")) {
      return doc[term.substring(4)];
    }
    if (term.startsWith("parent.")) {
      return parentDoc?[term.substring(7)];
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