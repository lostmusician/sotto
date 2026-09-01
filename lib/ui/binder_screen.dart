import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../providers/journal_providers.dart';
import 'mood_dial.dart';

class BinderScreen extends ConsumerStatefulWidget {
  const BinderScreen({super.key});

  @override
  ConsumerState<BinderScreen> createState() => _BinderScreenState();
}

class _BinderScreenState extends ConsumerState<BinderScreen> {
  final _pageController = PageController(viewportFraction: .72);
  bool _scaleHandled = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final anchor = ref.read(journalControllerProvider).selectedDateKey;
      ref
          .read(binderControllerProvider.notifier)
          .refresh(anchorDateKey: anchor);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _changeZoom(BinderZoom zoom) {
    final anchor = ref.read(binderControllerProvider).selectedDateKey;
    ref.read(binderControllerProvider.notifier).setZoom(zoom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      final items = _itemsFor(ref.read(binderControllerProvider));
      final index = items.indexWhere(
        (item) => item.days.any((day) => day.day.dateKey == anchor),
      );
      _pageController.jumpToPage(index < 0 ? 0 : index);
    });
  }

  void _zoomBy(int delta) {
    final state = ref.read(binderControllerProvider);
    final index = BinderZoom.values.indexOf(state.zoom);
    final next = (index + delta).clamp(0, BinderZoom.values.length - 1);
    if (next != index) _changeZoom(BinderZoom.values[next]);
  }

  Future<void> _changeEveningTime() async {
    final preference = ref.read(journalControllerProvider).eveningPreference;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: preference.hour, minute: preference.minute),
      helpText: 'When does evening begin?',
    );
    if (selected == null) return;
    await ref
        .read(journalControllerProvider.notifier)
        .updateEveningPreference(selected.hour * 60 + selected.minute);
  }

  @override
  Widget build(BuildContext context) {
    final binder = ref.watch(binderControllerProvider);
    final app = ref.watch(journalControllerProvider);
    final items = _itemsFor(binder);
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.equal, meta: true): () =>
          _zoomBy(-1),
      const SingleActivator(LogicalKeyboardKey.add, meta: true): () =>
          _zoomBy(-1),
      const SingleActivator(LogicalKeyboardKey.minus, meta: true): () =>
          _zoomBy(1),
      const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
          _zoomBy(-1),
      const SingleActivator(LogicalKeyboardKey.add, control: true): () =>
          _zoomBy(-1),
      const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
          _zoomBy(1),
    };

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: const Color(0xFFF1EEE6),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 14, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Your days',
                          style: TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('binder-settings'),
                        tooltip: 'Evening settings',
                        onPressed: _changeEveningTime,
                        icon: const Icon(Icons.schedule_rounded),
                      ),
                    ],
                  ),
                ),
                if (app.showMoodReminder)
                  _MoodReminder(
                    onPressed: () async {
                      await ref
                          .read(journalControllerProvider.notifier)
                          .openMood(localDateKey(DateTime.now()));
                    },
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SegmentedButton<BinderZoom>(
                    key: const Key('binder-zoom'),
                    segments: const [
                      ButtonSegment(
                        value: BinderZoom.days,
                        label: Text('Days'),
                      ),
                      ButtonSegment(
                        value: BinderZoom.weeks,
                        label: Text('Weeks'),
                      ),
                      ButtonSegment(
                        value: BinderZoom.months,
                        label: Text('Months'),
                      ),
                    ],
                    selected: {binder.zoom},
                    onSelectionChanged: (value) => _changeZoom(value.first),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent &&
                          event.scrollDelta.dx.abs() >
                              event.scrollDelta.dy.abs() &&
                          _pageController.hasClients) {
                        final next = event.scrollDelta.dx > 0
                            ? _pageController.page!.round() + 1
                            : _pageController.page!.round() - 1;
                        _pageController.animateToPage(
                          next.clamp(0, math.max(0, items.length - 1)),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                    child: GestureDetector(
                      onScaleStart: (_) => _scaleHandled = false,
                      onScaleUpdate: (details) {
                        if (_scaleHandled) return;
                        if (details.scale > 1.12) {
                          _scaleHandled = true;
                          _zoomBy(-1);
                        } else if (details.scale < .88) {
                          _scaleHandled = true;
                          _zoomBy(1);
                        }
                      },
                      child: items.isEmpty && !binder.isLoading
                          ? const Center(
                              child: Text(
                                'Your first recorded day will appear here.',
                                style: TextStyle(fontStyle: FontStyle.italic),
                              ),
                            )
                          : PageView.builder(
                              key: const Key('binder-pages'),
                              controller: _pageController,
                              reverse: true,
                              itemCount: items.length,
                              onPageChanged: (index) {
                                final item = items[index];
                                ref
                                    .read(binderControllerProvider.notifier)
                                    .selectDate(item.anchorDateKey);
                                if (index >= items.length - 4) {
                                  ref
                                      .read(binderControllerProvider.notifier)
                                      .loadMore();
                                }
                              },
                              itemBuilder: (context, index) => AnimatedBuilder(
                                animation: _pageController,
                                builder: (context, child) {
                                  final page =
                                      _pageController.positions.length == 1 &&
                                          _pageController
                                              .position
                                              .hasContentDimensions
                                      ? _pageController.page ?? 0
                                      : 0.0;
                                  final distance = (page - index).abs();
                                  final scale = 1 - math.min(distance, 1) * .08;
                                  final opacity =
                                      1 - math.min(distance, 1) * .56;
                                  return Transform.scale(
                                    scale: scale,
                                    child: Opacity(
                                      opacity: opacity,
                                      child: child,
                                    ),
                                  );
                                },
                                child: _BinderSheet(
                                  item: items[index],
                                  zoom: binder.zoom,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                if (binder.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_BinderItem> _itemsFor(BinderState state) {
    if (state.zoom == BinderZoom.days) {
      return [
        for (final day in state.days)
          _BinderItem(label: _friendlyDate(day.day.dateKey), days: [day]),
      ];
    }
    final groups = <String, List<BinderDay>>{};
    for (final day in state.days) {
      final date = localDateFromKey(day.day.dateKey);
      final label = state.zoom == BinderZoom.weeks
          ? _weekLabel(date)
          : '${_monthName(date.month)} ${date.year}';
      groups.putIfAbsent(label, () => []).add(day);
    }
    return [
      for (final group in groups.entries)
        _BinderItem(label: group.key, days: group.value),
    ];
  }
}

class _MoodReminder extends StatelessWidget {
  const _MoodReminder({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
    child: Material(
      color: const Color(0xFFE4DFC9),
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        key: const Key('mood-reminder'),
        title: const Text('Your mood can wait until this evening.'),
        trailing: TextButton(
          onPressed: onPressed,
          child: const Text('Add now'),
        ),
      ),
    ),
  );
}

class _BinderSheet extends ConsumerWidget {
  const _BinderSheet({required this.item, required this.zoom});
  final _BinderItem item;
  final BinderZoom zoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = item.days.first;
    final mood = _averageMood(item.days);
    final accent = mood == null
        ? const Color(0xFFB8B8AD)
        : MoodPalette.colorFor(mood.$1, mood.$2);
    final daily = primary.dailyEntry;
    final excerpt = daily?.content.trim() ?? '';
    final additionalCount = item.days.fold<int>(
      0,
      (sum, day) => sum + day.additionalEntries.length,
    );
    final gratitudeCount = item.days
        .where((day) => day.day.gratitude.trim().isNotEmpty)
        .length;
    return Semantics(
      label: '${item.label}, ${item.days.length} recorded days',
      child: Container(
        key: Key('binder-sheet-${item.anchorDateKey}'),
        margin: const EdgeInsets.fromLTRB(8, 18, 8, 30),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF5),
          borderRadius: BorderRadius.circular(28),
          border: Border(top: BorderSide(color: accent, width: 7)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item.label,
              style: const TextStyle(
                fontFamily: 'Georgia',
                fontSize: 27,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            if (zoom == BinderZoom.days) ...[
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        excerpt.isEmpty ? 'A quiet page.' : excerpt,
                        style: const TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 21,
                          height: 1.5,
                        ),
                      ),
                      if (primary.day.gratitude.trim().isNotEmpty) ...[
                        const SizedBox(height: 26),
                        const Text(
                          'GRATEFUL FOR',
                          style: TextStyle(fontSize: 11, letterSpacing: 1.1),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          primary.day.gratitude,
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ],
                      if (additionalCount > 0) ...[
                        const SizedBox(height: 24),
                        Text(
                          '$additionalCount additional ${additionalCount == 1 ? 'entry' : 'entries'}',
                        ),
                        const SizedBox(height: 6),
                        Text(
                          primary.additionalEntries
                              .map((entry) => _entryTime(entry.createdAt))
                              .join('  ·  '),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    key: const Key('edit-journal'),
                    onPressed: () => ref
                        .read(journalControllerProvider.notifier)
                        .openDay(primary.day.dateKey),
                    child: const Text('Edit journal'),
                  ),
                  TextButton(
                    key: const Key('add-entry'),
                    onPressed: () => ref
                        .read(journalControllerProvider.notifier)
                        .openDay(primary.day.dateKey, createAdditional: true),
                    child: const Text('Add entry'),
                  ),
                  TextButton(
                    key: const Key('edit-mood'),
                    onPressed: () => ref
                        .read(journalControllerProvider.notifier)
                        .openMood(primary.day.dateKey),
                    child: const Text('Edit mood'),
                  ),
                ],
              ),
            ] else ...[
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '${item.days.length} recorded ${item.days.length == 1 ? 'day' : 'days'}',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text('$additionalCount additional entries'),
                      const SizedBox(height: 8),
                      Text(
                        '$gratitudeCount with gratitude',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BinderItem {
  const _BinderItem({required this.label, required this.days});
  final String label;
  final List<BinderDay> days;
  String get anchorDateKey => days.first.day.dateKey;
}

(double, double)? _averageMood(List<BinderDay> days) {
  final moods = days
      .map((day) => day.checkIn)
      .whereType<DailyCheckIn>()
      .toList();
  if (moods.isEmpty) return null;
  final x = moods.fold<double>(
    0,
    (sum, mood) => sum + math.cos(mood.moodAngle * math.pi * 2),
  );
  final y = moods.fold<double>(
    0,
    (sum, mood) => sum + math.sin(mood.moodAngle * math.pi * 2),
  );
  return (
    ((math.atan2(y, x) / (math.pi * 2)) + 1) % 1,
    moods.fold<double>(0, (sum, mood) => sum + mood.moodIntensity) /
        moods.length,
  );
}

String _friendlyDate(String dateKey) {
  final date = localDateFromKey(dateKey);
  return '${_monthName(date.month)} ${date.day}, ${date.year}';
}

String _weekLabel(DateTime date) {
  final monday = date.subtract(Duration(days: date.weekday - DateTime.monday));
  return 'Week of ${_monthName(monday.month)} ${monday.day}';
}

String _entryTime(DateTime value) {
  final time = value.toLocal();
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
}

String _monthName(int month) => const [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][month - 1];
