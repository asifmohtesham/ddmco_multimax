/// Pure HTML→plain-text helpers for Frappe rich-text ("Text Editor") fields.
///
/// Frappe stores fields like ToDo.description as HTML (Desk's Quill editor
/// emits `<div class="ql-editor read-mode"><p>…</p></div>`). These helpers
/// flatten that markup for surfaces that need plain text. Kept top-level and
/// pure so they are unit-testable without a widget tree.
library;

String _decodeEntities(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&#39;', "'")
    .replaceAll('&quot;', '"');

/// Converts rich-text HTML to multi-line plain text — for plain-text
/// editors. `<br>` and block-close tags become newlines, every other tag is
/// stripped, common entities are decoded, and runs of 3+ newlines collapse
/// to one blank line.
String htmlToPlainText(String html) {
  var s = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li|h[1-6])>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '');
  s = _decodeEntities(s);
  s = s
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

/// Flattens rich-text HTML to a single-line plain string — for titles and
/// card summaries. Same conversion as [htmlToPlainText], then all whitespace
/// (including newlines) collapses to single spaces.
String htmlToSingleLine(String html) =>
    htmlToPlainText(html).replaceAll(RegExp(r'\s+'), ' ').trim();
