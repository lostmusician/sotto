import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/models/journal_entry.dart';
import 'package:sotto/providers/journal_providers.dart';
import 'package:sotto/services/bible_service.dart';
import 'package:sotto/services/database_service.dart';
import 'package:sotto/ui/editor_screen.dart';

import 'support/session_test_doubles.dart';

void main() {
  testWidgets('discovery searches tags and exposes a bounded graph', (
    tester,
  ) async {
    final harness = await _pumpCompletedApp(tester);
    final entry = harness.daily;
    final tag = await harness.database.ensureTag('Work');
    await harness.database.attachTag(
      entryId: entry.id,
      tag: tag,
      source: EntryTagSource.manual,
    );
    await harness.container
        .read(binderControllerProvider.notifier)
        .refresh(anchorDateKey: entry.dateKey);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('binder-discovery')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('journal-search')), findsOneWidget);
    expect(find.text('Work'), findsWidgets);
    expect(find.textContaining('A thoughtful project launch'), findsWidgets);

    await tester.tap(find.text('Connections'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('connections-graph')), findsOneWidget);
  });

  testWidgets(
    'Christian Mode creates Quiet Time and attaches licensed Scripture',
    (tester) async {
      final harness = await _pumpCompletedApp(tester, christianMode: true);

      await tester.tap(find.byKey(const Key('edit-journal')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-quiet-time')), findsOneWidget);
      expect(find.byKey(const Key('open-scripture')), findsOneWidget);

      await tester.tap(find.byKey(const Key('new-quiet-time')));
      await tester.pumpAndSettle();
      expect(
        harness.container
            .read(journalControllerProvider)
            .selectedEntry
            ?.purpose,
        EntryPurpose.quietTime,
      );
      expect(find.text('Observation'), findsOneWidget);
      expect(find.byKey(const Key('gratitude-editor')), findsNothing);

      await tester.tap(find.byKey(const Key('open-scripture')));
      await tester.pumpAndSettle();
      expect(find.text('Scripture'), findsOneWidget);
      await tester.tap(find.text('Genesis 1:1'));
      await tester.pump();
      await tester.tap(find.text('Attach verse'));
      await tester.pumpAndSettle();

      final entryId = harness.container
          .read(journalControllerProvider)
          .selectedEntryId!;
      final references = await harness.database.scripturesForEntry(entryId);
      expect(references.single.reference, 'Genesis 1:1');
      expect(references.single.cachedText, isNull);
      expect(find.text('Genesis 1:1'), findsOneWidget);
    },
  );
}

Future<_Harness> _pumpCompletedApp(
  WidgetTester tester, {
  bool christianMode = false,
}) async {
  final database = FakeDatabaseService();
  const dateKey = '2026-09-01';
  final daily = DayEntry.empty(
    dateKey: dateKey,
    type: DayEntryType.daily,
    now: DateTime(2026, 9, 1, 9),
  ).copyWith(content: 'A thoughtful project launch with the team.');
  await database.saveDayEntry(daily);
  await database.saveCheckIn(
    DailyCheckIn.forDate(dateKey: dateKey, moodAngle: .3, moodIntensity: .7),
  );
  await database.saveSetting(
    DatabaseService.christianModeSettingKey,
    '$christianMode',
  );
  final container = ProviderContainer(
    overrides: [
      databaseServiceProvider.overrideWithValue(database),
      youVersionBibleProvider.overrideWithValue(_FixtureBibleProvider()),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: EditorScreen(autoInitialize: false)),
    ),
  );
  await tester.pump();
  await container
      .read(journalControllerProvider.notifier)
      .initialize(now: DateTime(2026, 9, 1, 20));
  await tester.pumpAndSettle();
  final harness = _Harness(container, database, daily);
  addTearDown(harness.dispose);
  return harness;
}

class _FixtureBibleProvider extends YouVersionBibleProvider {
  _FixtureBibleProvider() : super(appKey: 'fixture');

  static const version = BibleVersion(
    id: '111',
    abbreviation: 'NIV',
    title: 'New International Version',
    languageTag: 'en',
    copyright: 'NIV fixture attribution',
  );

  @override
  Future<List<BibleVersion>> versions() async => const [version];

  @override
  Future<List<BibleBook>> books(BibleVersion version) async => const [
    BibleBook('GEN', 'Genesis', 1),
  ];

  @override
  Future<List<int>> chapters(BibleVersion version, BibleBook book) async =>
      const [1];

  @override
  Future<BiblePassage> passage(BibleVersion version, String passageId) async =>
      BiblePassage(
        id: 'GEN.1.1',
        reference: 'Genesis 1:1',
        content: 'In the beginning God created the heavens and the earth.',
        version: version,
      );
}

class _Harness {
  _Harness(this.container, this.database, this.daily);
  final ProviderContainer container;
  final FakeDatabaseService database;
  final DayEntry daily;

  Future<void> dispose() async {
    container.dispose();
    await database.close();
  }
}
