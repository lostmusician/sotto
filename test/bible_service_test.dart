import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sotto/models/journal_entry.dart';
import 'package:sotto/services/bible_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YouVersion provider', () {
    test('requires an application key', () async {
      final provider = YouVersionBibleProvider(appKey: '');
      addTearDown(provider.close);
      expect(provider.versions, throwsStateError);
    });

    test('offers only ESV, NIV, ERV, and NKJV in product order', () async {
      Uri? requestedUri;
      final provider = YouVersionBibleProvider(
        appKey: 'fixture',
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response(
            jsonEncode({
              'data': [
                _versionJson(114, 'NKJV', 'New King James Version'),
                _versionJson(3034, 'BSB', 'Berean Standard Bible'),
                _versionJson(111, 'NIV', 'New International Version'),
                _versionJson(406, 'ERV', 'Easy-to-Read Version'),
                _versionJson(59, 'ESV', 'English Standard Version'),
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(provider.close);

      final versions = await provider.versions();

      expect(versions.map((version) => version.abbreviation), [
        'ESV',
        'NIV',
        'ERV',
        'NKJV',
      ]);
      expect(versions.every((version) => !version.isOffline), isTrue);
      expect(requestedUri?.queryParametersAll['language_ranges[]'], ['en*']);
      expect(requestedUri?.queryParameters, isNot(contains('language_ranges')));
    });

    test(
      'discovers an accessible NIV directly when the collection omits it',
      () async {
        final requestedPaths = <String>[];
        final provider = YouVersionBibleProvider(
          appKey: 'fixture',
          client: MockClient((request) async {
            requestedPaths.add(request.url.path);
            if (request.url.path == '/v1/bibles') {
              return http.Response(
                jsonEncode({
                  'data': [_versionJson(3034, 'BSB', 'Berean Standard Bible')],
                }),
                200,
              );
            }
            if (request.url.path == '/v1/bibles/111') {
              return http.Response(
                jsonEncode(
                  _versionJson(111, 'NIV', 'New International Version'),
                ),
                200,
              );
            }
            return http.Response('{"message":"Not licensed"}', 403);
          }),
        );
        addTearDown(provider.close);

        final versions = await provider.versions();

        expect(versions.map((version) => version.abbreviation), ['NIV']);
        expect(requestedPaths, contains('/v1/bibles/111'));
      },
    );

    test('includes API validation details in request errors', () async {
      final provider = YouVersionBibleProvider(
        appKey: 'fixture',
        client: MockClient(
          (_) async =>
              http.Response('{"message":"language_ranges[] is required"}', 422),
        ),
      );
      addTearDown(provider.close);

      expect(
        provider.versions,
        throwsA(
          isA<http.ClientException>().having(
            (error) => error.message,
            'message',
            contains('language_ranges[] is required'),
          ),
        ),
      );
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

Map<String, Object> _versionJson(int id, String abbreviation, String title) => {
  'id': id,
  'abbreviation': abbreviation,
  'localized_abbreviation': abbreviation,
  'title': title,
  'localized_title': title,
  'language_tag': 'en',
  'copyright': '$abbreviation licensed attribution',
};
