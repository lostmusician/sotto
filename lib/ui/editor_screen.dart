import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../providers/journal_providers.dart';
import 'archive_screen.dart';
import 'mood_dial.dart';
import 'pixel_scene.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final _textController = TextEditingController();
  final _replyController = TextEditingController();
  final _writingFocus = FocusNode();
  final _replyFocus = FocusNode();
  Timer? _saveDebounce;
  Timer? _replyDebounce;
  Timer? _moodDebounce;
  String? _loadedEntryId;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(journalControllerProvider.notifier).initialize(),
    );
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _replyDebounce?.cancel();
    _moodDebounce?.cancel();
    _textController.dispose();
    _replyController.dispose();
    _writingFocus.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  void _onWritingChanged(String value) {
    ref.read(journalControllerProvider.notifier).updateContent(value);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(
      const Duration(milliseconds: 700),
      ref.read(journalControllerProvider.notifier).saveDraft,
    );
  }

  void _onReplyChanged(String value) {
    final controller = ref.read(journalControllerProvider.notifier);
    controller.updateReflectionReply(value);
    _replyDebounce?.cancel();
    _replyDebounce = Timer(
      const Duration(milliseconds: 700),
      () => controller.saveReflectionReply(value),
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

  Future<void> _openArchive() async {
    await ref.read(journalControllerProvider.notifier).openArchive();
    await ref.read(archiveControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(journalControllerProvider);
    final entry = session.entry;
    if (entry != null && _loadedEntryId != entry.id) {
      _loadedEntryId = entry.id;
      _textController.value = TextEditingValue(
        text: entry.content,
        selection: TextSelection.collapsed(offset: entry.content.length),
      );
      _replyController.text = entry.reflectionReply;
    }
    if (entry != null &&
        session.phase == SessionPhase.reflection &&
        !_replyFocus.hasFocus &&
        _replyController.text != entry.reflectionReply) {
      _replyController.text = entry.reflectionReply;
    }

    return Material(
      color: Colors.transparent,
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: switch (session.phase) {
          SessionPhase.arrival => _ArrivalView(
            key: const ValueKey('arrival'),
            session: session,
            onBegin: () async {
              await ref.read(journalControllerProvider.notifier).beginSession();
              if (mounted) _writingFocus.requestFocus();
            },
            onMoodChanged: _onMoodChanged,
            onArchive: _openArchive,
          ),
          SessionPhase.writing => _WritingView(
            key: const ValueKey('writing'),
            session: session,
            controller: _textController,
            focusNode: _writingFocus,
            onChanged: _onWritingChanged,
            onArchive: _openArchive,
            onClose: () => unawaited(
              ref.read(journalControllerProvider.notifier).requestClose(),
            ),
          ),
          SessionPhase.reflection => _ReflectionView(
            key: const ValueKey('reflection'),
            session: session,
            replyController: _replyController,
            replyFocus: _replyFocus,
            onReplyChanged: _onReplyChanged,
            onReopen: () async {
              await ref
                  .read(journalControllerProvider.notifier)
                  .reopenWriting();
              if (mounted) _writingFocus.requestFocus();
            },
            onFinish: () async {
              final controller = ref.read(journalControllerProvider.notifier);
              await controller.saveReflectionReply(_replyController.text);
              await controller.finishSession();
              await ref.read(archiveControllerProvider.notifier).refresh();
            },
          ),
          SessionPhase.archive => ArchiveScreen(
            key: const ValueKey('archive'),
            onBack: ref.read(journalControllerProvider.notifier).leaveArchive,
            onNewSession: () {
              ref.read(journalControllerProvider.notifier).startNewSession();
              _loadedEntryId = null;
              _textController.clear();
              _replyController.clear();
            },
          ),
        },
      ),
    );
  }
}

class _ArrivalView extends StatelessWidget {
  const _ArrivalView({
    required this.session,
    required this.onBegin,
    required this.onMoodChanged,
    required this.onArchive,
    super.key,
  });

  final JournalSessionState session;
  final Future<void> Function() onBegin;
  final void Function(double angle, double intensity) onMoodChanged;
  final Future<void> Function() onArchive;

  @override
  Widget build(BuildContext context) {
    final checkIn = session.todayCheckIn;
    final angle = checkIn?.moodAngle ?? .12;
    final intensity = checkIn?.moodIntensity ?? .55;
    final accent = MoodPalette.colorFor(angle, intensity);
    return ColoredBox(
      color: Color.lerp(const Color(0xFFF4F0E8), accent, .16)!,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 12,
              right: 18,
              child: IconButton(
                key: const Key('arrival-archive'),
                tooltip: 'Open archive',
                onPressed: onArchive,
                icon: const Icon(Icons.auto_stories_outlined),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 36,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    children: [
                      const Text(
                        'How did today feel?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 36,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Move around the circle for tone, inward or outward for intensity.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF686B62),
                        ),
                      ),
                      const SizedBox(height: 32),
                      MoodDial(
                        angle: angle,
                        intensity: intensity,
                        onChanged: onMoodChanged,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 250,
                        child: SessionScene(
                          phase: checkIn == null
                              ? SessionPhase.arrival
                              : SessionPhase.writing,
                          accent: accent,
                          compact: true,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        key: const Key('begin-session'),
                        onPressed: session.isLoading ? null : onBegin,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF34372F),
                          foregroundColor: const Color(0xFFFBF8F0),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 17,
                          ),
                        ),
                        child: Text(
                          session.hasUnfinishedDraft
                              ? 'Continue previous session'
                              : 'Enter the room',
                        ),
                      ),
                      if (session.hasUnfinishedDraft) ...[
                        const SizedBox(height: 12),
                        Text(
                          '${session.entry!.wordCount} words are waiting for you.',
                          style: const TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
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

class _WritingView extends StatelessWidget {
  const _WritingView({
    required this.session,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onArchive,
    required this.onClose,
    super.key,
  });

  final JournalSessionState session;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onArchive;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final mood = session.todayCheckIn;
    final accent = MoodPalette.colorFor(
      mood?.moodAngle ?? .12,
      mood?.moodIntensity ?? .55,
    );
    return ColoredBox(
      color: Color.lerp(const Color(0xFFFCFAF5), accent, .07)!,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 12,
              left: 14,
              child: IconButton(
                key: const Key('writing-archive'),
                tooltip: 'Open archive',
                onPressed: onArchive,
                icon: const Icon(Icons.auto_stories_outlined),
              ),
            ),
            Positioned(
              top: 14,
              right: 20,
              child: TextButton(
                key: const Key('close-session'),
                onPressed: onClose,
                child: const Text('Close session'),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 86, 28, 38),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: TextField(
                      key: const Key('journal-editor'),
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: onChanged,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      cursorColor: const Color(0xFF34372F),
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 28,
                        height: 1.55,
                        letterSpacing: -.3,
                        color: Color(0xFF292C26),
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Start where you are…',
                        hintStyle: TextStyle(color: Color(0xFFAAA99F)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 22,
              bottom: 20,
              width: MediaQuery.sizeOf(context).width < 700 ? 180 : 270,
              child: IgnorePointer(
                child: Opacity(
                  opacity: .78,
                  child: SessionScene(
                    phase: SessionPhase.writing,
                    accent: accent,
                    compact: true,
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

class _ReflectionView extends StatelessWidget {
  const _ReflectionView({
    required this.session,
    required this.replyController,
    required this.replyFocus,
    required this.onReplyChanged,
    required this.onReopen,
    required this.onFinish,
    super.key,
  });

  final JournalSessionState session;
  final TextEditingController replyController;
  final FocusNode replyFocus;
  final ValueChanged<String> onReplyChanged;
  final Future<void> Function() onReopen;
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    final mood = session.todayCheckIn;
    final accent = MoodPalette.colorFor(
      mood?.moodAngle ?? .12,
      mood?.moodIntensity ?? .55,
    );
    final question = session.entry?.reflectionQuestion;
    return ColoredBox(
      color: Color.lerp(const Color(0xFFF0ECE3), accent, .16)!,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SessionScene(phase: SessionPhase.reflection, accent: accent),
                  const SizedBox(height: 38),
                  const Text(
                    'Before you go',
                    style: TextStyle(
                      fontSize: 13,
                      letterSpacing: 1.2,
                      color: Color(0xFF66695F),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    child: session.isReflecting
                        ? const Row(
                            key: ValueKey('reflecting'),
                            children: [
                              SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Finding a question in what you wrote…',
                                style: TextStyle(fontStyle: FontStyle.italic),
                              ),
                            ],
                          )
                        : Text(
                            question ?? 'What would you like to carry forward?',
                            key: const ValueKey('question'),
                            style: const TextStyle(
                              fontFamily: 'Georgia',
                              fontSize: 30,
                              height: 1.28,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    key: const Key('reflection-reply'),
                    controller: replyController,
                    focusNode: replyFocus,
                    onChanged: onReplyChanged,
                    minLines: 2,
                    maxLines: 6,
                    decoration: InputDecoration(
                      hintText: 'A thought, if you want to leave one…',
                      filled: true,
                      fillColor: const Color(0xA8FFFCF5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    style: const TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 18,
                      height: 1.45,
                    ),
                  ),
                  if (session.lastReflectionWasDemo) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Local fallback reflection',
                      style: TextStyle(fontSize: 11, color: Color(0xFF74776E)),
                    ),
                  ],
                  const SizedBox(height: 26),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      TextButton(
                        key: const Key('continue-writing'),
                        onPressed: onReopen,
                        child: const Text('Continue writing'),
                      ),
                      FilledButton(
                        key: const Key('finish-session'),
                        onPressed: onFinish,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF34372F),
                          foregroundColor: const Color(0xFFFBF8F0),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                        child: const Text('Save and finish'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
