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

  test('persists an entry and its reflection annotations', () async {
    final entry = JournalEntry.empty().copyWith(content: 'A private thought.');
    final annotation = AiAnnotation.create(
      entryId: entry.id,
      question: 'What matters beneath this thought?',
      anchorOffset: entry.content.length,
    );
    await database.saveEntry(entry.copyWith(annotations: [annotation]));
    final loaded = await database.entryById(entry.id);
    expect(loaded?.content, 'A private thought.');
    expect(loaded?.annotations.single.question, annotation.question);
  });
}
