class FuzzySearchResult {
  final int score;
  final String markedString;

  FuzzySearchResult({required this.score, required this.markedString});
}

class FuzzySearch {
  static FuzzySearchResult fuzzyMatch(String keyword, String target, {bool returnMarkedString = false}) {
    if (keyword.isEmpty) {
      return FuzzySearchResult(score: 0, markedString: target);
    }
    
    keyword = keyword.toLowerCase();
    final lowerTarget = target.toLowerCase();
    
    int score = 0;
    List<int> matches = [];
    int keywordIndex = 0;
    int consecutiveMatches = 0;
    
    for (int i = 0; i < lowerTarget.length; i++) {
      if (keywordIndex < keyword.length && lowerTarget[i] == keyword[keywordIndex]) {
        matches.add(i);
        score += 1 + (consecutiveMatches * 2);
        consecutiveMatches++;
        keywordIndex++;
      } else {
        consecutiveMatches = 0;
      }
    }
    
    if (keywordIndex < keyword.length) {
      // Didn't match all characters in keyword
      return FuzzySearchResult(score: 0, markedString: target);
    }
    
    // Exact match or prefix match bonus
    if (lowerTarget.startsWith(keyword)) {
      score += 10;
    }
    
    if (!returnMarkedString) {
      return FuzzySearchResult(score: score, markedString: target);
    }
    
    String markedString = '';
    String buffer = '';
    
    void flushBuffer() {
      if (buffer.isNotEmpty) {
        markedString += '<b>$buffer</b>';
        buffer = '';
      }
    }
    
    for (int i = 0; i < target.length; i++) {
      if (matches.contains(i)) {
        buffer += target[i];
      } else {
        flushBuffer();
        markedString += target[i];
      }
    }
    flushBuffer();
    
    return FuzzySearchResult(score: score, markedString: markedString);
  }
}
