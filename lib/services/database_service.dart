import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/journal_entry.dart';

class DatabaseService {
  DatabaseService({DatabaseFactory? factory, String? databasePath})
    : _injectedFactory = factory,
      _injectedPath = databasePath;

  static const schemaVersion = 3;
  static const eveningSettingKey = 'evening_minutes';

  final DatabaseFactory? _injectedFactory;
  final String? _injectedPath;
  Future<Database>? _databaseFuture;

  Future<Database> get database => _databaseFuture ??= _open();

  Future<Database> _open() async {
    final factory = _injectedFactory ?? _platformFactory();
    final path = _injectedPath ?? await _defaultPath();
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _createSchema(db),
        onUpgrade: _upgradeSchema,
      ),
    );
  }

  Future<void> _createSchema(Database db) async {
    await _createCheckInTable(db);
    await _createDailyTables(db);
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE journal_entries ADD COLUMN status TEXT NOT NULL DEFAULT 'draft'",
      );
      await db.execute('ALTER TABLE journal_entries ADD COLUMN closed_at TEXT');
      await db.execute(
        'ALTER TABLE journal_entries ADD COLUMN reflection_question TEXT',
      );
      await db.execute(
        "ALTER TABLE journal_entries ADD COLUMN reflection_reply TEXT NOT NULL DEFAULT ''",
      );
      await db.execute('''
        UPDATE journal_entries
        SET status = CASE WHEN trim(content) = '' THEN 'draft' ELSE 'closed' END,
            closed_at = CASE WHEN trim(content) = '' THEN NULL ELSE updated_at END
      ''');
      await db.execute('''
        UPDATE journal_entries
        SET reflection_question = (
          SELECT question FROM ai_annotations
          WHERE ai_annotations.entry_id = journal_entries.id
          ORDER BY created_at DESC LIMIT 1
        )
        WHERE EXISTS (
          SELECT 1 FROM ai_annotations
          WHERE ai_annotations.entry_id = journal_entries.id
        )
      ''');
      await _createCheckInTable(db);
    }
    if (oldVersion < 3) {
      await _createDailyTables(db);
      await _migrateLegacyEntries(db);
    }
  }

  Future<void> _createCheckInTable(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS daily_checkins (
      date_key TEXT PRIMARY KEY,
      mood_angle REAL NOT NULL,
      mood_intensity REAL NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  Future<void> _createDailyTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS journal_days (
        date_key TEXT PRIMARY KEY,
        gratitude TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS day_entries (
        id TEXT PRIMARY KEY,
        date_key TEXT NOT NULL,
        entry_type TEXT NOT NULL CHECK(entry_type IN ('daily', 'additional')),
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(date_key) REFERENCES journal_days(date_key) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS one_daily_entry_per_day
      ON day_entries(date_key) WHERE entry_type = 'daily'
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS day_entries_date_order
      ON day_entries(date_key, entry_type, created_at DESC, id DESC)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )
    ''');
    await db.insert('app_settings', {
      'setting_key': eveningSettingKey,
      'setting_value': '${18 * 60}',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _migrateLegacyEntries(DatabaseExecutor db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'journal_entries'",
    );
    if (tables.isEmpty) return;

    final rows = await db.query(
      'journal_entries',
      orderBy: 'created_at ASC, id ASC',
    );
    final latestDraftRows = await db.query(
      'journal_entries',
      where: "status = 'draft'",
      orderBy: 'updated_at DESC, id DESC',
      limit: 1,
    );
    final latestDraftId = latestDraftRows.firstOrNull?['id'] as String?;
    final groups = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final content = (row['content'] as String?) ?? '';
      if (content.trim().isEmpty && row['id'] != latestDraftId) continue;
      final dateKey = localDateKey(
        DateTime.parse(row['created_at']! as String),
      );
      groups.putIfAbsent(dateKey, () => []).add(row);
    }

    for (final group in groups.entries) {
      final rowsForDay = group.value;
      final firstNonEmpty = rowsForDay
          .where(
            ((row) => ((row['content'] as String?) ?? '').trim().isNotEmpty),
          )
          .firstOrNull;
      final dailyRow = firstNonEmpty ?? rowsForDay.first;
      final createdAt = dailyRow['created_at']! as String;
      final updatedAt = rowsForDay.last['updated_at']! as String;
      await db.insert('journal_days', {
        'date_key': group.key,
        'gratitude': '',
        'created_at': createdAt,
        'updated_at': updatedAt,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      for (final row in rowsForDay) {
        await db.insert('day_entries', {
          'id': row['id'],
          'date_key': group.key,
          'entry_type': row['id'] == dailyRow['id']
              ? DayEntryType.daily.name
              : DayEntryType.additional.name,
          'title': row['title'] ?? '',
          'content': row['content'] ?? '',
          'created_at': row['created_at'],
          'updated_at': row['updated_at'],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }

    final checkIns = await db.query('daily_checkins');
    for (final checkIn in checkIns) {
      await db.insert('journal_days', {
        'date_key': checkIn['date_key'],
        'gratitude': '',
        'created_at': checkIn['created_at'],
        'updated_at': checkIn['updated_at'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  DatabaseFactory _platformFactory() {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return mobile.databaseFactory;
  }

  Future<String> _defaultPath() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return p.join(directory.path, 'sotto.sqlite');
  }

  Future<JournalDay> ensureDay(String dateKey, {DateTime? now}) async {
    final db = await database;
    final existing = await journalDay(dateKey);
    if (existing != null) return existing;
    final day = JournalDay.empty(dateKey, now: now);
    await db.insert(
      'journal_days',
      day.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return await journalDay(dateKey) ?? day;
  }

  Future<JournalDay?> journalDay(String dateKey) async {
    final db = await database;
    final rows = await db.query(
      'journal_days',
      where: 'date_key = ?',
      whereArgs: [dateKey],
      limit: 1,
    );
    return rows.isEmpty ? null : JournalDay.fromMap(rows.first);
  }

  Future<void> saveDay(JournalDay day) async {
    final db = await database;
    final changed = await db.update(
      'journal_days',
      day.toMap(),
      where: 'date_key = ?',
      whereArgs: [day.dateKey],
    );
    if (changed == 0) await db.insert('journal_days', day.toMap());
  }

  Future<List<DayEntry>> entriesForDay(String dateKey) async {
    final db = await database;
    final rows = await db.query(
      'day_entries',
      where: 'date_key = ?',
      whereArgs: [dateKey],
      orderBy:
          "CASE entry_type WHEN 'daily' THEN 0 ELSE 1 END, created_at DESC, id DESC",
    );
    return rows.map(DayEntry.fromMap).toList();
  }

  Future<DayEntry?> entryById(String id) async {
    final db = await database;
    final rows = await db.query(
      'day_entries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : DayEntry.fromMap(rows.first);
  }

  Future<void> saveDayEntry(DayEntry entry) async {
    final db = await database;
    await ensureDay(entry.dateKey, now: entry.createdAt);
    final changed = await db.update(
      'day_entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
    if (changed == 0) await db.insert('day_entries', entry.toMap());
  }

  Future<void> deleteDayEntry(String id) async {
    final db = await database;
    await db.delete('day_entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<DailyCheckIn?> checkInForDate(String dateKey) async {
    final db = await database;
    final rows = await db.query(
      'daily_checkins',
      where: 'date_key = ?',
      whereArgs: [dateKey],
      limit: 1,
    );
    return rows.isEmpty ? null : DailyCheckIn.fromMap(rows.first);
  }

  Future<void> saveCheckIn(DailyCheckIn checkIn) async {
    final db = await database;
    await ensureDay(checkIn.dateKey, now: checkIn.createdAt);
    final existing = await checkInForDate(checkIn.dateKey);
    final row = checkIn.copyWith(updatedAt: DateTime.now().toUtc()).toMap();
    if (existing != null) {
      row['created_at'] = existing.createdAt.toIso8601String();
    }
    await db.insert(
      'daily_checkins',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<BinderDay> loadBinderDay(String dateKey, {bool create = false}) async {
    final day = create
        ? await ensureDay(dateKey)
        : await journalDay(dateKey) ?? JournalDay.empty(dateKey);
    final values = await Future.wait<Object?>([
      entriesForDay(dateKey),
      checkInForDate(dateKey),
    ]);
    return BinderDay(
      day: day,
      entries: values[0] as List<DayEntry>,
      checkIn: values[1] as DailyCheckIn?,
    );
  }

  Future<List<BinderDay>> binderPage({
    BinderCursor? cursor,
    int limit = 20,
  }) async {
    final db = await database;
    final where = StringBuffer('''
      (trim(gratitude) != '' OR
       EXISTS (SELECT 1 FROM day_entries e
               WHERE e.date_key = journal_days.date_key
                 AND (trim(e.content) != '' OR trim(e.title) != '')) OR
       EXISTS (SELECT 1 FROM daily_checkins c
               WHERE c.date_key = journal_days.date_key))
    ''');
    final args = <Object?>[];
    if (cursor != null) {
      where.write(' AND date_key < ?');
      args.add(cursor.dateKey);
    }
    final rows = await db.query(
      'journal_days',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'date_key DESC',
      limit: limit,
    );
    return Future.wait(
      rows.map((row) => loadBinderDay(row['date_key']! as String)),
    );
  }

  Future<EveningPreference> eveningPreference() async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      where: 'setting_key = ?',
      whereArgs: [eveningSettingKey],
      limit: 1,
    );
    final value = rows.isEmpty
        ? 18 * 60
        : int.tryParse(rows.first['setting_value']! as String) ?? 18 * 60;
    return EveningPreference(minutesAfterMidnight: value.clamp(0, 1439));
  }

  Future<void> saveEveningPreference(EveningPreference preference) async {
    final db = await database;
    await db.insert('app_settings', {
      'setting_key': eveningSettingKey,
      'setting_value': '${preference.minutesAfterMidnight.clamp(0, 1439)}',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> close() async {
    final pendingDatabase = _databaseFuture;
    _databaseFuture = null;
    if (pendingDatabase != null) await (await pendingDatabase).close();
  }
}
