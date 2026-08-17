/// Pure-dart near-duplicate detection for provider names (bloc: "Garage
/// Audi Casablanca" / "Audi Casablanca" / "Audi Casa" must all resolve to
/// the same référentiel entry instead of spawning near-identical rows).
/// No fuzzy-matching package involved - same house style as the rest of
/// the domain layer (revision_estimation.dart, depreciation_rules.dart).
const _stopWords = {
  'garage', 'centre', 'station', 'atelier', 'concession', 'concessionnaire',
  'de', 'du', 'des', 'la', 'le', 'les', 'l', 'd', 'et', 'auto', 'autos',
};

const _accentMap = {
  'à': 'a', 'â': 'a', 'ä': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i',
  'ô': 'o', 'ö': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c',
};

String _stripAccents(String s) {
  final buffer = StringBuffer();
  for (final rune in s.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accentMap[char] ?? char);
  }
  return buffer.toString();
}

List<String> _tokens(String name) {
  final normalized = _stripAccents(name.toLowerCase())
      .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalized.isEmpty) return const [];
  return normalized.split(' ').where((t) => t.isNotEmpty && !_stopWords.contains(t)).toList();
}

/// Two tokens are considered the same word when identical, or when one is
/// a prefix of the other (min length 3) - catches local abbreviations like
/// "Casa" for "Casablanca".
bool _tokensMatch(String a, String b) {
  if (a == b) return true;
  if (a.length < 3 || b.length < 3) return false;
  return a.startsWith(b) || b.startsWith(a);
}

/// True when [a] and [b] are likely the same real-world provider typed
/// differently. Conservative on purpose: only names sharing (almost) all
/// their meaningful tokens are flagged, so two genuinely different garages
/// that happen to share a brand name ("Audi Rabat" vs "Audi Casablanca")
/// are never merged.
bool isLikelyDuplicate(String a, String b) {
  final tokensA = _tokens(a);
  final tokensB = _tokens(b);
  if (tokensA.isEmpty || tokensB.isEmpty) return false;
  if (tokensA.join(' ') == tokensB.join(' ')) return true;

  final shorter = tokensA.length <= tokensB.length ? tokensA : tokensB;
  final longer = tokensA.length <= tokensB.length ? tokensB : tokensA;

  var matched = 0;
  final remaining = [...longer];
  for (final token in shorter) {
    final i = remaining.indexWhere((t) => _tokensMatch(token, t));
    if (i != -1) {
      matched++;
      remaining.removeAt(i);
    }
  }
  // Every token of the shorter name must find a match in the longer one -
  // that's what makes "Audi Casa" resolve inside "Garage Audi Casablanca"
  // while still rejecting a name that only partially overlaps.
  return matched == shorter.length;
}
