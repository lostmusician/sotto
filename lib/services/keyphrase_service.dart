import 'dart:math' as math;

import 'package:text_analysis/text_analysis.dart';

abstract interface class KeyphraseExtractor {
  Future<List<KeyphraseCandidate>> extract({
    required String content,
    String title = '',
    String gratitude = '',
    Map<String, int> corpusFrequency = const {},
    int corpusSize = 1,
    int limit = 5,
  });
}

class KeyphraseCandidate {
  const KeyphraseCandidate(this.phrase, this.score);
  final String phrase;
  final double score;
}

class RakeKeyphraseExtractor implements KeyphraseExtractor {
  const RakeKeyphraseExtractor();

  static const _journalStopWords = {
    'today',
    'day',
    'felt',
    'feel',
    'feeling',
    'thing',
    'things',
    'really',
    'just',
    'went',
    'got',
    'now',
    'tonight',
    'morning',
    'afternoon',
    'evening',
    'yesterday',
    'tomorrow',
    'journal',
    'entry',
  };

  @override
  Future<List<KeyphraseCandidate>> extract({
    required String content,
    String title = '',
    String gratitude = '',
    Map<String, int> corpusFrequency = const {},
    int corpusSize = 1,
    int limit = 5,
  }) async {
    final source = [
      title,
      content,
      gratitude,
    ].where((value) => value.trim().isNotEmpty).join('\n');
    if (source.trim().isEmpty || limit <= 0) return const [];

    final document = await TextDocument.analyze(
      sourceText: source,
      analyzer: English.analyzer,
      nGramRange: NGramRange(1, 3),
    );
    final scores = <String, double>{};
    final lowerTitle = title.toLowerCase();
    final lowerGratitude = gratitude.toLowerCase();
    final lowerContent = content.toLowerCase();
    for (final entry in document.keywords.keywordScores.entries) {
      final phrase = _clean(entry.key);
      if (!_isUseful(phrase)) continue;
      final count = _occurrences(lowerContent, phrase);
      final documentFrequency = corpusFrequency[phrase] ?? 0;
      final rarity = math.log((corpusSize + 1) / (documentFrequency + 1)) + 1;
      final titleBoost = lowerTitle.contains(phrase) ? 1.35 : 1.0;
      final gratitudeBoost = lowerGratitude.contains(phrase) ? 1.18 : 1.0;
      final repetitionBoost = 1 + math.min(count - 1, 3) * .12;
      final lengthBalance = phrase.split(' ').length == 1 ? .82 : 1.0;
      scores[phrase] =
          entry.value *
          rarity *
          titleBoost *
          gratitudeBoost *
          repetitionBoost *
          lengthBalance;
    }
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maximum = ranked.firstOrNull?.value ?? 1;
    return ranked
        .take(limit)
        .map(
          (entry) => KeyphraseCandidate(
            _displayPhrase(entry.key, source),
            (entry.value / maximum).clamp(0, 1),
          ),
        )
        .toList();
  }

  static String _clean(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9' -]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _isUseful(String phrase) {
    if (phrase.length < 3 || phrase.length > 48) return false;
    final words = phrase.split(' ');
    if (words.length > 3) return false;
    if (words.every(_journalStopWords.contains)) return false;
    if (words.any((word) => word.length < 2)) return false;
    return RegExp(r'[a-z]').hasMatch(phrase);
  }

  static int _occurrences(String source, String phrase) {
    if (source.isEmpty) return 1;
    return RegExp(
      RegExp.escape(phrase),
      caseSensitive: false,
    ).allMatches(source).length.clamp(1, 4);
  }

  static String _displayPhrase(String phrase, String source) {
    final match = RegExp(
      RegExp.escape(phrase),
      caseSensitive: false,
    ).firstMatch(source);
    if (match == null) return phrase;
    return source.substring(match.start, match.end).trim();
  }
}
