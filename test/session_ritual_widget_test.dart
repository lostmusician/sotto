import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/models/journal_entry.dart';
import 'package:sotto/providers/journal_providers.dart';
import 'package:sotto/ui/editor_screen.dart';

import 'support/session_test_doubles.dart';

void main() {
  testWidgets('journal defaults to the daily entry with gratitude footer', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester, now: DateTime(2026, 9, 1, 10));

    expect(find.byKey(const Key('entry-stack')), findsOneWidget);
    expect(find.text('DAILY'), findsOneWidget);
    expect(find.byKey(const Key('journal-editor')), findsOneWidget);
    expect(find.byKey(const Key('gratitude-editor')), findsOneWidget);
    expect(
      harness.container.read(journalControllerProvider).phase,
      AppPhase.journal,
    );
  });

  testWidgets('new entry is separate and does not show gratitude', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester, now: DateTime(2026, 9, 1, 10));
    await tester.tap(find.byKey(const Key('new-entry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gratitude-editor')), findsNothing);
    await tester.enterText(find.byKey(const Key('entry-title')), 'Afternoon');
    await tester.enterText(
      find.byKey(const Key('journal-editor')),
      'A second thought.',
    );
    await tester.pump(const Duration(milliseconds: 750));

    final state = harness.container.read(journalControllerProvider);
    expect(state.entries, hasLength(2));
    expect(state.selectedEntry?.type, DayEntryType.additional);
  });

  testWidgets('keyboard, wheel, and touch move through the entry stack', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester, now: DateTime(2026, 9, 1, 10));
    await harness.container.read(journalControllerProvider.notifier).addEntry();
    harness.container
        .read(journalControllerProvider.notifier)
        .updateEntry(content: 'Keep this additional entry.');
    await tester.pumpAndSettle();
    expect(
      harness.container.read(journalControllerProvider).selectedEntry?.type,
      DayEntryType.additional,
    );

    await tester.tap(find.byKey(const Key('journal-editor')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(
      harness.container.read(journalControllerProvider).selectedEntry?.type,
      DayEntryType.daily,
    );

    final stackListener = tester.widget<Listener>(
      find.byKey(const Key('entry-stack-wheel')),
    );
    stackListener.onPointerSignal!(
      const PointerScrollEvent(scrollDelta: Offset(0, 24)),
    );
    await tester.pumpAndSettle();
    expect(
      harness.container.read(journalControllerProvider).selectedEntry?.type,
      DayEntryType.additional,
    );

    await tester.drag(
      find.byKey(const Key('entry-stack')),
      const Offset(0, 100),
    );
    await tester.pumpAndSettle();
    expect(
      harness.container.read(journalControllerProvider).selectedEntry?.type,
      DayEntryType.daily,
    );
  });

  testWidgets('completed journal before evening shows binder mood reminder', (
    tester,
  ) async {
    final database = FakeDatabaseService();
    await database.saveDayEntry(
      DayEntry.empty(
        dateKey: '2026-09-01',
        type: DayEntryType.daily,
      ).copyWith(content: 'Already written.'),
    );
    await _pumpHarness(
      tester,
      database: database,
      now: DateTime(2026, 9, 1, 12),
    );

    expect(find.byKey(const Key('mood-reminder')), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
  });

  testWidgets('binder exposes journal, additional entry, and mood actions', (
    tester,
  ) async {
    final database = FakeDatabaseService();
    const dateKey = '2026-09-01';
    await database.saveDayEntry(
      DayEntry.empty(
        dateKey: dateKey,
        type: DayEntryType.daily,
      ).copyWith(content: 'A finished day.'),
    );
    await database.saveCheckIn(
      DailyCheckIn.forDate(dateKey: dateKey, moodAngle: .2, moodIntensity: .6),
    );
    final harness = await _pumpHarness(
      tester,
      database: database,
      now: DateTime(2026, 9, 1, 20),
    );

    expect(find.byKey(const Key('edit-journal')), findsOneWidget);
    expect(find.byKey(const Key('add-entry')), findsOneWidget);
    expect(find.byKey(const Key('edit-mood')), findsOneWidget);

    await tester.tap(find.text('Weeks'));
    await tester.pumpAndSettle();
    expect(
      harness.container.read(binderControllerProvider).zoom,
      BinderZoom.weeks,
    );

    final binderCenter = tester.getCenter(
      find.byKey(const Key('binder-pages')),
    );
    final firstFinger = await tester.startGesture(
      binderCenter - const Offset(30, 0),
      pointer: 1,
    );
    final secondFinger = await tester.startGesture(
      binderCenter + const Offset(30, 0),
      pointer: 2,
    );
    await firstFinger.moveTo(binderCenter - const Offset(80, 0));
    await secondFinger.moveTo(binderCenter + const Offset(80, 0));
    await firstFinger.up();
    await secondFinger.up();
    await tester.pumpAndSettle();
    expect(
      harness.container.read(binderControllerProvider).zoom,
      BinderZoom.days,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(
      harness.container.read(binderControllerProvider).zoom,
      BinderZoom.weeks,
    );
  });

  testWidgets('evening launch opens mood and continues to journal', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester, now: DateTime(2026, 9, 1, 18));

    expect(find.byKey(const Key('mood-dial')), findsOneWidget);
    final slider = tester.widget<Slider>(
      find.byKey(const Key('mood-tone-slider')),
    );
    slider.onChanged!(.5);
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('finish-mood')),
    );
    button.onPressed!();
    await tester.pumpAndSettle();

    expect(
      harness.container.read(journalControllerProvider).phase,
      AppPhase.journal,
    );
  });
}

Future<_Harness> _pumpHarness(
  WidgetTester tester, {
  required DateTime now,
  FakeDatabaseService? database,
}) async {
  final db = database ?? FakeDatabaseService();
  final container = ProviderContainer(
    overrides: [databaseServiceProvider.overrideWithValue(db)],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: EditorScreen()),
    ),
  );
  await tester.pump();
  await container.read(journalControllerProvider.notifier).initialize(now: now);
  await tester.pumpAndSettle();
  final harness = _Harness(container, db);
  addTearDown(harness.dispose);
  return harness;
}

class _Harness {
  _Harness(this.container, this.database);
  final ProviderContainer container;
  final FakeDatabaseService database;
  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
    await database.close();
  }
}
