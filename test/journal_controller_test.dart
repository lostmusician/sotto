import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/models/journal_entry.dart';
import 'package:sotto/providers/journal_providers.dart';
import 'package:sotto/services/ai_service.dart';
import 'package:sotto/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/session_test_doubles.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('runs the complete ritual through explicit transitions', () async {
    final database = DatabaseService(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final controller = JournalController(database, _FixedReflectionService());
    final now = DateTime(2026, 8, 31, 18);

    await controller.initialize(now: now);
    controller.updateMood(.4, .8, now: now);
    await controller.beginSession(now: now);
    controller.updateContent('Today I noticed I was rushing.');

    expect(controller.state.phase, SessionPhase.writing);
    await controller.requestClose();
    expect(controller.state.phase, SessionPhase.reflection);
    expect(
      controller.state.entry?.reflectionQuestion,
      'What asks you to slow down?',
    );

    controller.updateReflectionReply('I can leave more space.');
    await controller.finishSession(now: now.add(const Duration(minutes: 12)));

    expect(controller.state.phase, SessionPhase.archive);
    expect(controller.state.entry?.status, EntryStatus.closed);
    expect(controller.state.entry?.reflectionReply, 'I can leave more space.');
    await database.close();
  });

  test('invalid transitions do not create or lose an entry', () async {
    final database = DatabaseService(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final controller = JournalController(database, _FixedReflectionService());
    await controller.initialize();

    await controller.requestClose();
    await controller.finishSession();

    expect(controller.state.phase, SessionPhase.arrival);
    expect(controller.state.entry, isNull);
    await database.close();
  });

  test('restores unfinished draft on arrival', () async {
    final database = DatabaseService(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await database.saveEntry(
      JournalEntry.empty().copyWith(content: 'Still writing this.'),
    );
    final controller = JournalController(database, _FixedReflectionService());

    await controller.initialize();

    expect(controller.state.phase, SessionPhase.arrival);
    expect(controller.state.hasUnfinishedDraft, isTrue);
    expect(controller.state.entry?.content, 'Still writing this.');
    await database.close();
  });

  test(
    'reflection service failure falls back without blocking close',
    () async {
      final database = DatabaseService(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final controller = JournalController(
        database,
        _FailingReflectionService(),
      );
      await controller.initialize();
      await controller.beginSession();
      controller.updateContent('A difficult afternoon.');

      await controller.requestClose();

      expect(controller.state.phase, SessionPhase.reflection);
      expect(controller.state.isReflecting, isFalse);
      expect(controller.state.lastReflectionWasDemo, isTrue);
      expect(controller.state.entry?.reflectionQuestion, isNotEmpty);
      await database.close();
    },
  );

  test('reopening writing invalidates the prior reflection', () async {
    final database = DatabaseService(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final controller = JournalController(database, _FixedReflectionService());
    await controller.initialize();
    await controller.beginSession();
    controller.updateContent('A thought.');
    await controller.requestClose();

    await controller.reopenWriting();

    expect(controller.state.phase, SessionPhase.writing);
    expect(controller.state.entry?.reflectionQuestion, isNull);
    expect(controller.state.entry?.content, 'A thought.');
    await database.close();
  });

  test('closing cannot override navigation to the archive', () async {
    final database = _ControllableDatabaseService();
    final controller = JournalController(database, _FixedReflectionService());
    await controller.initialize();
    await controller.beginSession();
    controller.updateContent('A thought worth keeping.');
    database.pauseNextSave();

    final closing = controller.requestClose();
    await database.saveStarted;
    await controller.openArchive();
    database.releaseSave();
    await closing;

    expect(controller.state.phase, SessionPhase.archive);
    expect(controller.state.entry?.content, 'A thought worth keeping.');
  });

  test('opening the archive persists an edited arrival mood', () async {
    final database = FakeDatabaseService();
    final controller = JournalController(database, _FixedReflectionService());
    final now = DateTime(2026, 8, 31, 18);
    await controller.initialize(now: now);
    controller.updateMood(.84, .63, now: now);

    await controller.openArchive();

    final saved = database.checkIns[localDateKey(now)];
    expect(saved?.moodAngle, .84);
    expect(saved?.moodIntensity, .63);
  });
}

class _FixedReflectionService implements ReflectionService {
  @override
  Future<ReflectionResult> reflectOn(String text) async =>
      const ReflectionResult(
        question: 'What asks you to slow down?',
        isDemo: false,
      );
}

class _FailingReflectionService implements ReflectionService {
  @override
  Future<ReflectionResult> reflectOn(String text) =>
      Future.error(StateError('model unavailable'));
}

class _ControllableDatabaseService extends FakeDatabaseService {
  bool _pauseNext = false;
  late Completer<void> _saveStarted;
  late Completer<void> _saveRelease;

  Future<void> get saveStarted => _saveStarted.future;

  void pauseNextSave() {
    _pauseNext = true;
    _saveStarted = Completer<void>();
    _saveRelease = Completer<void>();
  }

  void releaseSave() => _saveRelease.complete();

  @override
  Future<void> saveEntry(JournalEntry entry) async {
    if (_pauseNext) {
      _pauseNext = false;
      _saveStarted.complete();
      await _saveRelease.future;
    }
    await super.saveEntry(entry);
  }
}
