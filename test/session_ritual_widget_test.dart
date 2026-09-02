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
  testWidgets('journal defaults to daily with an always-visible entry wheel', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester, now: DateTime(2026, 9, 1, 10));

    expect(find.byKey(const Key('full-page-journal')), findsOneWidget);
    expect(find.byKey(const Key('entry-wheel-panel')), findsOneWidget);
    expect(find.byKey(const Key('entry-wheel')), findsOneWidget);
    expect(find.byKey(const Key('entry-wheel-center')), findsOneWidget);
    expect(find.text('DAILY'), findsOneWidget);
    expect(find.byKey(const Key('journal-editor')), findsOneWidget);
    expect(find.byKey(const Key('gratitude-editor')), findsOneWidget);
    expect(find.byKey(const Key('entry-stack-toggle')), findsNothing);
    expect(find.byKey(const Key('entry-stack-expanded')), findsNothing);
    expect(find.byKey(const Key('new-entry')), findsOneWidget);
    expect(find.byKey(const Key('finish-journal')), findsOneWidget);
    expect(
      harness.container.read(journalControllerProvider).phase,
      AppPhase.journal,
    );
  });

  testWidgets('one tap focuses the gratitude field', (tester) async {
    await _pumpHarness(tester, now: DateTime(2026, 9, 1, 10));
    final gratitudeField = find.byKey(const Key('gratitude-editor'));
    final gratitudeEditable = find.descendant(
      of: gratitudeField,
      matching: find.byType(EditableText),
    );

    await tester.tap(gratitudeField);
    await tester.pump();

    expect(
      tester.widget<EditableText>(gratitudeEditable).focusNode.hasFocus,
      isTrue,
    );
  });

  testWidgets('entry wheel keeps the selected entry between faded neighbors', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester, now: DateTime(2026, 9, 1, 10));
    final controller = harness.container.read(
      journalControllerProvider.notifier,
    );
    await controller.addEntry(now: DateTime(2026, 9, 1, 12));
    controller.updateEntry(content: 'First additional entry.');
    await controller.saveCurrentEntry();
    await controller.addEntry(now: DateTime(2026, 9, 1, 14));
    controller.updateEntry(content: 'Second additional entry.');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('entry-wheel-previous')), findsOneWidget);
    expect(find.byKey(const Key('entry-wheel-center')), findsOneWidget);
    expect(find.byKey(const Key('entry-wheel-next')), findsOneWidget);
    expect(
      tester
          .widget<AnimatedOpacity>(find.byKey(const Key('entry-wheel-center')))
          .opacity,
      1,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const Key('entry-wheel-previous')),
          )
          .opacity,
      lessThan(1),
    );
    expect(
      tester
          .widget<AnimatedOpacity>(find.byKey(const Key('entry-wheel-next')))
          .opacity,
      lessThan(1),
    );

    await tester.tap(find.byKey(const Key('entry-wheel-previous')));
    await tester.pumpAndSettle();
    expect(controller.state.selectedEntry?.type, DayEntryType.daily);
    expect(find.byKey(const Key('gratitude-editor')), findsOneWidget);
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

  testWidgets('leaving an empty additional entry removes it', (tester) async {
    final harness = await _pumpHarness(tester, now: DateTime(2026, 9, 1, 10));
    await tester.tap(find.byKey(const Key('new-entry')));
    await tester.pumpAndSettle();
    expect(
      harness.container.read(journalControllerProvider).entries,
      hasLength(2),
    );

    await tester.fling(
      find.byKey(const Key('entry-wheel')),
      const Offset(0, 100),
      900,
    );
    await tester.pumpAndSettle();

    final state = harness.container.read(journalControllerProvider);
    expect(state.entries, hasLength(1));
    expect(state.selectedEntry?.type, DayEntryType.daily);
  });

  testWidgets('keyboard, wheel, and touch snap through the entry wheel', (
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

    harness.database.saveDayEntryCallCount = 0;
    final wheelCenter = tester.getCenter(find.byKey(const Key('entry-wheel')));
    final mouse = TestPointer(7, PointerDeviceKind.mouse);
    tester.binding.handlePointerEvent(mouse.hover(wheelCenter));
    tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, 58)));
    await tester.pumpAndSettle();
    expect(
      harness.container.read(journalControllerProvider).selectedEntry?.type,
      DayEntryType.additional,
    );
    expect(harness.database.saveDayEntryCallCount, 1);

    await tester.fling(
      find.byKey(const Key('entry-wheel')),
      const Offset(0, 100),
      900,
    );
    await tester.pumpAndSettle();
    expect(
      harness.container.read(journalControllerProvider).selectedEntry?.type,
      DayEntryType.daily,
    );
  });

  testWidgets('small wheel deltas accumulate and large deltas cross entries', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester, now: DateTime(2026, 9, 1, 10));
    final controller = harness.container.read(
      journalControllerProvider.notifier,
    );
    for (var index = 0; index < 4; index++) {
      await controller.addEntry(now: DateTime(2026, 9, 1, 11 + index));
      controller.updateEntry(content: 'Additional entry $index');
      await controller.saveCurrentEntry();
    }
    final dailyId = controller.state.dailyEntry!.id;
    await controller.selectEntry(dailyId);
    await tester.pumpAndSettle();

    final wheelCenter = tester.getCenter(find.byKey(const Key('entry-wheel')));
    final mouse = TestPointer(8, PointerDeviceKind.mouse);
    tester.binding.handlePointerEvent(mouse.hover(wheelCenter));
    harness.database.saveDayEntryCallCount = 0;
    for (var index = 0; index < 3; index++) {
      tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, 8)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    expect(controller.state.selectedEntryId, isNot(dailyId));
    expect(harness.database.saveDayEntryCallCount, 1);

    await controller.selectEntry(dailyId);
    await tester.pumpAndSettle();
    harness.database.saveDayEntryCallCount = 0;
    tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, 170)));
    await tester.pumpAndSettle();

    expect(controller.state.selectedEntryId, controller.state.entries.last.id);
    expect(harness.database.saveDayEntryCallCount, 1);
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
    expect(find.byKey(const Key('binder-rail')), findsOneWidget);
    expect(find.byKey(const Key('binder-pages')), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<BinderZoom>>(
            find.byKey(const Key('binder-zoom')),
          )
          .showSelectedIcon,
      isFalse,
    );

    await tester.tap(find.text('Weeks'));
    await tester.pump();
    expect(find.byKey(const Key('binder-zoom-transition')), findsOneWidget);
    expect(find.byKey(const Key('binder-pages')), findsNWidgets(2));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('binder-pages')), findsOneWidget);
  });

  testWidgets('binder wheel and keyboard navigation cross multiple days', (
    tester,
  ) async {
    final database = FakeDatabaseService();
    final now = DateTime(2026, 9, 1, 20);
    await _seedCompletedDays(database, now, 12);
    final harness = await _pumpHarness(tester, database: database, now: now);

    final listener = tester.widget<Listener>(
      find.byKey(const Key('binder-rail')),
    );
    listener.onPointerSignal!(
      const PointerScrollEvent(scrollDelta: Offset(0, 120)),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    expect(
      harness.container.read(binderControllerProvider).selectedDateKey,
      localDateKey(now.subtract(const Duration(days: 5))),
    );

    final anchor = harness.container
        .read(binderControllerProvider)
        .selectedDateKey;
    await tester.tap(find.text('Weeks'));
    await tester.pumpAndSettle();
    expect(
      harness.container.read(binderControllerProvider).selectedDateKey,
      anchor,
    );
    await tester.tap(find.text('Days'));
    await tester.pumpAndSettle();
    expect(
      harness.container.read(binderControllerProvider).selectedDateKey,
      anchor,
    );

    final dayListener = tester.widget<Listener>(
      find.byKey(const Key('binder-rail')),
    );
    for (var index = 0; index < 3; index++) {
      dayListener.onPointerSignal!(
        const PointerScrollEvent(scrollDelta: Offset(0, 8)),
      );
    }
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    expect(
      harness.container.read(binderControllerProvider).selectedDateKey,
      localDateKey(now.subtract(const Duration(days: 6))),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(
      harness.container.read(binderControllerProvider).selectedDateKey,
      localDateKey(now.subtract(const Duration(days: 11))),
    );
  });

  testWidgets('binder strips and touch flings navigate recorded dates', (
    tester,
  ) async {
    final database = FakeDatabaseService();
    final now = DateTime(2026, 9, 1, 20);
    await _seedCompletedDays(database, now, 8);
    final harness = await _pumpHarness(tester, database: database, now: now);
    final secondDate = localDateKey(now.subtract(const Duration(days: 1)));

    await tester.tap(find.byKey(Key('binder-strip-$secondDate')));
    await tester.pumpAndSettle();
    expect(
      harness.container.read(binderControllerProvider).selectedDateKey,
      secondDate,
    );

    await tester.fling(
      find.byKey(const Key('binder-pages')),
      const Offset(-120, 0),
      900,
    );
    await tester.pumpAndSettle();
    final selected = harness.container
        .read(binderControllerProvider)
        .selectedDateKey!;
    expect(selected.compareTo(secondDate), lessThan(0));
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

Future<void> _seedCompletedDays(
  FakeDatabaseService database,
  DateTime newest,
  int count,
) async {
  for (var offset = 0; offset < count; offset++) {
    final date = newest.subtract(Duration(days: offset));
    final dateKey = localDateKey(date);
    await database.saveDayEntry(
      DayEntry.empty(
        dateKey: dateKey,
        type: DayEntryType.daily,
        now: date,
      ).copyWith(content: 'Journal day $offset'),
    );
    await database.saveCheckIn(
      DailyCheckIn.forDate(
        dateKey: dateKey,
        moodAngle: offset / count,
        moodIntensity: .6,
        now: date,
      ),
    );
  }
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
