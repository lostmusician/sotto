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

  final DatabaseFactory? _injectedFactory;
  final String? _injectedPath;
  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final factory = _injectedFactory ?? _platformFactory();
    final path = _injectedPath ?? await _defaultPath();
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE journal_entries (id TEXT PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, target_word_count INTEGER NOT NULL DEFAULT 500)',
          );
          await db.execute(
            'CREATE TABLE ai_annotations (id TEXT PRIMARY KEY, entry_id TEXT NOT NULL, question TEXT NOT NULL, anchor_offset INTEGER NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(entry_id) REFERENCES journal_entries(id) ON DELETE CASCADE)',
          );
          await db.execute(
            'CREATE INDEX annotations_entry_id ON ai_annotations(entry_id, created_at)',
          );
        },
      ),
    );
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

  Future<JournalEntry?> latestEntry() async {
    final db = await database;
    final rows = await db.query(
      'journal_entries',
      orderBy: 'updated_at DESC',
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

  Future<List<JournalEntry>> allEntries() async {
    final db = await database;
    final rows = await db.query('journal_entries', orderBy: 'updated_at DESC');
    return Future.wait(rows.map(_hydrate));
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
    await _database?.close();
    _database = null;
  }
}
