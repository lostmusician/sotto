import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/journal_entry.dart';
import '../providers/journal_providers.dart';
import 'binder_screen.dart';
import 'mood_dial.dart';
import 'scripture_screen.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({this.autoInitialize = true, super.key});

  final bool autoInitialize;

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
  int _scriptureRevision = 0;

  @override
  void initState() {
    super.initState();
    _writingFocus = FocusNode(onKeyEvent: _handleWritingKey);
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoInitialize) {
      Future.microtask(
        () => ref.read(journalControllerProvider.notifier).initialize(),
      );
    }
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
    _entryDebounce = Timer(const Duration(milliseconds: 700), () async {
      if (!await controller.saveCurrentEntry()) return;
      final current = ref.read(journalControllerProvider);
      final entry = current.selectedEntry;
      if (current.smartOrganizationEnabled && entry != null && !entry.isEmpty) {
        await ref
            .read(discoveryControllerProvider.notifier)
            .organizeEntry(entry);
      }
    });
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

  Future<void> _openScripture() async {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final selection = compact
        ? await showModalBottomSheet<ScriptureSelection>(
            context: context,
            isScrollControlled: true,
            builder: (context) => SizedBox(
              height: MediaQuery.sizeOf(context).height * .94,
              child: const ScriptureWorkspace(),
            ),
          )
        : await showGeneralDialog<ScriptureSelection>(
            context: context,
            barrierDismissible: true,
            barrierLabel: 'Close Scripture',
            barrierColor: Colors.black26,
            transitionDuration: const Duration(milliseconds: 220),
            pageBuilder: (context, animation, secondaryAnimation) => Align(
              alignment: Alignment.centerRight,
              child: Material(
                elevation: 16,
                child: SizedBox(
                  width: 560,
                  height: MediaQuery.sizeOf(context).height,
                  child: const ScriptureWorkspace(),
                ),
              ),
            ),
          );
    if (selection == null || !mounted) return;
    final entry = ref.read(journalControllerProvider).selectedEntry;
    if (entry == null) return;
    final passage = selection.passage;
    await ref
        .read(databaseServiceProvider)
        .saveScripture(
          ScriptureReference(
            id: const Uuid().v4(),
            entryId: entry.id,
            source: passage.version.isOffline ? 'bundled' : 'youversion',
            bibleId: passage.version.id,
            translationAbbreviation: passage.version.abbreviation,
            passageId: passage.id,
            reference: passage.reference,
            copyright: passage.version.copyright,
            cachedText: passage.version.isOffline ? passage.content : null,
          ),
        );
    if (selection.insertText) {
      final insertion =
          '“${passage.content}”\n— ${passage.reference} (${passage.version.abbreviation})';
      final value = _contentController.value;
      final selectionRange = value.selection.isValid
          ? value.selection
          : TextSelection.collapsed(offset: value.text.length);
      final next = value.text.replaceRange(
        selectionRange.start,
        selectionRange.end,
        insertion,
      );
      _contentController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(
          offset: selectionRange.start + insertion.length,
        ),
      );
      _onEntryChanged();
    }
    setState(() => _scriptureRevision += 1);
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
            scriptureRevision: _scriptureRevision,
            writingFocus: _writingFocus,
            onEntryChanged: _onEntryChanged,
            onGratitudeChanged: _onGratitudeChanged,
            onSelectEntry: _selectEntry,
            onAddEntry: () async {
              _entryDebounce?.cancel();
              await ref.read(journalControllerProvider.notifier).addEntry();
              if (mounted) _writingFocus.requestFocus();
            },
            onAddQuietTime: () async {
              _entryDebounce?.cancel();
              await ref.read(journalControllerProvider.notifier).addQuietTime();
              if (mounted) _writingFocus.requestFocus();
            },
            onOpenScripture: _openScripture,
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
    required this.scriptureRevision,
    required this.writingFocus,
    required this.onEntryChanged,
    required this.onGratitudeChanged,
    required this.onSelectEntry,
    required this.onAddEntry,
    required this.onAddQuietTime,
    required this.onOpenScripture,
    required this.onFinish,
    super.key,
  });

  final JournalAppState state;
  final TextEditingController titleController;
  final TextEditingController contentController;
  final TextEditingController gratitudeController;
  final int scriptureRevision;
  final FocusNode writingFocus;
  final VoidCallback onEntryChanged;
  final ValueChanged<String> onGratitudeChanged;
  final Future<void> Function(String) onSelectEntry;
  final Future<void> Function() onAddEntry;
  final Future<void> Function() onAddQuietTime;
  final Future<void> Function() onOpenScripture;
  final Future<void> Function() onFinish;

  @override
  State<_JournalView> createState() => _JournalViewState();
}

class _JournalViewState extends State<_JournalView> {
  void _moveSelection(int delta) {
    final index = widget.state.entries.indexWhere(
      (entry) => entry.id == widget.state.selectedEntryId,
    );
    final next = (index + delta).clamp(0, widget.state.entries.length - 1);
    if (next != index) {
      unawaited(widget.onSelectEntry(widget.state.entries[next].id));
    }
  }

  void _resumeWriting() => widget.writingFocus.requestFocus();

  @override
  Widget build(BuildContext context) {
    final selected = widget.state.selectedEntry;
    if (selected == null) return const _LoadingView();
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final compact = viewportWidth < 600;
    final wheelOverlapsWritingColumn = viewportWidth < 1380;
    final pagePadding = compact ? 20.0 : 48.0;
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
          _moveSelection(-1),
      const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
          _moveSelection(1),
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
                          wheelOverlapsWritingColumn ? 176 : 82,
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
                                      onChanged: (_) => widget.onEntryChanged(),
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
                                      onChanged: (_) => widget.onEntryChanged(),
                                      // Keep the gratitude footer in the initial
                                      // viewport, then let this field expand with
                                      // the journal as the user writes.
                                      minLines: compact ? 6 : 5,
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
                                        onChanged: widget.onGratitudeChanged,
                                        minLines: 2,
                                        maxLines: 5,
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          hintText: 'A small thing is enough…',
                                        ),
                                      ),
                                    ],
                                    if (selected.purpose ==
                                        EntryPurpose.quietTime)
                                      _QuietTimeFields(entryId: selected.id),
                                    if (widget.state.christianModeEnabled)
                                      _ScriptureAttachments(
                                        entryId: selected.id,
                                        revision: widget.scriptureRevision,
                                        onOpenScripture: widget.onOpenScripture,
                                      ),
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
                  child: _EntryWheel(
                    entries: widget.state.entries,
                    selectedEntryId: selected.id,
                    writingFocus: widget.writingFocus,
                    onSelected: widget.onSelectEntry,
                    onAdd: widget.onAddEntry,
                    onAddQuietTime: widget.onAddQuietTime,
                    onOpenScripture: widget.onOpenScripture,
                    christianMode: widget.state.christianModeEnabled,
                    onFinish: widget.onFinish,
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

class _QuietTimeFields extends ConsumerStatefulWidget {
  const _QuietTimeFields({required this.entryId});
  final String entryId;

  @override
  ConsumerState<_QuietTimeFields> createState() => _QuietTimeFieldsState();
}

class _QuietTimeFieldsState extends ConsumerState<_QuietTimeFields> {
  final _observation = TextEditingController();
  final _application = TextEditingController();
  final _prayer = TextEditingController();
  Timer? _debounce;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final reflection = await ref
        .read(databaseServiceProvider)
        .quietTimeForEntry(widget.entryId);
    if (!mounted) return;
    _observation.text = reflection?.observation ?? '';
    _application.text = reflection?.application ?? '';
    _prayer.text = reflection?.prayer ?? '';
    setState(() => _loaded = true);
  }

  void _changed(_) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      ref
          .read(databaseServiceProvider)
          .saveQuietTime(
            QuietTimeReflection(
              entryId: widget.entryId,
              observation: _observation.text,
              application: _application.text,
              prayer: _prayer.text,
            ),
          );
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _observation.dispose();
    _application.dispose();
    _prayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const LinearProgressIndicator();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 28),
        const Divider(),
        const SizedBox(height: 14),
        Text(
          'QUIET TIME',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.05,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        _ReflectionField(
          label: 'Observation',
          hint: 'What stands out in this passage?',
          controller: _observation,
          onChanged: _changed,
        ),
        _ReflectionField(
          label: 'Application',
          hint: 'How might this shape today?',
          controller: _application,
          onChanged: _changed,
        ),
        _ReflectionField(
          label: 'Prayer',
          hint: 'Respond in your own words…',
          controller: _prayer,
          onChanged: _changed,
        ),
      ],
    );
  }
}

class _ReflectionField extends StatelessWidget {
  const _ReflectionField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
  });
  final String label;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      minLines: 2,
      maxLines: 6,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

class _ScriptureAttachments extends ConsumerStatefulWidget {
  const _ScriptureAttachments({
    required this.entryId,
    required this.revision,
    required this.onOpenScripture,
  });
  final String entryId;
  final int revision;
  final Future<void> Function() onOpenScripture;

  @override
  ConsumerState<_ScriptureAttachments> createState() =>
      _ScriptureAttachmentsState();
}

class _ScriptureAttachmentsState extends ConsumerState<_ScriptureAttachments> {
  late Future<List<ScriptureReference>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant _ScriptureAttachments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entryId != widget.entryId ||
        oldWidget.revision != widget.revision) {
      _reload();
    }
  }

  void _reload() {
    _future = ref
        .read(databaseServiceProvider)
        .scripturesForEntry(widget.entryId);
  }

  @override
  Widget build(BuildContext context) {
    final christianMode = ref.watch(
      journalControllerProvider.select((state) => state.christianModeEnabled),
    );
    if (!christianMode) return const SizedBox.shrink();
    return FutureBuilder<List<ScriptureReference>>(
      future: _future,
      builder: (context, snapshot) {
        final references = snapshot.data ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (references.isNotEmpty) ...[
              const SizedBox(height: 24),
              for (final reference in references)
                Card(
                  color: Theme.of(
                    context,
                  ).colorScheme.secondaryContainer.withValues(alpha: .55),
                  child: ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(reference.reference),
                    subtitle: Text(
                      [
                        if (reference.cachedText != null) reference.cachedText!,
                        reference.translationAbbreviation,
                        reference.copyright,
                      ].join('\n'),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove verse',
                      onPressed: () async {
                        await ref
                            .read(databaseServiceProvider)
                            .deleteScripture(reference.id);
                        setState(_reload);
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await widget.onOpenScripture();
                  if (mounted) setState(_reload);
                },
                icon: const Icon(Icons.add),
                label: const Text('Attach Scripture'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EntryWheel extends StatefulWidget {
  const _EntryWheel({
    required this.entries,
    required this.selectedEntryId,
    required this.writingFocus,
    required this.onSelected,
    required this.onAdd,
    required this.onAddQuietTime,
    required this.onOpenScripture,
    required this.christianMode,
    required this.onFinish,
  });

  final List<DayEntry> entries;
  final String selectedEntryId;
  final FocusNode writingFocus;
  final Future<void> Function(String) onSelected;
  final Future<void> Function() onAdd;
  final Future<void> Function() onAddQuietTime;
  final Future<void> Function() onOpenScripture;
  final bool christianMode;
  final Future<void> Function() onFinish;

  @override
  State<_EntryWheel> createState() => _EntryWheelState();
}

class _EntryWheelState extends State<_EntryWheel> {
  static const _itemExtent = 42.0;

  late FixedExtentScrollController _scrollController;
  bool _hovering = false;
  late int _visualIndex;
  bool _selectionInFlight = false;
  int? _queuedSelection;

  int get _selectedIndex {
    final index = widget.entries.indexWhere(
      (entry) => entry.id == widget.selectedEntryId,
    );
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    _visualIndex = _selectedIndex;
    _scrollController = FixedExtentScrollController(initialItem: _visualIndex);
  }

  @override
  void didUpdateWidget(covariant _EntryWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedIndex = _selectedIndex.clamp(0, widget.entries.length - 1);
    if (selectedIndex == _visualIndex &&
        oldWidget.entries.length == widget.entries.length) {
      return;
    }
    _visualIndex = selectedIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.selectedItem != selectedIndex) {
        _scrollController.jumpToItem(selectedIndex);
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _commitVisualSelection() async {
    final index = _visualIndex.clamp(0, widget.entries.length - 1);
    if (widget.entries[index].id == widget.selectedEntryId) return;
    if (_selectionInFlight) {
      _queuedSelection = index;
      return;
    }
    _selectionInFlight = true;
    await widget.onSelected(widget.entries[index].id);
    if (!mounted) return;
    _selectionInFlight = false;
    final queued = _queuedSelection;
    _queuedSelection = null;
    if (queued != null && queued != index) {
      _visualIndex = queued.clamp(0, widget.entries.length - 1);
      await _commitVisualSelection();
    }
  }

  Future<void> _moveTo(int index) async {
    final target = index.clamp(0, widget.entries.length - 1);
    if (target == _visualIndex) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _scrollController.jumpToItem(target);
      setState(() => _visualIndex = target);
    } else {
      await _scrollController.animateToItem(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
    await _commitVisualSelection();
  }

  Key? _positionKey(int index) {
    if (index == _visualIndex) return const Key('entry-wheel-center');
    if (index == _visualIndex - 1) return const Key('entry-wheel-previous');
    if (index == _visualIndex + 1) return const Key('entry-wheel-next');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final safeIndex = _selectedIndex;
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
          final faded = widget.writingFocus.hasFocus && !_hovering;
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
        child: SizedBox(
          key: const Key('entry-wheel-panel'),
          width: compact ? 220 : 284,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: 12),
                        child: Text(
                          'ENTRIES',
                          style: TextStyle(fontSize: 9, letterSpacing: 1.1),
                        ),
                      ),
                    ),
                    _CompactAction(
                      key: const Key('new-entry'),
                      tooltip: 'New entry',
                      onPressed: widget.onAdd,
                      icon: Icons.add_rounded,
                    ),
                    if (widget.christianMode)
                      _CompactAction(
                        key: const Key('new-quiet-time'),
                        tooltip: 'New Quiet Time',
                        onPressed: widget.onAddQuietTime,
                        icon: Icons.church_outlined,
                      ),
                    if (widget.christianMode)
                      _CompactAction(
                        key: const Key('open-scripture'),
                        tooltip: 'Open Scripture',
                        onPressed: widget.onOpenScripture,
                        icon: Icons.menu_book_outlined,
                      ),
                    _CompactAction(
                      key: const Key('finish-journal'),
                      tooltip: 'Done for now',
                      onPressed: widget.onFinish,
                      icon: Icons.check_rounded,
                    ),
                  ],
                ),
              ),
              Semantics(
                container: true,
                label:
                    'Current entry, ${safeIndex + 1} of ${widget.entries.length}',
                value: _entryLabel(selected),
                increasedValue: safeIndex < widget.entries.length - 1
                    ? _entryLabel(widget.entries[safeIndex + 1])
                    : null,
                decreasedValue: safeIndex > 0
                    ? _entryLabel(widget.entries[safeIndex - 1])
                    : null,
                onIncrease: safeIndex < widget.entries.length - 1
                    ? () => _moveTo(safeIndex + 1)
                    : null,
                onDecrease: safeIndex > 0 ? () => _moveTo(safeIndex - 1) : null,
                child: ExcludeSemantics(
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x80FFFFFF),
                        Colors.white,
                        Colors.white,
                        Color(0x80FFFFFF),
                      ],
                      stops: [0, .32, .68, 1],
                    ).createShader(bounds),
                    blendMode: BlendMode.dstIn,
                    child: SizedBox(
                      height: _itemExtent * 3,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollEndNotification) {
                            unawaited(_commitVisualSelection());
                          }
                          return false;
                        },
                        child: ListWheelScrollView.useDelegate(
                          key: const Key('entry-wheel'),
                          controller: _scrollController,
                          itemExtent: _itemExtent,
                          physics: const FixedExtentScrollPhysics(),
                          diameterRatio: 2.7,
                          perspective: .002,
                          squeeze: .92,
                          overAndUnderCenterOpacity: 1,
                          onSelectedItemChanged: (index) {
                            if (_visualIndex != index) {
                              setState(() => _visualIndex = index);
                            }
                          },
                          childDelegate: ListWheelChildBuilderDelegate(
                            childCount: widget.entries.length,
                            builder: (context, index) {
                              if (index < 0 || index >= widget.entries.length) {
                                return null;
                              }
                              final entry = widget.entries[index];
                              final isCentered = index == _visualIndex;
                              return AnimatedOpacity(
                                key: _positionKey(index),
                                duration: duration,
                                opacity: isCentered ? 1 : .62,
                                child: AnimatedScale(
                                  duration: duration,
                                  scale: isCentered ? 1 : .92,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: isCentered ? .09 : .04,
                                            ),
                                            blurRadius: isCentered ? 12 : 7,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: BackdropFilter(
                                          filter: ui.ImageFilter.blur(
                                            sigmaX: 9,
                                            sigmaY: 9,
                                          ),
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: highContrast
                                                    ? const [
                                                        Color(0xFFFFFCF5),
                                                        Color(0xFFFFFCF5),
                                                      ]
                                                    : isCentered
                                                    ? const [
                                                        Color(0xB8FFFFFF),
                                                        Color(0x7AF6F0E6),
                                                      ]
                                                    : const [
                                                        Color(0x8CFFFFFF),
                                                        Color(0x52F6F0E6),
                                                      ],
                                              ),
                                              border: Border.all(
                                                color: highContrast
                                                    ? const Color(0x994F4B56)
                                                    : const Color(0x8AFFFFFF),
                                                width: .75,
                                              ),
                                            ),
                                            child: InkWell(
                                              key: Key(
                                                'entry-slip-${entry.id}',
                                              ),
                                              onTap: () => _moveTo(index),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    SizedBox(
                                                      width: 58,
                                                      child: Text(
                                                        entry.type ==
                                                                DayEntryType
                                                                    .daily
                                                            ? 'DAILY'
                                                            : _entryTime(entry),
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.fade,
                                                        softWrap: false,
                                                        style: const TextStyle(
                                                          fontSize: 8,
                                                          letterSpacing: .65,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 7),
                                                    Expanded(
                                                      child: Text(
                                                        _entryExcerpt(entry),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: isCentered
                                                              ? FontWeight.w600
                                                              : FontWeight.w400,
                                                        ),
                                                      ),
                                                    ),
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
                              );
                            },
                          ),
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
    );
  }
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
