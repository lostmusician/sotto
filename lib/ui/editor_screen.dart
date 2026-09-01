import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../providers/journal_providers.dart';
import 'binder_screen.dart';
import 'mood_dial.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen>
    with WidgetsBindingObserver {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _gratitudeController = TextEditingController();
  late final FocusNode _writingFocus;
  Timer? _entryDebounce;
  Timer? _gratitudeDebounce;
  Timer? _moodDebounce;
  String? _loadedEntryId;
  String? _loadedDateKey;

  @override
  void initState() {
    super.initState();
    _writingFocus = FocusNode(onKeyEvent: _handleWritingKey);
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(
      () => ref.read(journalControllerProvider.notifier).initialize(),
    );
  }

  KeyEventResult _handleWritingKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowDown => 1,
      _ => 0,
    };
    if (delta == 0) return KeyEventResult.ignored;
    final state = ref.read(journalControllerProvider);
    final index = state.entries.indexWhere(
      (entry) => entry.id == state.selectedEntryId,
    );
    final next = (index + delta).clamp(0, state.entries.length - 1);
    if (next != index) unawaited(_selectEntry(state.entries[next].id));
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entryDebounce?.cancel();
    _gratitudeDebounce?.cancel();
    _moodDebounce?.cancel();
    _titleController.dispose();
    _contentController.dispose();
    _gratitudeController.dispose();
    _writingFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final current = ref.read(journalControllerProvider);
    if (current.phase == AppPhase.binder) {
      ref.read(journalControllerProvider.notifier).initialize();
    }
  }

  void _syncControllers(JournalAppState state) {
    final entry = state.selectedEntry;
    if (entry != null && _loadedEntryId != entry.id) {
      _loadedEntryId = entry.id;
      _titleController.text = entry.title;
      _contentController.value = TextEditingValue(
        text: entry.content,
        selection: TextSelection.collapsed(offset: entry.content.length),
      );
    }
    if (state.day != null && _loadedDateKey != state.day!.dateKey) {
      _loadedDateKey = state.day!.dateKey;
      _gratitudeController.text = state.day!.gratitude;
    }
  }

  void _onEntryChanged() {
    final controller = ref.read(journalControllerProvider.notifier);
    controller.updateEntry(
      title: _titleController.text,
      content: _contentController.text,
    );
    _entryDebounce?.cancel();
    _entryDebounce = Timer(
      const Duration(milliseconds: 700),
      controller.saveCurrentEntry,
    );
  }

  void _onGratitudeChanged(String value) {
    final controller = ref.read(journalControllerProvider.notifier);
    controller.updateGratitude(value);
    _gratitudeDebounce?.cancel();
    _gratitudeDebounce = Timer(
      const Duration(milliseconds: 700),
      controller.saveGratitude,
    );
  }

  void _onMoodChanged(double angle, double intensity) {
    final controller = ref.read(journalControllerProvider.notifier);
    controller.updateMood(angle, intensity);
    _moodDebounce?.cancel();
    _moodDebounce = Timer(
      const Duration(milliseconds: 700),
      controller.saveMood,
    );
  }

  Future<void> _selectEntry(String entryId) async {
    _entryDebounce?.cancel();
    await ref.read(journalControllerProvider.notifier).selectEntry(entryId);
    if (mounted) _writingFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(journalControllerProvider);
    _syncControllers(state);
    return Material(
      color: Colors.transparent,
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 320),
        child: switch (state.phase) {
          AppPhase.loading => const _LoadingView(key: ValueKey('loading')),
          AppPhase.mood => _MoodView(
            key: const ValueKey('mood'),
            state: state,
            onChanged: _onMoodChanged,
            onFinish: () async {
              _moodDebounce?.cancel();
              await ref.read(journalControllerProvider.notifier).finishMood();
            },
            onBinder: ref.read(journalControllerProvider.notifier).openBinder,
          ),
          AppPhase.journal => _JournalView(
            key: const ValueKey('journal'),
            state: state,
            titleController: _titleController,
            contentController: _contentController,
            gratitudeController: _gratitudeController,
            writingFocus: _writingFocus,
            onEntryChanged: _onEntryChanged,
            onGratitudeChanged: _onGratitudeChanged,
            onSelectEntry: _selectEntry,
            onAddEntry: () async {
              _entryDebounce?.cancel();
              await ref.read(journalControllerProvider.notifier).addEntry();
              if (mounted) _writingFocus.requestFocus();
            },
            onFinish: () async {
              _entryDebounce?.cancel();
              _gratitudeDebounce?.cancel();
              await ref
                  .read(journalControllerProvider.notifier)
                  .finishEditing();
            },
          ),
          AppPhase.binder => const BinderScreen(key: ValueKey('binder')),
        },
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({super.key});

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFFF4F0E8),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _MoodView extends StatelessWidget {
  const _MoodView({
    required this.state,
    required this.onChanged,
    required this.onFinish,
    required this.onBinder,
    super.key,
  });

  final JournalAppState state;
  final void Function(double, double) onChanged;
  final Future<void> Function() onFinish;
  final Future<void> Function() onBinder;

  @override
  Widget build(BuildContext context) {
    final angle = state.checkIn?.moodAngle ?? .12;
    final intensity = state.checkIn?.moodIntensity ?? .55;
    final accent = MoodPalette.colorFor(angle, intensity);
    return ColoredBox(
      color: Color.lerp(const Color(0xFFF4F0E8), accent, .18)!,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 12,
              left: 14,
              child: IconButton(
                key: const Key('mood-binder'),
                tooltip: 'Open binder',
                onPressed: onBinder,
                icon: const Icon(Icons.menu_book_outlined),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    children: [
                      Text(
                        _friendlyDate(state.selectedDateKey),
                        style: const TextStyle(fontSize: 13, letterSpacing: 1),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'How did today feel?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 38,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 28),
                      MoodDial(
                        angle: angle,
                        intensity: intensity,
                        onChanged: onChanged,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('finish-mood'),
                        onPressed: onFinish,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 16,
                          ),
                        ),
                        child: const Text('Save mood'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalView extends StatelessWidget {
  const _JournalView({
    required this.state,
    required this.titleController,
    required this.contentController,
    required this.gratitudeController,
    required this.writingFocus,
    required this.onEntryChanged,
    required this.onGratitudeChanged,
    required this.onSelectEntry,
    required this.onAddEntry,
    required this.onFinish,
    super.key,
  });

  final JournalAppState state;
  final TextEditingController titleController;
  final TextEditingController contentController;
  final TextEditingController gratitudeController;
  final FocusNode writingFocus;
  final VoidCallback onEntryChanged;
  final ValueChanged<String> onGratitudeChanged;
  final Future<void> Function(String) onSelectEntry;
  final Future<void> Function() onAddEntry;
  final Future<void> Function() onFinish;

  void _moveSelection(int delta) {
    final index = state.entries.indexWhere(
      (entry) => entry.id == state.selectedEntryId,
    );
    final next = (index + delta).clamp(0, state.entries.length - 1);
    if (next != index) unawaited(onSelectEntry(state.entries[next].id));
  }

  @override
  Widget build(BuildContext context) {
    final selected = state.selectedEntry;
    if (selected == null) return const _LoadingView();
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
          _moveSelection(-1),
      const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
          _moveSelection(1),
    };
    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: const Color(0xFFF0ECE3),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _friendlyDate(state.selectedDateKey),
                          style: const TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: 23,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('finish-journal'),
                        onPressed: onFinish,
                        child: const Text('Done for now'),
                      ),
                    ],
                  ),
                ),
                _EntryStack(
                  entries: state.entries,
                  selectedEntryId: selected.id,
                  onSelected: onSelectEntry,
                  onAdd: onAddEntry,
                  onMove: _moveSelection,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 240),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: SingleChildScrollView(
                      key: ValueKey(selected.id),
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 780),
                          padding: const EdgeInsets.fromLTRB(34, 28, 34, 34),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFCF5),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x18000000),
                                blurRadius: 22,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                key: const Key('entry-title'),
                                controller: titleController,
                                onChanged: (_) => onEntryChanged(),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  hintText: selected.type == DayEntryType.daily
                                      ? 'Daily journal'
                                      : _entryTime(selected),
                                ),
                                style: const TextStyle(
                                  fontFamily: 'Georgia',
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Divider(),
                              TextField(
                                key: const Key('journal-editor'),
                                controller: contentController,
                                focusNode: writingFocus,
                                autofocus: true,
                                onChanged: (_) => onEntryChanged(),
                                minLines: 12,
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  hintText: 'Start where you are…',
                                ),
                                style: const TextStyle(
                                  fontFamily: 'Georgia',
                                  fontSize: 24,
                                  height: 1.55,
                                ),
                              ),
                              if (selected.type == DayEntryType.daily) ...[
                                const SizedBox(height: 34),
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0EBD9),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Text(
                                        'WHAT ARE YOU GRATEFUL FOR TODAY?',
                                        style: TextStyle(
                                          fontSize: 11,
                                          letterSpacing: 1.05,
                                        ),
                                      ),
                                      TextField(
                                        key: const Key('gratitude-editor'),
                                        controller: gratitudeController,
                                        onChanged: onGratitudeChanged,
                                        minLines: 2,
                                        maxLines: 5,
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          hintText: 'A small thing is enough…',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryStack extends StatefulWidget {
  const _EntryStack({
    required this.entries,
    required this.selectedEntryId,
    required this.onSelected,
    required this.onAdd,
    required this.onMove,
  });

  final List<DayEntry> entries;
  final String selectedEntryId;
  final Future<void> Function(String) onSelected;
  final Future<void> Function() onAdd;
  final void Function(int) onMove;

  @override
  State<_EntryStack> createState() => _EntryStackState();
}

class _EntryStackState extends State<_EntryStack> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    final index = widget.entries.indexWhere(
      (entry) => entry.id == widget.selectedEntryId,
    );
    _controller = PageController(
      initialPage: index < 0 ? 0 : index,
      viewportFraction: .34,
    );
  }

  @override
  void didUpdateWidget(covariant _EntryStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedEntryId == widget.selectedEntryId) return;
    final index = widget.entries.indexWhere(
      (entry) => entry.id == widget.selectedEntryId,
    );
    if (index >= 0 && _controller.hasClients) {
      _controller.animateToPage(
        index,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 146,
    child: Row(
      children: [
        const SizedBox(width: 18),
        Expanded(
          child: Listener(
            key: const Key('entry-stack-wheel'),
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
                widget.onMove(event.scrollDelta.dy > 0 ? 1 : -1);
              }
            },
            child: PageView.builder(
              key: const Key('entry-stack'),
              controller: _controller,
              scrollDirection: Axis.vertical,
              padEnds: true,
              itemCount: widget.entries.length,
              onPageChanged: (index) =>
                  widget.onSelected(widget.entries[index].id),
              itemBuilder: (context, index) {
                final entry = widget.entries[index];
                final selected = entry.id == widget.selectedEntryId;
                return Semantics(
                  selected: selected,
                  child: ExcludeSemantics(
                    excluding: !selected,
                    child: Transform.translate(
                      offset: Offset(index.isEven ? 0 : 8, 0),
                      child: Material(
                        color: selected
                            ? const Color(0xFFFFFCF5)
                            : const Color(0xFFD9D5CB),
                        elevation: selected ? 4 : 0,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          key: Key('entry-slip-${entry.id}'),
                          onTap: () => widget.onSelected(entry.id),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  entry.type == DayEntryType.daily
                                      ? 'DAILY'
                                      : _entryTime(entry),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    letterSpacing: .8,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    entry.title.trim().isNotEmpty
                                        ? entry.title
                                        : entry.content.trim().isEmpty
                                        ? 'Untitled entry'
                                        : entry.content.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          key: const Key('new-entry'),
          tooltip: 'New entry',
          onPressed: widget.onAdd,
          icon: const Icon(Icons.add_rounded),
        ),
        const SizedBox(width: 18),
      ],
    ),
  );
}

String _entryTime(DayEntry entry) {
  final time = entry.createdAt.toLocal();
  final hour = time.hour == 0
      ? 12
      : time.hour > 12
      ? time.hour - 12
      : time.hour;
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${time.hour >= 12 ? 'PM' : 'AM'}';
}

String _friendlyDate(String? dateKey) {
  if (dateKey == null) return '';
  final date = localDateFromKey(dateKey);
  const months = [
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
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
