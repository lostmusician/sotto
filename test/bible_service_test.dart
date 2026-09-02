import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sotto/models/journal_entry.dart';
import 'package:sotto/services/bible_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bundled BSB', () {
    final provider = BundledBibleProvider();

    test('contains all books and resolves a known verse offline', () async {
      final books = await provider.books(BundledBibleProvider.version);
      final chapters = await provider.chapters(
        BundledBibleProvider.version,
        books.first,
      );
      final passage = await provider.passage(
        BundledBibleProvider.version,
        'JHN.3.16',
      );

      expect(books, hasLength(66));
      expect(chapters, hasLength(50));
      expect(passage.reference, 'John 3:16');
      expect(passage.content.toLowerCase(), contains('loved the world'));
      expect(passage.version.isOffline, isTrue);
      expect(
        passage.version.copyright.toLowerCase(),
        contains('public domain'),
      );
    });

    test('searches verse text without a network', () async {
      final results = await provider.search(
        BundledBibleProvider.version,
        'quiet waters',
      );
      expect(results, isNotEmpty);
      expect(results.first.reference, startsWith('Psalm 23:'));
    });
  });

  group('YouVersion provider', () {
    test('requires an application key', () async {
      final provider = YouVersionBibleProvider(appKey: '');
      addTearDown(provider.close);
      expect(provider.versions, throwsStateError);
    });

    test('surfaces Retry-After and preserves attribution metadata', () async {
      final rateLimited = YouVersionBibleProvider(
        appKey: 'fixture',
        client: MockClient(
          (_) async => http.Response('', 429, headers: {'retry-after': '17'}),
        ),
      );
      addTearDown(rateLimited.close);
      expect(
        rateLimited.versions,
        throwsA(
          isA<BibleRateLimitException>().having(
            (error) => error.retryAfterSeconds,
            'retryAfterSeconds',
            17,
          ),
        ),
      );

      final provider = YouVersionBibleProvider(
        appKey: 'fixture',
        client: MockClient(
          (_) async => http.Response(
            '{"id":"JHN.3.16","reference":"John 3:16","content":"Text"}',
            200,
          ),
        ),
      );
      addTearDown(provider.close);
      const version = BibleVersion(
        id: 'licensed',
        abbreviation: 'TEST',
        title: 'Test Bible',
        languageTag: 'en',
        copyright: 'Licensed attribution',
      );
      final passage = await provider.passage(version, 'JHN.3.16');
      expect(passage.version.abbreviation, 'TEST');
      expect(passage.version.copyright, 'Licensed attribution');
    });
  });
}
