import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/models/journal_entry.dart';
import 'package:sotto/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DatabaseService database;
  setUp(() {
    database = DatabaseService(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });
  tearDown(() => database.close());

  test(
    'stores one daily entry, additional entries, gratitude, and mood',
    () async {
      const dateKey = '2026-09-01';
      final day = JournalDay.empty(dateKey).copyWith(gratitude: 'Warm tea.');
      final daily = DayEntry.empty(
        dateKey: dateKey,
        type: DayEntryType.daily,
      ).copyWith(content: 'The main thought.');
      final additional = DayEntry.empty(
        dateKey: dateKey,
        type: DayEntryType.additional,
      ).copyWith(content: 'A later thought.');
      await database.saveDay(day);
      await database.saveDayEntry(daily);
      await database.saveDayEntry(additional);
      await database.saveCheckIn(
        DailyCheckIn.forDate(
          dateKey: dateKey,
          moodAngle: .3,
          moodIntensity: .7,
        ),
      );

      final loaded = await database.loadBinderDay(dateKey);

      expect(loaded.dailyEntry?.content, 'The main thought.');
      expect(loaded.additionalEntries.single.content, 'A later thought.');
      expect(loaded.day.gratitude, 'Warm tea.');
      expect(loaded.isComplete, isTrue);
    },
  );

  test('enforces one daily entry per date', () async {
    const dateKey = '2026-09-01';
    await database.saveDayEntry(
      DayEntry.empty(dateKey: dateKey, type: DayEntryType.daily),
    );

    expect(
      () => database.saveDayEntry(
        DayEntry.empty(dateKey: dateKey, type: DayEntryType.daily),
      ),
      throwsA(anything),
    );
  });

  test('paginates recorded dates with a stable date cursor', () async {
    for (var day = 1; day <= 24; day++) {
      final key = '2026-08-${day.toString().padLeft(2, '0')}';
      await database.saveDayEntry(
        DayEntry.empty(
          dateKey: key,
          type: DayEntryType.daily,
        ).copyWith(content: 'Entry $day'),
      );
    }

    final first = await database.binderPage(limit: 10);
    final second = await database.binderPage(
      cursor: BinderCursor(first.last.day.dateKey),
      limit: 10,
    );

    expect(first, hasLength(10));
    expect(second, hasLength(10));
    expect(
      first.last.day.dateKey.compareTo(second.first.day.dateKey),
      greaterThan(0),
    );
    expect({
      ...first.map((day) => day.day.dateKey),
      ...second.map((day) => day.day.dateKey),
    }, hasLength(20));
  });

  test('replaces the evening preference', () async {
    await database.saveEveningPreference(
      const EveningPreference(minutesAfterMidnight: 20 * 60 + 15),
    );

    final loaded = await database.eveningPreference();

    expect(loaded.hour, 20);
    expect(loaded.minute, 15);
  });

  test(
    'uses NIV when no preference exists or the legacy BSB is selected',
    () async {
      expect(await database.preferredBibleId(), 'NIV');

      await database.saveSetting(
        DatabaseService.preferredBibleSettingKey,
        'BSB',
      );

      expect(await database.preferredBibleId(), 'NIV');
    },
  );

  test('includes a mood-only day in recorded-date pagination', () async {
    const dateKey = '2026-08-30';
    await database.saveCheckIn(
      DailyCheckIn.forDate(dateKey: dateKey, moodAngle: .7, moodIntensity: .4),
    );

    final page = await database.binderPage();

    expect(page.single.day.dateKey, dateKey);
    expect(page.single.entries, isEmpty);
    expect(page.single.checkIn, isNotNull);
  });

  test(
    'migrates v2 entries into separate day entries and preserves legacy rows',
    () async {
      final directory = await Directory.systemTemp.createTemp('sotto-v3-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/legacy.sqlite';
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            await db.execute('''
            CREATE TABLE journal_entries (
              id TEXT PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL,
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
              target_word_count INTEGER NOT NULL DEFAULT 500,
              status TEXT NOT NULL DEFAULT 'draft', closed_at TEXT,
              reflection_question TEXT, reflection_reply TEXT NOT NULL DEFAULT ''
            )
          ''');
            await db.execute('''
            CREATE TABLE ai_annotations (
              id TEXT PRIMARY KEY, entry_id TEXT NOT NULL, question TEXT NOT NULL,
              anchor_offset INTEGER NOT NULL, created_at TEXT NOT NULL
            )
          ''');
            await db.execute('''
            CREATE TABLE daily_checkins (
              date_key TEXT PRIMARY KEY, mood_angle REAL NOT NULL,
              mood_intensity REAL NOT NULL, created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          },
        ),
      );
      final morning = DateTime(2026, 9, 1, 2).toUtc().toIso8601String();
      final evening = DateTime(2026, 9, 1, 11).toUtc().toIso8601String();
      await legacy.insert(
        'journal_entries',
        _legacyRow('first', 'Morning', morning),
      );
      await legacy.insert(
        'journal_entries',
        _legacyRow('second', 'Evening', evening),
      );
      await legacy.close();

      final migrated = DatabaseService(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      final dateKey = localDateKey(DateTime.parse(morning));
      final day = await migrated.loadBinderDay(dateKey);
      final legacyRows = await (await migrated.database).rawQuery(
        'SELECT count(*) AS total FROM journal_entries',
      );
      final legacyCount = legacyRows.single['total'] as int;

      expect(day.dailyEntry?.id, 'first');
      expect(day.additionalEntries.single.id, 'second');
      expect(legacyCount, 2);
      await migrated.close();
    },
  );
}

Map<String, Object?> _legacyRow(String id, String content, String timestamp) =>
    {
      'id': id,
      'title': 'Untitled entry',
      'content': content,
      'created_at': timestamp,
      'updated_at': timestamp,
      'target_word_count': 500,
      'status': 'closed',
      'closed_at': timestamp,
      'reflection_question': 'Legacy question?',
      'reflection_reply': '',
    };
