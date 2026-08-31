import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/models/journal_entry.dart';
import 'package:sotto/providers/journal_providers.dart';
import 'package:sotto/services/ai_service.dart';
import 'package:sotto/services/database_service.dart';
import 'package:sotto/ui/editor_screen.dart';

import 'support/session_test_doubles.dart';

void main() {
  testWidgets('arrival supports accessible mood controls and begins writing', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);

    expect(find.byKey(const Key('mood-dial')), findsOneWidget);
    final toneSlider = tester.widget<Slider>(
      find.byKey(const Key('mood-tone-slider')),
    );
    toneSlider.onChanged!(.42);
    await tester.pump();
    await _pressButton(tester, find.byKey(const Key('begin-session')));
    await tester.pumpAndSettle();

    expect(
      harness.container.read(journalControllerProvider).phase,
      SessionPhase.writing,
    );
    expect(find.byKey(const Key('journal-editor')), findsOneWidget);
    expect(
      harness.container.read(journalControllerProvider).todayCheckIn,
      isNotNull,
    );
    expect(
      harness.container.read(journalControllerProvider).isLoading,
      isFalse,
    );
  });

  testWidgets('unfinished draft is offered on arrival', (tester) async {
    final database = _memoryDatabase();
    await database.saveEntry(
      JournalEntry.empty().copyWith(content: 'An unfinished thought.'),
    );
    await _pumpHarness(tester, database: database);

    expect(find.text('Continue previous session'), findsOneWidget);
    expect(find.text('3 words are waiting for you.'), findsOneWidget);
  });

  testWidgets('writing never triggers reflection until manual close', (
    tester,
  ) async {
    final reflection = _CountingReflectionService();
    final harness = await _pumpHarness(tester, reflection: reflection);
    await _pressButton(tester, find.byKey(const Key('begin-session')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('journal-editor')),
      'This is enough writing to have once triggered the old idle prompt.',
    );
    await tester.pump(const Duration(seconds: 12));

    expect(reflection.calls, 0);
    expect(find.byKey(const Key('reflection-reply')), findsNothing);

    await _pressButton(tester, find.byKey(const Key('close-session')));
    await tester.pumpAndSettle();

    expect(reflection.calls, 1);
    expect(find.byKey(const Key('reflection-reply')), findsOneWidget);
    expect(
      harness.container.read(journalControllerProvider).isReflecting,
      isFalse,
    );
  });

  testWidgets('failed reflection falls back and session can finish', (
    tester,
  ) async {
    final harness = await _pumpHarness(
      tester,
      reflection: _FailingReflectionService(),
    );
    await _pressButton(tester, find.byKey(const Key('begin-session')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('journal-editor')),
      'Today felt more difficult than I expected.',
    );
    await _pressButton(tester, find.byKey(const Key('close-session')));
    await tester.pumpAndSettle();

    expect(find.text('Local fallback reflection'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('reflection-reply')),
      'I can be gentler tomorrow.',
    );
    await _pressButton(tester, find.byKey(const Key('finish-session')));
    await tester.pumpAndSettle();

    expect(find.text('Your days'), findsOneWidget);
    expect(
      harness.container.read(journalControllerProvider).phase,
      SessionPhase.archive,
    );
  });

  testWidgets('archive zoom changes while preserving scroll context', (
    tester,
  ) async {
    final database = _memoryDatabase();
    final now = DateTime.utc(2026, 8, 31, 12);
    for (var index = 0; index < 36; index++) {
      final closedAt = now.subtract(Duration(days: index));
      await database.saveEntry(
        JournalEntry.empty(now: closedAt).copyWith(
          content: 'A closed journal entry number $index with a few words.',
          status: EntryStatus.closed,
          closedAt: closedAt,
        ),
      );
    }
    final harness = await _pumpHarness(tester, database: database);
    await _tapVisible(tester, find.byKey(const Key('arrival-archive')));
    await tester.pumpAndSettle();

    final scrollable = find.byType(CustomScrollView);
    await tester.drag(scrollable, const Offset(0, -700));
    await tester.pumpAndSettle();
    final beforePosition = tester
        .state<ScrollableState>(
          find.descendant(of: scrollable, matching: find.byType(Scrollable)),
        )
        .position;
    final beforeProgress =
        beforePosition.pixels / beforePosition.maxScrollExtent;

    await _tapVisible(tester, find.text('Weeks'));
    await tester.pumpAndSettle();
    final afterPosition = tester
        .state<ScrollableState>(
          find.descendant(of: scrollable, matching: find.byType(Scrollable)),
        )
        .position;
    final afterProgress = afterPosition.pixels / afterPosition.maxScrollExtent;

    expect(afterPosition.pixels, greaterThan(0));
    expect((afterProgress - beforeProgress).abs(), lessThan(.02));
    expect(
      harness.container.read(archiveControllerProvider).zoom,
      ArchiveZoom.weeks,
    );
  });
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

Future<void> _pressButton(WidgetTester tester, Finder finder) async {
  final button = tester.widget<ButtonStyleButton>(finder);
  expect(button.onPressed, isNotNull);
  button.onPressed!();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

DatabaseService _memoryDatabase() => FakeDatabaseService();

Future<_Harness> _pumpHarness(
  WidgetTester tester, {
  DatabaseService? database,
  ReflectionService? reflection,
}) async {
  final db = database ?? _memoryDatabase();
  final container = ProviderContainer(
    overrides: [
      databaseServiceProvider.overrideWithValue(db),
      reflectionServiceProvider.overrideWithValue(
        reflection ?? _CountingReflectionService(),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: EditorScreen()),
    ),
  );
  await tester.pump();
  await container.read(journalControllerProvider.notifier).initialize();
  await tester.pumpAndSettle();
  final harness = _Harness(container, db);
  addTearDown(harness.dispose);
  return harness;
}

class _Harness {
  _Harness(this.container, this.database);
  final ProviderContainer container;
  final DatabaseService database;
  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
    await database.close();
  }
}

class _CountingReflectionService implements ReflectionService {
  int calls = 0;

  @override
  Future<ReflectionResult> reflectOn(String text) async {
    calls++;
    return const ReflectionResult(
      question: 'What deserves more of your attention?',
      isDemo: false,
    );
  }
}

class _FailingReflectionService implements ReflectionService {
  @override
  Future<ReflectionResult> reflectOn(String text) =>
      Future.error(StateError('local model unavailable'));
}
