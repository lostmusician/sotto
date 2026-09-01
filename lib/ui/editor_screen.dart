import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

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

class _JournalView extends StatefulWidget {
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

  @override
  State<_JournalView> createState() => _JournalViewState();
}

class _JournalViewState extends State<_JournalView> {
  bool _stackExpanded = false;

  void _moveSelection(int delta) {
    final index = widget.state.entries.indexWhere(
      (entry) => entry.id == widget.state.selectedEntryId,
    );
    final next = (index + delta).clamp(0, widget.state.entries.length - 1);
    if (next != index) {
      setState(() => _stackExpanded = false);
      unawaited(widget.onSelectEntry(widget.state.entries[next].id));
    }
  }

  Future<void> _selectEntry(String id) async {
    setState(() => _stackExpanded = false);
    await widget.onSelectEntry(id);
  }

  Future<void> _addEntry() async {
    setState(() => _stackExpanded = false);
    await widget.onAddEntry();
  }

  void _resumeWriting() {
    if (_stackExpanded) setState(() => _stackExpanded = false);
    widget.writingFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.state.selectedEntry;
    if (selected == null) return const _LoadingView();
    final compact = MediaQuery.sizeOf(context).width < 600;
    final pagePadding = compact ? 20.0 : 48.0;
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
          _moveSelection(-1),
      const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
          _moveSelection(1),
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (_stackExpanded) setState(() => _stackExpanded = false);
      },
    };
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          key: const Key('full-page-journal'),
          color: const Color(0xFFFFFCF5),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) => AnimatedSwitcher(
                      duration: duration,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, .018),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: SingleChildScrollView(
                        key: ValueKey(selected.id),
                        padding: EdgeInsets.fromLTRB(
                          pagePadding,
                          82,
                          pagePadding,
                          48,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: math.max(0, constraints.maxHeight - 130),
                          ),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 780),
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: _resumeWriting,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    TextField(
                                      key: const Key('entry-title'),
                                      controller: widget.titleController,
                                      onTap: _resumeWriting,
                                      onChanged: (_) {
                                        if (_stackExpanded) {
                                          setState(
                                            () => _stackExpanded = false,
                                          );
                                        }
                                        widget.onEntryChanged();
                                      },
                                      decoration: InputDecoration(
                                        border: InputBorder.none,
                                        hintText:
                                            selected.type == DayEntryType.daily
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
                                      controller: widget.contentController,
                                      focusNode: widget.writingFocus,
                                      autofocus: true,
                                      onTap: _resumeWriting,
                                      onChanged: (_) {
                                        if (_stackExpanded) {
                                          setState(
                                            () => _stackExpanded = false,
                                          );
                                        }
                                        widget.onEntryChanged();
                                      },
                                      minLines: compact ? 15 : 17,
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
                                    if (selected.type ==
                                        DayEntryType.daily) ...[
                                      const SizedBox(height: 42),
                                      const Divider(),
                                      const SizedBox(height: 18),
                                      Text(
                                        'WHAT ARE YOU GRATEFUL FOR TODAY?',
                                        style: TextStyle(
                                          fontSize: 11,
                                          letterSpacing: 1.05,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      TextField(
                                        key: const Key('gratitude-editor'),
                                        controller: widget.gratitudeController,
                                        onTap: _resumeWriting,
                                        onChanged: widget.onGratitudeChanged,
                                        minLines: 2,
                                        maxLines: 5,
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          hintText: 'A small thing is enough…',
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
                    ),
                  ),
                ),
                Positioned(
                  left: compact ? 14 : 22,
                  top: 14,
                  child: AnimatedBuilder(
                    animation: widget.writingFocus,
                    builder: (context, child) => AnimatedOpacity(
                      duration: duration,
                      opacity: widget.writingFocus.hasFocus
                          ? compact
                                ? .68
                                : .34
                          : .82,
                      child: child,
                    ),
                    child: Text(
                      _friendlyDate(widget.state.selectedDateKey),
                      key: const Key('floating-journal-date'),
                      style: const TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: compact ? 8 : 16,
                  top: 8,
                  child: _EntryStack(
                    entries: widget.state.entries,
                    selectedEntryId: selected.id,
                    writingFocus: widget.writingFocus,
                    expanded: _stackExpanded,
                    onToggle: () =>
                        setState(() => _stackExpanded = !_stackExpanded),
                    onSelected: _selectEntry,
                    onAdd: _addEntry,
                    onFinish: widget.onFinish,
                    onMove: _moveSelection,
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
    required this.writingFocus,
    required this.expanded,
    required this.onToggle,
    required this.onSelected,
    required this.onAdd,
    required this.onFinish,
    required this.onMove,
  });

  final List<DayEntry> entries;
  final String selectedEntryId;
  final FocusNode writingFocus;
  final bool expanded;
  final VoidCallback onToggle;
  final Future<void> Function(String) onSelected;
  final Future<void> Function() onAdd;
  final Future<void> Function() onFinish;
  final void Function(int) onMove;

  @override
  State<_EntryStack> createState() => _EntryStackState();
}

class _EntryStackState extends State<_EntryStack> {
  bool _hovering = false;
  double _verticalDrag = 0;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = widget.entries.indexWhere(
      (entry) => entry.id == widget.selectedEntryId,
    );
    final safeIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final selected = widget.entries[safeIndex];
    final compact = MediaQuery.sizeOf(context).width < 600;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedBuilder(
        animation: widget.writingFocus,
        builder: (context, child) {
          final faded =
              widget.writingFocus.hasFocus && !_hovering && !widget.expanded;
          return AnimatedOpacity(
            duration: duration,
            opacity: highContrast
                ? 1
                : faded
                ? compact
                      ? .72
                      : .34
                : 1,
            child: child,
          );
        },
        child: Listener(
          key: const Key('entry-stack-wheel'),
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
              widget.onMove(event.scrollDelta.dy > 0 ? 1 : -1);
            }
          },
          child: GestureDetector(
            key: const Key('entry-stack'),
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) => _verticalDrag = 0,
            onVerticalDragUpdate: (details) {
              _verticalDrag += details.primaryDelta ?? 0;
            },
            onVerticalDragEnd: (_) {
              if (_verticalDrag.abs() > 20) {
                widget.onMove(_verticalDrag < 0 ? 1 : -1);
              }
            },
            child: _GlassSurface(
              child: SizedBox(
                width: compact ? 220 : 284,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            button: true,
                            expanded: widget.expanded,
                            label:
                                'Current entry, ${safeIndex + 1} of ${widget.entries.length}, ${_entryLabel(selected)}',
                            onIncrease: () => widget.onMove(1),
                            onDecrease: () => widget.onMove(-1),
                            child: InkWell(
                              key: const Key('entry-stack-toggle'),
                              onTap: widget.onToggle,
                              borderRadius: BorderRadius.circular(13),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _entryLabel(selected),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      widget.expanded
                                          ? Icons.expand_less_rounded
                                          : Icons.expand_more_rounded,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        _CompactAction(
                          key: const Key('new-entry'),
                          tooltip: 'New entry',
                          onPressed: widget.onAdd,
                          icon: Icons.add_rounded,
                        ),
                        _CompactAction(
                          key: const Key('finish-journal'),
                          tooltip: 'Done for now',
                          onPressed: widget.onFinish,
                          icon: Icons.check_rounded,
                        ),
                      ],
                    ),
                    AnimatedSize(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      child: widget.expanded
                          ? ConstrainedBox(
                              key: const Key('entry-stack-expanded'),
                              constraints: const BoxConstraints(maxHeight: 150),
                              child: ListView.builder(
                                shrinkWrap: true,
                                padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
                                itemExtent: 46,
                                itemCount: widget.entries.length,
                                itemBuilder: (context, index) {
                                  final entry = widget.entries[index];
                                  final isSelected =
                                      entry.id == widget.selectedEntryId;
                                  return Semantics(
                                    selected: isSelected,
                                    button: true,
                                    label: _entryLabel(entry),
                                    child: InkWell(
                                      key: Key('entry-slip-${entry.id}'),
                                      onTap: () => widget.onSelected(entry.id),
                                      borderRadius: BorderRadius.circular(11),
                                      child: Container(
                                        margin: EdgeInsets.only(
                                          left: index.isEven ? 0 : 7,
                                          bottom: 4,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 11,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0xCCFFFFFF)
                                              : const Color(0x66E3DED3),
                                          borderRadius: BorderRadius.circular(
                                            11,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Text(
                                              entry.type == DayEntryType.daily
                                                  ? 'DAILY'
                                                  : _entryTime(entry),
                                              style: const TextStyle(
                                                fontSize: 9,
                                                letterSpacing: .7,
                                              ),
                                            ),
                                            const SizedBox(width: 9),
                                            Expanded(
                                              child: Text(
                                                _entryExcerpt(entry),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            )
                          : const SizedBox.shrink(),
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

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MediaQuery.highContrastOf(context)
              ? const Color(0xFFFFFCF5)
              : const Color(0xCFFFFCF5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x4D4F4B56)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x16000000),
              blurRadius: 16,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: child,
      ),
    ),
  );
}

class _CompactAction extends StatelessWidget {
  const _CompactAction({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    super.key,
  });

  final String tooltip;
  final Future<void> Function() onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 40, height: 40),
    onPressed: onPressed,
    icon: Icon(icon, size: 19),
  );
}

String _entryLabel(DayEntry entry) {
  if (entry.type == DayEntryType.daily) return 'Daily Journal';
  if (entry.title.trim().isNotEmpty) return entry.title.trim();
  return _entryTime(entry);
}

String _entryExcerpt(DayEntry entry) {
  if (entry.title.trim().isNotEmpty) return entry.title.trim();
  if (entry.content.trim().isNotEmpty) return entry.content.trim();
  return 'Untitled entry';
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
