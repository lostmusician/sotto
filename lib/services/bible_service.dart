import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/journal_entry.dart';

class BibleBook {
  const BibleBook(this.id, this.name, this.chapterCount);
  final String id;
  final String name;
  final int chapterCount;
}

abstract interface class BibleProvider {
  Future<List<BibleVersion>> versions();
  Future<List<BibleBook>> books(BibleVersion version);
  Future<List<int>> chapters(BibleVersion version, BibleBook book);
  Future<BiblePassage> passage(BibleVersion version, String passageId);
  Future<List<BiblePassage>> search(
    BibleVersion version,
    String query, {
    int limit = 50,
  });
}

class BundledBibleProvider implements BibleProvider {
  static const version = BibleVersion(
    id: 'BSB',
    abbreviation: 'BSB',
    title: 'Berean Standard Bible',
    languageTag: 'en',
    copyright:
        "The Holy Bible, Berean Standard Bible. This text of God's Word has been dedicated to the public domain.",
    isOffline: true,
  );

  Map<String, _Verse>? _verses;
  List<BibleBook>? _books;

  @override
  Future<List<BibleVersion>> versions() async => const [version];

  Future<void> _load() async {
    if (_verses != null) return;
    final source = await rootBundle.loadString('assets/bible/bsb.txt');
    final verses = <String, _Verse>{};
    final chapterCounts = <String, int>{};
    final names = <String, String>{};
    for (final rawLine in const LineSplitter().convert(source)) {
      final line = rawLine.replaceFirst('\ufeff', '').trimRight();
      final tab = line.indexOf('\t');
      if (tab <= 0) continue;
      final reference = line.substring(0, tab).trim();
      final match = RegExp(r'^(.+?) (\d+):(\d+)$').firstMatch(reference);
      if (match == null) continue;
      final bookName = match.group(1)!;
      final chapter = int.parse(match.group(2)!);
      final verse = int.parse(match.group(3)!);
      final bookId = _bookIds[bookName];
      if (bookId == null) continue;
      final passageId = '$bookId.$chapter.$verse';
      verses[passageId] = _Verse(
        passageId,
        reference,
        line.substring(tab + 1).trim(),
        bookId,
        chapter,
        verse,
      );
      names[bookId] = bookName;
      chapterCounts[bookId] = chapter > (chapterCounts[bookId] ?? 0)
          ? chapter
          : chapterCounts[bookId]!;
    }
    _verses = verses;
    _books = [
      for (final entry in _bookIds.entries)
        BibleBook(
          entry.value,
          names[entry.value] ?? entry.key,
          chapterCounts[entry.value] ?? 0,
        ),
    ];
  }

  @override
  Future<List<BibleBook>> books(BibleVersion version) async {
    await _load();
    return List.unmodifiable(_books!);
  }

  @override
  Future<List<int>> chapters(BibleVersion version, BibleBook book) async => [
    for (var chapter = 1; chapter <= book.chapterCount; chapter++) chapter,
  ];

  @override
  Future<BiblePassage> passage(
    BibleVersion requestedVersion,
    String passageId,
  ) async {
    await _load();
    final normalized = passageId.toUpperCase();
    final exact = _verses![normalized];
    if (exact != null) {
      return BiblePassage(
        id: exact.id,
        reference: exact.reference,
        content: exact.text,
        version: version,
      );
    }
    final parts = normalized.split('.');
    if (parts.length < 2) throw StateError('Passage not found: $passageId');
    final prefix = '${parts[0]}.${parts[1]}.';
    final chapterVerses =
        _verses!.values.where((verse) => verse.id.startsWith(prefix)).toList()
          ..sort((a, b) => a.verse.compareTo(b.verse));
    if (chapterVerses.isEmpty) {
      throw StateError('Passage not found: $passageId');
    }
    return BiblePassage(
      id: '${parts[0]}.${parts[1]}',
      reference: '${_bookName(parts[0])} ${parts[1]}',
      content: chapterVerses
          .map((verse) => '${verse.verse} ${verse.text}')
          .join('\n'),
      version: version,
    );
  }

  @override
  Future<List<BiblePassage>> search(
    BibleVersion requestedVersion,
    String query, {
    int limit = 50,
  }) async {
    await _load();
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return _verses!.values
        .where((verse) => verse.text.toLowerCase().contains(needle))
        .take(limit)
        .map(
          (verse) => BiblePassage(
            id: verse.id,
            reference: verse.reference,
            content: verse.text,
            version: version,
          ),
        )
        .toList();
  }

  String _bookName(String id) =>
      _bookIds.entries.firstWhere((entry) => entry.value == id).key;
}

class YouVersionBibleProvider implements BibleProvider {
  YouVersionBibleProvider({String? appKey, http.Client? client})
    : appKey = appKey ?? const String.fromEnvironment('YOUVERSION_APP_KEY'),
      _client = client ?? http.Client();

  final String appKey;
  final http.Client _client;
  static final _base = Uri.parse('https://api.youversion.com/v1/');

  bool get isConfigured => appKey.isNotEmpty;

  Map<String, String> get _headers {
    if (appKey.isEmpty) {
      throw StateError(
        'YouVersion access has not been configured for this build.',
      );
    }
    return {'X-YVP-App-Key': appKey, 'Accept': 'application/json'};
  }

  @override
  Future<List<BibleVersion>> versions() async {
    final json = await _get('bibles?language_ranges=en&page_size=99');
    return (json['data'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (item) => BibleVersion(
            id: '${item['id']}',
            abbreviation:
                '${item['localized_abbreviation'] ?? item['abbreviation']}',
            title: '${item['localized_title'] ?? item['title']}',
            languageTag: '${item['language_tag'] ?? 'en'}',
            copyright: '${item['copyright'] ?? ''}',
          ),
        )
        .toList();
  }

  @override
  Future<List<BibleBook>> books(BibleVersion version) async {
    final json = await _get('bibles/${version.id}/books');
    return (json['data'] as List<dynamic>? ??
            json['books'] as List<dynamic>? ??
            const [])
        .cast<Map<String, dynamic>>()
        .map(
          (item) => BibleBook(
            '${item['usfm'] ?? item['id']}',
            '${item['localized_title'] ?? item['title'] ?? item['name']}',
            item['chapter_count'] as int? ??
                (item['chapters'] as List<dynamic>? ?? const []).length.clamp(
                  1,
                  150,
                ),
          ),
        )
        .toList();
  }

  @override
  Future<List<int>> chapters(BibleVersion version, BibleBook book) async {
    final json = await _get('bibles/${version.id}/books/${book.id}/chapters');
    final rows =
        (json['data'] as List<dynamic>? ??
                json['chapters'] as List<dynamic>? ??
                const [])
            .cast<Map<String, dynamic>>();
    return rows
        .map((item) {
          final raw =
              '${item['number'] ?? item['chapter_number'] ?? item['id']}';
          return int.tryParse(raw) ??
              int.tryParse(RegExp(r'(\d+)$').firstMatch(raw)?.group(1) ?? '');
        })
        .whereType<int>()
        .toList();
  }

  @override
  Future<BiblePassage> passage(BibleVersion version, String passageId) async {
    final json = await _get(
      'bibles/${version.id}/passages/${Uri.encodeComponent(passageId)}?format=text&include_headings=false&include_notes=false',
    );
    final data = json['data'] is Map<String, dynamic>
        ? json['data']! as Map<String, dynamic>
        : json;
    return BiblePassage(
      id: '${data['id']}',
      reference: '${data['reference']}',
      content: '${data['content']}',
      version: version,
    );
  }

  @override
  Future<List<BiblePassage>> search(
    BibleVersion version,
    String query, {
    int limit = 50,
  }) => Future.error(
    UnsupportedError(
      'YouVersion does not expose general full-text Bible search through this provider.',
    ),
  );

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _client
        .get(_base.resolve(path), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 429) {
      final retry = response.headers['retry-after'];
      throw BibleRateLimitException(retry == null ? null : int.tryParse(retry));
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw StateError(
        'This Bible version is not licensed to the configured app.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'YouVersion request failed (${response.statusCode}).',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void close() => _client.close();
}

class BibleRateLimitException implements Exception {
  const BibleRateLimitException(this.retryAfterSeconds);
  final int? retryAfterSeconds;
}

class _Verse {
  const _Verse(
    this.id,
    this.reference,
    this.text,
    this.bookId,
    this.chapter,
    this.verse,
  );
  final String id;
  final String reference;
  final String text;
  final String bookId;
  final int chapter;
  final int verse;
}

const _bookIds = <String, String>{
  'Genesis': 'GEN',
  'Exodus': 'EXO',
  'Leviticus': 'LEV',
  'Numbers': 'NUM',
  'Deuteronomy': 'DEU',
  'Joshua': 'JOS',
  'Judges': 'JDG',
  'Ruth': 'RUT',
  '1 Samuel': '1SA',
  '2 Samuel': '2SA',
  '1 Kings': '1KI',
  '2 Kings': '2KI',
  '1 Chronicles': '1CH',
  '2 Chronicles': '2CH',
  'Ezra': 'EZR',
  'Nehemiah': 'NEH',
  'Esther': 'EST',
  'Job': 'JOB',
  'Psalm': 'PSA',
  'Proverbs': 'PRO',
  'Ecclesiastes': 'ECC',
  'Song of Solomon': 'SNG',
  'Isaiah': 'ISA',
  'Jeremiah': 'JER',
  'Lamentations': 'LAM',
  'Ezekiel': 'EZK',
  'Daniel': 'DAN',
  'Hosea': 'HOS',
  'Joel': 'JOL',
  'Amos': 'AMO',
  'Obadiah': 'OBA',
  'Jonah': 'JON',
  'Micah': 'MIC',
  'Nahum': 'NAM',
  'Habakkuk': 'HAB',
  'Zephaniah': 'ZEP',
  'Haggai': 'HAG',
  'Zechariah': 'ZEC',
  'Malachi': 'MAL',
  'Matthew': 'MAT',
  'Mark': 'MRK',
  'Luke': 'LUK',
  'John': 'JHN',
  'Acts': 'ACT',
  'Romans': 'ROM',
  '1 Corinthians': '1CO',
  '2 Corinthians': '2CO',
  'Galatians': 'GAL',
  'Ephesians': 'EPH',
  'Philippians': 'PHP',
  'Colossians': 'COL',
  '1 Thessalonians': '1TH',
  '2 Thessalonians': '2TH',
  '1 Timothy': '1TI',
  '2 Timothy': '2TI',
  'Titus': 'TIT',
  'Philemon': 'PHM',
  'Hebrews': 'HEB',
  'James': 'JAS',
  '1 Peter': '1PE',
  '2 Peter': '2PE',
  '1 John': '1JN',
  '2 John': '2JN',
  '3 John': '3JN',
  'Jude': 'JUD',
  'Revelation': 'REV',
};
