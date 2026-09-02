import 'dart:convert';

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

class YouVersionBibleProvider implements BibleProvider {
  YouVersionBibleProvider({String? appKey, http.Client? client})
    : appKey = appKey ?? const String.fromEnvironment('YOUVERSION_APP_KEY'),
      _client = client ?? http.Client();

  final String appKey;
  final http.Client _client;
  static final _base = Uri.parse('https://api.youversion.com/v1/');
  static const supportedAbbreviations = ['ESV', 'NIV', 'ERV', 'NKJV'];

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
    final json = await _get('bibles?language_ranges%5B%5D=en&page_size=99');
    final versions = (json['data'] as List<dynamic>? ?? const [])
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
    final byAbbreviation = {
      for (final version in versions)
        version.abbreviation.trim().toUpperCase(): version,
    };
    return [
      for (final abbreviation in supportedAbbreviations)
        ?byAbbreviation[abbreviation],
    ];
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
      final detail = _responseDetail(response.body);
      throw http.ClientException(
        'YouVersion request failed (${response.statusCode})'
        '${detail.isEmpty ? '.' : ': $detail'}',
        response.request?.url,
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void close() => _client.close();

  String _responseDetail(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return '';
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded case {'message': final Object message}) return '$message';
      if (decoded case {'detail': final Object detail}) return '$detail';
      if (decoded case {'error': final Object error}) return '$error';
    } catch (_) {
      // Fall through to a bounded plain-text response.
    }
    return trimmed.length <= 240 ? trimmed : '${trimmed.substring(0, 240)}…';
  }
}

class BibleRateLimitException implements Exception {
  const BibleRateLimitException(this.retryAfterSeconds);
  final int? retryAfterSeconds;
}
