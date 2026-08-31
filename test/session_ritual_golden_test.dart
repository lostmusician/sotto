import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/providers/journal_providers.dart';
import 'package:sotto/ui/editor_screen.dart';

import 'support/session_test_doubles.dart';

void main() {
  testWidgets('arrival desktop golden', (tester) async {
    final harness = await _pumpGolden(tester, size: const Size(1280, 800));

    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/session_arrival_desktop.png'),
    );
    await harness.dispose();
  });

  testWidgets('arrival phone golden', (tester) async {
    final harness = await _pumpGolden(tester, size: const Size(390, 844));

    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/session_arrival_phone.png'),
    );
    await harness.dispose();
  });

  testWidgets('writing narrow desktop golden', (tester) async {
    final harness = await _pumpGolden(tester, size: const Size(820, 700));
    await harness.controller.beginSession();
    harness.controller.updateContent(
      'There is a quiet kind of momentum in beginning before I feel ready.',
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/session_writing_narrow_desktop.png'),
    );
    await harness.dispose();
  });

  testWidgets('writing reduced motion golden', (tester) async {
    final harness = await _pumpGolden(
      tester,
      size: const Size(1000, 700),
      disableAnimations: true,
    );
    await harness.controller.beginSession();
    await tester.pump();

    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/session_writing_reduced_motion.png'),
    );
    await harness.dispose();
  });

  testWidgets('arrival large text golden', (tester) async {
    final harness = await _pumpGolden(
      tester,
      size: const Size(1200, 900),
      textScaler: const TextScaler.linear(1.6),
    );

    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/session_arrival_large_text.png'),
    );
    await harness.dispose();
  });

  testWidgets('reflection high contrast golden', (tester) async {
    final harness = await _pumpGolden(
      tester,
      size: const Size(1000, 800),
      highContrast: true,
    );
    await harness.controller.beginSession();
    harness.controller.updateContent(
      'I kept making room for everyone else and forgot to leave some for me.',
    );
    await harness.controller.requestClose();
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/session_reflection_high_contrast.png'),
    );
    await harness.dispose();
  });
}

Future<_GoldenHarness> _pumpGolden(
  WidgetTester tester, {
  required Size size,
  bool disableAnimations = false,
  bool highContrast = false,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final database = FakeDatabaseService();
  final container = ProviderContainer(
    overrides: [
      databaseServiceProvider.overrideWithValue(database),
      reflectionServiceProvider.overrideWithValue(
        const FixedReflectionService(
          question: 'Where could you make a little more room for yourself?',
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            devicePixelRatio: 1,
            disableAnimations: disableAnimations,
            highContrast: highContrast,
            textScaler: textScaler,
          ),
          child: const EditorScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  final controller = container.read(journalControllerProvider.notifier);
  await controller.initialize(now: DateTime(2026, 8, 31, 18));
  await tester.pumpAndSettle();
  return _GoldenHarness(container, database, controller);
}

class _GoldenHarness {
  const _GoldenHarness(this.container, this.database, this.controller);

  final ProviderContainer container;
  final FakeDatabaseService database;
  final JournalController controller;

  Future<void> dispose() async {
    container.dispose();
    await database.close();
  }
}
