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

  static const schemaVersion = 2;

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
    await db.execute('''
      CREATE TABLE journal_entries (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        target_word_count INTEGER NOT NULL DEFAULT 500,
        status TEXT NOT NULL DEFAULT 'draft',
        closed_at TEXT,
        reflection_question TEXT,
        reflection_reply TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE ai_annotations (
        id TEXT PRIMARY KEY,
        entry_id TEXT NOT NULL,
        question TEXT NOT NULL,
        anchor_offset INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(entry_id) REFERENCES journal_entries(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX annotations_entry_id ON ai_annotations(entry_id, created_at)',
    );
    await _createCheckInTable(db);
    await _createArchiveIndex(db);
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
          SET status = CASE
                WHEN trim(content) = '' THEN 'draft'
                ELSE 'closed'
              END,
              closed_at = CASE
                WHEN trim(content) = '' THEN NULL
                ELSE updated_at
              END
        ''');
      await db.execute('''
          UPDATE journal_entries
          SET reflection_question = (
            SELECT question
            FROM ai_annotations
            WHERE ai_annotations.entry_id = journal_entries.id
            ORDER BY created_at DESC
            LIMIT 1
          )
          WHERE EXISTS (
            SELECT 1 FROM ai_annotations
            WHERE ai_annotations.entry_id = journal_entries.id
          )
        ''');
      await _createCheckInTable(db);
      await _createArchiveIndex(db);
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

  Future<void> _createArchiveIndex(DatabaseExecutor db) => db.execute('''
    CREATE INDEX IF NOT EXISTS entries_archive_cursor
    ON journal_entries(status, closed_at DESC, id DESC)
  ''');

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

  Future<JournalEntry?> latestDraft() async {
    final db = await database;
    final rows = await db.query(
      'journal_entries',
      where: 'status = ?',
      whereArgs: [EntryStatus.draft.name],
      orderBy: 'updated_at DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _hydrate(rows.first);
  }

  Future<JournalEntry?> latestEntry() async {
    final db = await database;
    final rows = await db.query(
      'journal_entries',
      orderBy: 'updated_at DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _hydrate(rows.first);
  }

  Future<JournalEntry?> entryById(String id) async {
    final db = await database;
    final rows = await db.query(
      'journal_entries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _hydrate(rows.first);
  }

  Future<List<JournalEntry>> archivePage({
    ArchiveCursor? cursor,
    int limit = 30,
  }) async {
    final db = await database;
    final where = StringBuffer('status = ? AND closed_at IS NOT NULL');
    final args = <Object?>[EntryStatus.closed.name];
    if (cursor != null) {
      where.write(' AND (closed_at < ? OR (closed_at = ? AND id < ?))');
      final timestamp = cursor.closedAt.toIso8601String();
      args.addAll([timestamp, timestamp, cursor.entryId]);
    }
    final rows = await db.query(
      'journal_entries',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'closed_at DESC, id DESC',
      limit: limit,
    );
    return Future.wait(rows.map(_hydrate));
  }

  Future<List<JournalEntry>> closedEntriesBetween(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    final rows = await db.query(
      'journal_entries',
      where: 'status = ? AND closed_at >= ? AND closed_at < ?',
      whereArgs: [
        EntryStatus.closed.name,
        start.toUtc().toIso8601String(),
        end.toUtc().toIso8601String(),
      ],
      orderBy: 'closed_at DESC, id DESC',
    );
    return Future.wait(rows.map(_hydrate));
  }

  Future<List<JournalEntry>> allEntries() async {
    final db = await database;
    final rows = await db.query(
      'journal_entries',
      orderBy: 'updated_at DESC, id DESC',
    );
    return Future.wait(rows.map(_hydrate));
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

  Future<List<DailyCheckIn>> checkInsBetween(
    String startDateKey,
    String endDateKey,
  ) async {
    final db = await database;
    final rows = await db.query(
      'daily_checkins',
      where: 'date_key >= ? AND date_key <= ?',
      whereArgs: [startDateKey, endDateKey],
      orderBy: 'date_key ASC',
    );
    return rows.map(DailyCheckIn.fromMap).toList();
  }

  Future<void> saveCheckIn(DailyCheckIn checkIn) async {
    final db = await database;
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

  Future<JournalEntry> _hydrate(Map<String, Object?> row) async {
    final db = await database;
    final annotationRows = await db.query(
      'ai_annotations',
      where: 'entry_id = ?',
      whereArgs: [row['id']],
      orderBy: 'created_at ASC',
    );
    return JournalEntry.fromMap(
      row,
      annotations: annotationRows.map(AiAnnotation.fromMap).toList(),
    );
  }

  Future<void> saveEntry(JournalEntry entry) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'journal_entries',
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final annotation in entry.annotations) {
        await txn.insert(
          'ai_annotations',
          annotation.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> deleteEntry(String id) async {
    final db = await database;
    await db.delete('journal_entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    final pendingDatabase = _databaseFuture;
    _databaseFuture = null;
    if (pendingDatabase != null) {
      await (await pendingDatabase).close();
    }
  }
}
