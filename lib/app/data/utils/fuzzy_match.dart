/// Fuzzy pattern matcher — a faithful port of Frappe v15's
/// `frappe/public/js/frappe/ui/toolbar/fuzzy_match.js` (itself a port of
/// Forrest Smith's `fts_fuzzy_match`).
///
/// Every character of [pattern] must appear in [str] in order (case
/// insensitive). The score rewards adjacent matches, matches after a
/// separator, camel-case boundaries and a first-letter hit; it penalises
/// leading unmatched letters (capped) and every unmatched letter.
///
/// Pure. Used by the Awesome Bar to rank "Delivery Note List" against `dn`.
library;

const int kFuzzySequentialBonus = 25; // bonus for adjacent matches
const int kFuzzySeparatorBonus = 30; // bonus if match occurs after a separator
const int kFuzzyCamelBonus = 30; // bonus if match is uppercase and prev is lower
const int kFuzzyFirstLetterBonus = 15; // bonus if the first letter is matched
const int kFuzzyLeadingLetterPenalty = -5; // per letter before the first match
const int kFuzzyMaxLeadingLetterPenalty = -15; // cap on the leading penalty
const int kFuzzyUnmatchedLetterPenalty = -1;

const int _kRecursionLimit = 10;
const int _kMaxMatches = 256;

/// Result of [fuzzyMatch]: whether the whole [pattern] was found, its score,
/// and the indices of the matched characters in the searched string.
class FuzzyMatchResult {
  final bool matched;
  final int score;
  final List<int> matches;

  const FuzzyMatchResult(this.matched, this.score, this.matches);

  static const FuzzyMatchResult none = FuzzyMatchResult(false, 0, []);

  @override
  String toString() => 'FuzzyMatchResult($matched, $score, $matches)';
}

/// Fuzzy-finds [pattern] inside [str]. Mirrors `fuzzy_match(pattern, str)`.
FuzzyMatchResult fuzzyMatch(String pattern, String str) {
  if (pattern.isEmpty || str.isEmpty) return FuzzyMatchResult.none;
  final r = _fuzzyMatchRecursive(
    pattern,
    str,
    0,
    0,
    null,
    <int>[],
    _kMaxMatches,
    0,
    0,
    _kRecursionLimit,
  );
  return r;
}

FuzzyMatchResult _fuzzyMatchRecursive(
  String pattern,
  String str,
  int patternCurIndex,
  int strCurrIndex,
  List<int>? srcMatches,
  List<int> matches,
  int maxMatches,
  int nextMatch,
  int recursionCount,
  int recursionLimit,
) {
  int outScore = 0;

  if (++recursionCount >= recursionLimit) {
    return FuzzyMatchResult(false, outScore, matches);
  }
  if (patternCurIndex == pattern.length || strCurrIndex == str.length) {
    return FuzzyMatchResult(false, outScore, matches);
  }

  bool recursiveMatch = false;
  List<int> bestRecursiveMatches = <int>[];
  int bestRecursiveScore = 0;
  bool firstMatch = true;

  while (patternCurIndex < pattern.length && strCurrIndex < str.length) {
    if (pattern[patternCurIndex].toLowerCase() ==
        str[strCurrIndex].toLowerCase()) {
      if (nextMatch >= maxMatches) {
        return FuzzyMatchResult(false, outScore, matches);
      }
      if (firstMatch && srcMatches != null) {
        matches = List<int>.of(srcMatches);
        firstMatch = false;
      }

      final rec = _fuzzyMatchRecursive(
        pattern,
        str,
        patternCurIndex,
        strCurrIndex + 1,
        matches,
        <int>[],
        maxMatches,
        nextMatch,
        recursionCount,
        recursionLimit,
      );
      if (rec.matched) {
        if (!recursiveMatch || rec.score > bestRecursiveScore) {
          bestRecursiveMatches = List<int>.of(rec.matches);
          bestRecursiveScore = rec.score;
        }
        recursiveMatch = true;
      }

      // JS `matches[next_match++] = idx` grows the array in place.
      if (nextMatch < matches.length) {
        matches[nextMatch] = strCurrIndex;
      } else {
        matches.add(strCurrIndex);
      }
      nextMatch++;
      ++patternCurIndex;
    }
    ++strCurrIndex;
  }

  final matched = patternCurIndex == pattern.length;

  if (matched) {
    outScore = 100;

    int penalty = kFuzzyLeadingLetterPenalty * matches[0];
    penalty = penalty < kFuzzyMaxLeadingLetterPenalty
        ? kFuzzyMaxLeadingLetterPenalty
        : penalty;
    outScore += penalty;

    final unmatched = str.length - nextMatch;
    outScore += kFuzzyUnmatchedLetterPenalty * unmatched;

    for (int i = 0; i < nextMatch; i++) {
      final currIdx = matches[i];
      if (i > 0) {
        final prevIdx = matches[i - 1];
        if (currIdx == prevIdx + 1) outScore += kFuzzySequentialBonus;
      }
      if (currIdx > 0) {
        final neighbor = str[currIdx - 1];
        final curr = str[currIdx];
        if (neighbor != neighbor.toUpperCase() &&
            curr != curr.toLowerCase()) {
          outScore += kFuzzyCamelBonus;
        }
        final isNeighbourSeparator = neighbor == '_' || neighbor == ' ';
        if (isNeighbourSeparator) outScore += kFuzzySeparatorBonus;
      } else {
        outScore += kFuzzyFirstLetterBonus;
      }
    }

    if (recursiveMatch && bestRecursiveScore > outScore) {
      return FuzzyMatchResult(
          true, bestRecursiveScore, List<int>.of(bestRecursiveMatches));
    }
    return FuzzyMatchResult(true, outScore, List<int>.of(matches));
  }
  return FuzzyMatchResult(false, outScore, matches);
}

/// `frappe.search.utils.fuzzy_search(keywords, item, true)` — the score
/// (0 when nothing matched) plus the matched indices for highlighting.
///
/// Frappe callers test the score for truthiness, so a matched string whose
/// score computes to exactly 0 is treated as no match, as it is there.
FuzzyMatchResult fuzzySearch(String keywords, String item) {
  final r = fuzzyMatch(keywords, item);
  if (!r.matched || r.score == 0) return FuzzyMatchResult.none;
  return r;
}
