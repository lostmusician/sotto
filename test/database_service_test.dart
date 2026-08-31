import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/models/journal_entry.dart';
import 'package:sotto/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late DatabaseService database;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    database = DatabaseService(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() => database.close());

  test('persists entry ritual fields and annotations', () async {
    final now = DateTime.utc(2026, 8, 31, 10);
    final entry = JournalEntry.empty(now: now).copyWith(
      content: 'A private thought.',
      status: EntryStatus.closed,
      closedAt: now,
      reflectionQuestion: 'What matters beneath this thought?',
      reflectionReply: 'I want to be honest.',
    );
    final annotation = AiAnnotation.create(
      entryId: entry.id,
      question: 'What matters beneath this thought?',
      anchorOffset: entry.content.length,
    );

    await database.saveEntry(entry.copyWith(annotations: [annotation]));
    final loaded = await database.entryById(entry.id);

    expect(loaded?.status, EntryStatus.closed);
    expect(loaded?.reflectionReply, 'I want to be honest.');
    expect(loaded?.annotations.single.question, annotation.question);
  });

  test(
    'replaces one daily check-in without replacing its creation time',
    () async {
      final created = DateTime.utc(2026, 8, 31, 1);
      final first = DailyCheckIn.today(
        moodAngle: .2,
        moodIntensity: .4,
        now: created,
      );
      await database.saveCheckIn(first);
      await database.saveCheckIn(
        first.copyWith(
          moodAngle: .8,
          moodIntensity: .7,
          updatedAt: created.add(const Duration(hours: 4)),
        ),
      );

      final loaded = await database.checkInForDate(first.dateKey);
      expect(loaded?.moodAngle, .8);
      expect(loaded?.moodIntensity, .7);
      expect(loaded?.createdAt, created);
    },
  );

  test('archive pagination uses closed_at and id as a stable cursor', () async {
    final closedAt = DateTime.utc(2026, 8, 31, 12);
    for (final id in ['c', 'b', 'a']) {
      await database.saveEntry(
        JournalEntry(
          id: id,
          title: id,
          content: 'Entry $id',
          createdAt: closedAt,
          updatedAt: closedAt,
          targetWordCount: 500,
          status: EntryStatus.closed,
          closedAt: closedAt,
        ),
      );
    }

    final first = await database.archivePage(limit: 2);
    final second = await database.archivePage(
      cursor: ArchiveCursor(
        closedAt: first.last.closedAt!,
        entryId: first.last.id,
      ),
      limit: 2,
    );

    expect(first.map((entry) => entry.id), ['c', 'b']);
    expect(second.map((entry) => entry.id), ['a']);
  });

  test('date range query excludes the end boundary', () async {
    final day = DateTime.utc(2026, 8, 31);
    for (var index = 0; index < 3; index++) {
      final closed = day.add(Duration(days: index));
      await database.saveEntry(
        JournalEntry.empty(now: closed).copyWith(
          content: 'Day $index',
          status: EntryStatus.closed,
          closedAt: closed,
        ),
      );
    }

    final entries = await database.closedEntriesBetween(
      day,
      day.add(const Duration(days: 2)),
    );
    expect(entries, hasLength(2));
  });

  test('migrates a version-one database without losing reflection data', () async {
    final directory = await Directory.systemTemp.createTemp('sotto-migration-');
    final path = '${directory.path}/legacy.sqlite';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE journal_entries (id TEXT PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, target_word_count INTEGER NOT NULL DEFAULT 500)',
          );
          await db.execute(
            'CREATE TABLE ai_annotations (id TEXT PRIMARY KEY, entry_id TEXT NOT NULL, question TEXT NOT NULL, anchor_offset INTEGER NOT NULL, created_at TEXT NOT NULL)',
          );
        },
      ),
    );
    final timestamp = DateTime.utc(2026, 8, 30).toIso8601String();
    await legacy.insert('journal_entries', {
      'id': 'legacy',
      'title': 'Old entry',
      'content': 'Something worth keeping',
      'created_at': timestamp,
      'updated_at': timestamp,
      'target_word_count': 500,
    });
    await legacy.insert('ai_annotations', {
      'id': 'annotation',
      'entry_id': 'legacy',
      'question': 'What are you protecting?',
      'anchor_offset': 24,
      'created_at': timestamp,
    });
    await legacy.close();

    final migrated = DatabaseService(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    final entry = await migrated.entryById('legacy');

    expect(entry?.status, EntryStatus.closed);
    expect(entry?.closedAt, DateTime.parse(timestamp));
    expect(entry?.reflectionQuestion, 'What are you protecting?');

    await migrated.close();
    await directory.delete(recursive: true);
  });
}
