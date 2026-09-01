import 'dart:async';
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

class _BinderScreenState extends ConsumerState<BinderScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motionController;
  Animation<double>? _railAnimation;
  Timer? _snapTimer;
  List<_BinderItem> _currentItems = const [];
  double _railPosition = 0;
  int _selectedIndex = 0;
  bool _scaleHandled = false;
  bool _initialAnchorSynced = false;
  String? _pendingZoomAnchor;

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController(vsync: this)
      ..addListener(() {
        final animation = _railAnimation;
        if (animation == null) return;
        setState(() => _railPosition = animation.value);
        _commitNearest(_currentItems);
      });
    Future.microtask(() {
      final anchor = ref.read(journalControllerProvider).selectedDateKey;
      ref
          .read(binderControllerProvider.notifier)
          .refresh(anchorDateKey: anchor);
    });
  }

  @override
  void dispose() {
    _snapTimer?.cancel();
    _motionController.dispose();
    super.dispose();
  }

  void _changeZoom(BinderZoom zoom) {
    if (zoom == ref.read(binderControllerProvider).zoom) return;
    _pendingZoomAnchor = ref.read(binderControllerProvider).selectedDateKey;
    ref.read(binderControllerProvider.notifier).setZoom(zoom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final items = _itemsFor(ref.read(binderControllerProvider));
      final anchor = _pendingZoomAnchor;
      final index = items.indexWhere(
        (item) => item.days.any((day) => day.day.dateKey == anchor),
      );
      _pendingZoomAnchor = null;
      _jumpToIndex(index < 0 ? 0 : index, items, commit: false);
      if (anchor != null &&
          index >= 0 &&
          items[index].days.any((day) => day.day.dateKey == anchor)) {
        ref.read(binderControllerProvider.notifier).selectDate(anchor);
      }
    });
  }

  void _zoomBy(int delta) {
    final state = ref.read(binderControllerProvider);
    final index = BinderZoom.values.indexOf(state.zoom);
    final next = (index + delta).clamp(0, BinderZoom.values.length - 1);
    if (next != index) _changeZoom(BinderZoom.values[next]);
  }

  void _jumpToIndex(int index, List<_BinderItem> items, {bool commit = true}) {
    if (items.isEmpty) return;
    _motionController.stop();
    _snapTimer?.cancel();
    final target = index.clamp(0, items.length - 1);
    setState(() {
      _railPosition = target.toDouble();
      _selectedIndex = target;
    });
    if (commit) _commitIndex(target, items);
  }

  void _moveBy(double amount, List<_BinderItem> items) {
    if (items.isEmpty || amount == 0) return;
    _motionController.stop();
    setState(() {
      _railPosition = (_railPosition + amount).clamp(
        0.0,
        math.max(0, items.length - 1).toDouble(),
      );
    });
    _commitNearest(items);
  }

  void _scheduleSnap(List<_BinderItem> items) {
    _snapTimer?.cancel();
    _snapTimer = Timer(
      const Duration(milliseconds: 110),
      () => _animateToIndex(_railPosition.round(), items),
    );
  }

  void _snapWithVelocity(double velocity, List<_BinderItem> items) {
    final projected = _railPosition - velocity / 360;
    _animateToIndex(projected.round(), items);
  }

  void _animateToIndex(int index, List<_BinderItem> items) {
    if (!mounted || items.isEmpty) return;
    _snapTimer?.cancel();
    final target = index.clamp(0, items.length - 1).toDouble();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion || (target - _railPosition).abs() < .01) {
      _jumpToIndex(target.round(), items);
      return;
    }
    final distance = (target - _railPosition).abs();
    _motionController.duration = Duration(
      milliseconds: (170 + distance * 34).round().clamp(170, 430),
    );
    _railAnimation = Tween<double>(begin: _railPosition, end: target).animate(
      CurvedAnimation(parent: _motionController, curve: Curves.easeOutCubic),
    );
    _motionController.forward(from: 0);
  }

  void _commitNearest(List<_BinderItem> items) {
    if (items.isEmpty) return;
    final index = _railPosition.round().clamp(0, items.length - 1);
    final selectedDate = ref.read(binderControllerProvider).selectedDateKey;
    if (index == _selectedIndex && selectedDate == items[index].anchorDateKey) {
      return;
    }
    _selectedIndex = index;
    _commitIndex(index, items);
  }

  void _commitIndex(int index, List<_BinderItem> items) {
    if (items.isEmpty) return;
    final target = index.clamp(0, items.length - 1);
    ref
        .read(binderControllerProvider.notifier)
        .selectDate(items[target].anchorDateKey);
    if (target >= items.length - 4) {
      ref.read(binderControllerProvider.notifier).loadMore();
    }
  }

  void _moveKeyboard(int delta) {
    _animateToIndex(_selectedIndex + delta, _currentItems);
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
    _currentItems = items;
    if (items.isNotEmpty && !_initialAnchorSynced) {
      _initialAnchorSynced = true;
      final anchor = binder.selectedDateKey;
      final anchorIndex = items.indexWhere(
        (item) => item.days.any((day) => day.day.dateKey == anchor),
      );
      if (anchorIndex > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _jumpToIndex(anchorIndex, items);
        });
      }
    }
    if (items.isNotEmpty &&
        _selectedIndex >= items.length &&
        _pendingZoomAnchor == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToIndex(items.length - 1, items);
      });
    }
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
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
          _moveKeyboard(1),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
          _moveKeyboard(-1),
      const SingleActivator(LogicalKeyboardKey.pageDown): () =>
          _moveKeyboard(5),
      const SingleActivator(LogicalKeyboardKey.pageUp): () => _moveKeyboard(-5),
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
                  child: items.isEmpty && !binder.isLoading
                      ? const Center(
                          child: Text(
                            'Your first recorded day will appear here.',
                            style: TextStyle(fontStyle: FontStyle.italic),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 600;
                            final pitch = compact ? 14.0 : 24.0;
                            return Listener(
                              key: const Key('binder-rail'),
                              onPointerSignal: (event) {
                                if (event is! PointerScrollEvent) return;
                                final delta =
                                    event.scrollDelta.dx.abs() >
                                        event.scrollDelta.dy.abs()
                                    ? event.scrollDelta.dx
                                    : event.scrollDelta.dy;
                                _moveBy(delta / pitch, items);
                                _scheduleSnap(items);
                              },
                              onPointerPanZoomStart: (_) {
                                _motionController.stop();
                                _scaleHandled = false;
                              },
                              onPointerPanZoomUpdate: (event) {
                                if (!_scaleHandled && event.scale > 1.12) {
                                  _scaleHandled = true;
                                  _zoomBy(-1);
                                  return;
                                }
                                if (!_scaleHandled && event.scale < .88) {
                                  _scaleHandled = true;
                                  _zoomBy(1);
                                  return;
                                }
                                if (!_scaleHandled) {
                                  final delta =
                                      event.panDelta.dx.abs() >
                                          event.panDelta.dy.abs()
                                      ? -event.panDelta.dx
                                      : event.panDelta.dy;
                                  _moveBy(delta / pitch, items);
                                }
                              },
                              onPointerPanZoomEnd: (_) =>
                                  _animateToIndex(_railPosition.round(), items),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onScaleStart: (_) {
                                  _motionController.stop();
                                  _scaleHandled = false;
                                },
                                onScaleUpdate: (details) {
                                  if (details.pointerCount > 1) {
                                    if (!_scaleHandled &&
                                        details.scale > 1.12) {
                                      _scaleHandled = true;
                                      _zoomBy(-1);
                                    } else if (!_scaleHandled &&
                                        details.scale < .88) {
                                      _scaleHandled = true;
                                      _zoomBy(1);
                                    }
                                    return;
                                  }
                                  if (!_scaleHandled) {
                                    _moveBy(
                                      -details.focalPointDelta.dx / pitch,
                                      items,
                                    );
                                  }
                                },
                                onScaleEnd: (details) {
                                  if (!_scaleHandled) {
                                    _snapWithVelocity(
                                      details.velocity.pixelsPerSecond.dx,
                                      items,
                                    );
                                  }
                                },
                                child: _BinderRail(
                                  key: const Key('binder-pages'),
                                  items: items,
                                  zoom: binder.zoom,
                                  position: _railPosition,
                                  selectedIndex: _selectedIndex.clamp(
                                    0,
                                    items.length - 1,
                                  ),
                                  pitch: pitch,
                                  compact: compact,
                                  onSelect: (index) =>
                                      _animateToIndex(index, items),
                                ),
                              ),
                            );
                          },
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

class _BinderRail extends StatelessWidget {
  const _BinderRail({
    required this.items,
    required this.zoom,
    required this.position,
    required this.selectedIndex,
    required this.pitch,
    required this.compact,
    required this.onSelect,
    super.key,
  });

  final List<_BinderItem> items;
  final BinderZoom zoom;
  final double position;
  final int selectedIndex;
  final double pitch;
  final bool compact;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final previewWidth = constraints.maxWidth * (compact ? .84 : .72);
      final previewLeft = (constraints.maxWidth - previewWidth) / 2;
      final previewRight = previewLeft + previewWidth;
      final visibleSlots = ((previewLeft / pitch).ceil() + 2).clamp(3, 9);
      final strips = <Widget>[];
      for (var index = 0; index < items.length; index++) {
        final relative = index - position;
        final distance = relative.abs();
        if (distance < .48 || distance > visibleSlots) continue;
        final older = relative > 0;
        final left = older
            ? previewLeft - distance * pitch - 22
            : previewRight + distance * pitch - 22;
        strips.add(
          Positioned(
            left: left,
            top: 18 + math.min(distance, 6) * 5,
            bottom: 30 + math.min(distance, 6) * 5,
            width: 44,
            child: _PaperEdge(
              item: items[index],
              opacity: (1 - distance * .075).clamp(.32, .88),
              onPressed: () => onSelect(index),
            ),
          ),
        );
      }
      return Stack(
        clipBehavior: Clip.none,
        children: [
          ...strips,
          Positioned(
            left: previewLeft,
            width: previewWidth,
            top: 0,
            bottom: 0,
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(.018, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _BinderSheet(
                key: ValueKey(
                  '${zoom.name}-${items[selectedIndex].anchorDateKey}',
                ),
                item: items[selectedIndex],
                zoom: zoom,
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _PaperEdge extends StatelessWidget {
  const _PaperEdge({
    required this.item,
    required this.opacity,
    required this.onPressed,
  });

  final _BinderItem item;
  final double opacity;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final mood = _averageMood(item.days);
    final accent = mood == null
        ? const Color(0xFFB8B8AD)
        : MoodPalette.colorFor(mood.$1, mood.$2);
    return Semantics(
      button: true,
      label: 'Open ${item.label}',
      child: Tooltip(
        message: item.label,
        child: InkWell(
          key: Key('binder-strip-${item.anchorDateKey}'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(11),
          child: Center(
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFCF5),
                  borderRadius: BorderRadius.circular(9),
                  border: Border(top: BorderSide(color: accent, width: 5)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x21000000),
                      blurRadius: 9,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
  const _BinderSheet({required this.item, required this.zoom, super.key});
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      excerpt.isEmpty ? 'A quiet page.' : excerpt,
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
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
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
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
