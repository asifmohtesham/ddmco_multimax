import 'package:flutter/material.dart';

/// A widget that renders [text] with every occurrence of [query] highlighted.
///
/// Matching is case-insensitive.  If [query] is empty or null the widget
/// renders a plain [Text] equivalent using the supplied [style].
///
/// ### Usage
/// ```dart
/// SearchHighlight(
///   text:  'BOM-00123-PROD',
///   query: 'BOM-001',
///   style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
/// )
/// ```
///
/// ### Highlight appearance
/// The matched substring is drawn with a warm-amber background
/// (`Colors.amber.shade200` at 70 % opacity) and the [highlightTextStyle]
/// foreground so it remains legible on both light and dark surfaces.
/// Override [highlightColor] or [highlightTextStyle] to match your theme.
class SearchHighlight extends StatelessWidget {
  /// The full string to display.
  final String text;

  /// The substring to highlight.  Case-insensitive.  Empty → no highlight.
  final String query;

  /// Base text style applied to non-highlighted segments.
  /// Defaults to the ambient [DefaultTextStyle] when null.
  final TextStyle? style;

  /// Background colour painted behind each matched segment.
  /// Defaults to [Colors.amber.shade200] at 70 % opacity.
  final Color? highlightColor;

  /// Text style applied to matched segments.
  /// When null, the matched text inherits [style] plus a bold weight.
  final TextStyle? highlightTextStyle;

  /// Maximum lines before clipping.  Null = unlimited.
  final int? maxLines;

  /// Overflow behaviour.  Defaults to [TextOverflow.clip] (no ellipsis).
  final TextOverflow overflow;

  const SearchHighlight({
    super.key,
    required this.text,
    required this.query,
    this.style,
    this.highlightColor,
    this.highlightTextStyle,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveQuery = query.trim();

    // Fast-path: nothing to highlight.
    if (effectiveQuery.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: true,
      );
    }

    final spans = _buildSpans(context, effectiveQuery);

    return RichText(
      text: TextSpan(
        style: style ?? DefaultTextStyle.of(context).style,
        children: spans,
      ),
      maxLines: maxLines,
      overflow: overflow,
      softWrap: true,
    );
  }

  List<TextSpan> _buildSpans(BuildContext context, String q) {
    final List<TextSpan> spans = [];

    // Escape regex special characters inside the query string.
    final escaped = RegExp.escape(q);
    final pattern = RegExp(escaped, caseSensitive: false);

    final matches = pattern.allMatches(text);
    if (matches.isEmpty) {
      spans.add(TextSpan(text: text));
      return spans;
    }

    final bgColor = highlightColor ??
        Colors.amber.shade200.withValues(alpha: 0.70);

    final hlStyle = highlightTextStyle ??
        (style ?? DefaultTextStyle.of(context).style).copyWith(
          fontWeight: FontWeight.bold,
          background: Paint()..color = bgColor,
        );

    int cursor = 0;
    for (final match in matches) {
      // Text before the match.
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      // The matched segment.
      spans.add(TextSpan(
        text: text.substring(match.start, match.end),
        style: hlStyle,
      ));
      cursor = match.end;
    }

    // Remaining text after the last match.
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return spans;
  }
}

/// Index-based variant of [SearchHighlight] for fuzzy matches: emphasises
/// the characters of [text] at [indices] (the positions a fuzzy matcher
/// hit), the way Frappe wraps each matched character in `<mark>`.
///
/// [prefix] / [suffix] are rendered un-highlighted around [text], so a label
/// such as "New **D**elivery **N**ote" is one [RichText].
///
/// The emphasis is bold + the theme's primary colour over a 13 % primary
/// tint — the StatusPill tint convention — so it reads in both theme modes.
class MatchIndexHighlight extends StatelessWidget {
  final String text;
  final List<int> indices;
  final String prefix;
  final String suffix;
  final TextStyle? style;
  final TextStyle? highlightTextStyle;
  final int? maxLines;
  final TextOverflow overflow;

  const MatchIndexHighlight({
    super.key,
    required this.text,
    required this.indices,
    this.prefix = '',
    this.suffix = '',
    this.style,
    this.highlightTextStyle,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    if (indices.isEmpty) {
      return Text(
        '$prefix$text$suffix',
        style: base,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: true,
      );
    }
    final primary = Theme.of(context).colorScheme.primary;
    final hl = highlightTextStyle ??
        base.copyWith(
          fontWeight: FontWeight.w700,
          color: primary,
          background: Paint()..color = primary.withValues(alpha: 0.13),
        );
    final marked = List<bool>.filled(text.length, false);
    for (final i in indices) {
      if (i >= 0 && i < text.length) marked[i] = true;
    }
    final spans = <TextSpan>[];
    if (prefix.isNotEmpty) spans.add(TextSpan(text: prefix));
    var buffer = StringBuffer();
    bool? bufferMarked;
    void flush() {
      if (buffer.isEmpty) return;
      spans.add(TextSpan(
        text: buffer.toString(),
        style: bufferMarked == true ? hl : null,
      ));
      buffer = StringBuffer();
    }

    for (var i = 0; i < text.length; i++) {
      if (bufferMarked != marked[i]) {
        flush();
        bufferMarked = marked[i];
      }
      buffer.write(text[i]);
    }
    flush();
    if (suffix.isNotEmpty) spans.add(TextSpan(text: suffix));
    return RichText(
      text: TextSpan(style: base, children: spans),
      maxLines: maxLines,
      overflow: overflow,
      softWrap: true,
    );
  }
}
