/// Safe arithmetic evaluator for the Awesome Bar calculator row.
///
/// Frappe's Awesome Bar `eval()`s anything that starts with a digit, `(` or
/// `=`. This is the sandboxed equivalent: a recursive-descent parser over
/// `+ - * / % ^`, parentheses, decimals and unary minus. Anything else — a
/// stray identifier, a dangling operator, division by zero — yields `null`
/// so no calculator row is shown.
///
/// Pure.
library;

import 'dart:math' as math;

/// Whether Frappe would try to evaluate [txt] as a calculation: the first
/// character is a digit, `(` or `=`.
bool looksLikeCalculation(String txt) {
  if (txt.isEmpty) return false;
  final c = txt[0];
  return c == '(' || c == '=' || (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39);
}

/// Evaluates [expression] and returns the result, or `null` when it is not a
/// well-formed finite calculation. A leading `=` is stripped, as in Frappe.
double? evaluateExpression(String expression) {
  var src = expression.trim();
  if (src.startsWith('=')) src = src.substring(1);
  if (src.trim().isEmpty) return null;
  try {
    final p = _Parser(src);
    final v = p.parseExpression();
    p.skipWhitespace();
    if (!p.atEnd) return null;
    if (v.isNaN || v.isInfinite) return null;
    return v;
  } on FormatException {
    return null;
  }
}

/// Renders [value] the way a person expects to read it: integers without a
/// decimal point, otherwise up to 10 significant decimals with trailing
/// zeros removed.
String formatCalculatorResult(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  var s = value.toStringAsFixed(10);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  s = s.replaceFirst(RegExp(r'\.$'), '');
  return s;
}

class _Parser {
  final String src;
  int pos = 0;

  _Parser(this.src);

  bool get atEnd => pos >= src.length;

  void skipWhitespace() {
    while (!atEnd && (src[pos] == ' ' || src[pos] == '\t')) {
      pos++;
    }
  }

  String? peek() {
    skipWhitespace();
    return atEnd ? null : src[pos];
  }

  // expression := term (('+' | '-') term)*
  double parseExpression() {
    var v = parseTerm();
    while (true) {
      final c = peek();
      if (c == '+') {
        pos++;
        v += parseTerm();
      } else if (c == '-') {
        pos++;
        v -= parseTerm();
      } else {
        return v;
      }
    }
  }

  // term := factor (('*' | '/' | '%') factor)*
  double parseTerm() {
    var v = parseFactor();
    while (true) {
      final c = peek();
      if (c == '*') {
        pos++;
        v *= parseFactor();
      } else if (c == '/') {
        pos++;
        final d = parseFactor();
        if (d == 0) throw const FormatException('division by zero');
        v /= d;
      } else if (c == '%') {
        pos++;
        final d = parseFactor();
        if (d == 0) throw const FormatException('modulo by zero');
        v = v % d;
      } else {
        return v;
      }
    }
  }

  // factor := unary ('^' factor)?   (right-associative)
  double parseFactor() {
    final base = parseUnary();
    if (peek() == '^') {
      pos++;
      final exp = parseFactor();
      return _pow(base, exp);
    }
    return base;
  }

  // unary := '-' unary | '+' unary | primary
  double parseUnary() {
    final c = peek();
    if (c == '-') {
      pos++;
      return -parseUnary();
    }
    if (c == '+') {
      pos++;
      return parseUnary();
    }
    return parsePrimary();
  }

  // primary := number | '(' expression ')'
  double parsePrimary() {
    final c = peek();
    if (c == null) throw const FormatException('unexpected end');
    if (c == '(') {
      pos++;
      final v = parseExpression();
      if (peek() != ')') throw const FormatException('missing )');
      pos++;
      return v;
    }
    return parseNumber();
  }

  double parseNumber() {
    skipWhitespace();
    final start = pos;
    var seenDot = false;
    var seenDigit = false;
    while (!atEnd) {
      final ch = src[pos];
      final code = ch.codeUnitAt(0);
      if (code >= 0x30 && code <= 0x39) {
        seenDigit = true;
        pos++;
      } else if (ch == '.' && !seenDot) {
        seenDot = true;
        pos++;
      } else {
        break;
      }
    }
    if (!seenDigit) throw const FormatException('number expected');
    final v = double.tryParse(src.substring(start, pos));
    if (v == null) throw const FormatException('bad number');
    return v;
  }

  static double _pow(double b, double e) {
    // Integer exponents stay exact for the common `2^10` case.
    if (e == e.roundToDouble() && e.abs() <= 1024) {
      var n = e.toInt();
      var result = 1.0;
      var base = b;
      final negative = n < 0;
      n = n.abs();
      while (n > 0) {
        if (n & 1 == 1) result *= base;
        base *= base;
        n >>= 1;
      }
      return negative ? 1 / result : result;
    }
    return math.pow(b, e).toDouble();
  }
}
