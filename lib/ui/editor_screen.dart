import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/journal_providers.dart';
import 'pixel_scene.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});
  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _saveDebounce;
  Timer? _reflectionDebounce;
  String? _loadedEntryId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(journalControllerProvider.notifier).initialize();
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _reflectionDebounce?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    ref.read(journalControllerProvider.notifier).updateContent(value);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(
      const Duration(milliseconds: 700),
      ref.read(journalControllerProvider.notifier).save,
    );
    _reflectionDebounce?.cancel();
    if (value.trim().split(RegExp(r'\s+')).length >= 8) {
      _reflectionDebounce = Timer(const Duration(seconds: 10), _reflect);
    }
  }

  Future<void> _reflect() async {
    final state = ref.read(journalControllerProvider);
    final excerpt = _lastWords(state.entry.content, 150);
    if (excerpt.isEmpty || ref.read(aiTypingProvider)) return;
    ref.read(aiTypingProvider.notifier).state = true;
    try {
      final result = await ref.read(aiServiceProvider).reflectOn(excerpt);
      if (mounted) {
        await ref
            .read(journalControllerProvider.notifier)
            .addReflection(result);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('The companion could not reflect: $error')),
        );
      }
    } finally {
      if (mounted) {
        ref.read(aiTypingProvider.notifier).state = false;
      }
    }
  }

  String _lastWords(String text, int count) {
    final words = text.trim().split(RegExp(r'\s+'));
    return words.length <= count
        ? text.trim()
        : words.sublist(words.length - count).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(journalControllerProvider);
    final entry = session.entry;
    final wordCount = ref.watch(activeWordCountProvider);
    final isThinking = ref.watch(aiTypingProvider);
    if (_loadedEntryId != entry.id) {
      _loadedEntryId = entry.id;
      _textController.value = TextEditingValue(
        text: entry.content,
        selection: TextSelection.collapsed(offset: entry.content.length),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final editor = _EditorPane(
              controller: _textController,
              focusNode: _focusNode,
              onChanged: _onChanged,
              isLoading: session.isLoading,
            );
            final companion = _CompanionPane(
              wordCount: wordCount,
              targetWordCount: entry.targetWordCount,
              isThinking: isThinking,
              annotation: entry.annotations.lastOrNull?.question,
              isDemo: session.lastReflectionWasDemo,
            );
            if (constraints.maxWidth < 900) {
              return Column(
                children: [
                  SizedBox(height: 260, child: companion),
                  Expanded(child: editor),
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 66, child: editor),
                Expanded(flex: 34, child: companion),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EditorPane extends StatelessWidget {
  const _EditorPane({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.isLoading,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFEFDF9),
        border: Border.all(color: const Color(0xFFD8D8D2)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 96, 28, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  cursorColor: const Color(0xFF24271F),
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 29,
                    height: 1.48,
                    letterSpacing: -.35,
                    color: Color(0xFF23251F),
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Begin with what is true…',
                    hintStyle: TextStyle(color: Color(0xFFB1B1AA)),
                  ),
                ),
              ),
            ),
          ),
          if (isLoading)
            const Positioned(
              top: 24,
              left: 24,
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompanionPane extends StatelessWidget {
  const _CompanionPane({
    required this.wordCount,
    required this.targetWordCount,
    required this.isThinking,
    required this.annotation,
    required this.isDemo,
  });
  final int wordCount;
  final int targetWordCount;
  final bool isThinking;
  final String? annotation;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F6F7),
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          child: Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: PixelScene(
                  wordCount: wordCount,
                  targetWordCount: targetWordCount,
                  isThinking: isThinking,
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: isThinking
                    ? const Padding(
                        key: ValueKey('thinking'),
                        padding: EdgeInsets.only(top: 24),
                        child: Text(
                          'Your companion is thinking…',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      )
                    : annotation == null
                    ? const SizedBox.shrink(key: ValueKey('empty'))
                    : Container(
                        key: ValueKey(annotation),
                        margin: const EdgeInsets.only(top: 24),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEFDF9),
                          border: Border.all(color: const Color(0xFFC9CDC5)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              annotation!,
                              style: const TextStyle(
                                fontFamily: 'Georgia',
                                fontSize: 19,
                                height: 1.35,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            if (isDemo) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'DEMO REFLECTION · add a local GGUF model for AI',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 9,
                                  letterSpacing: .7,
                                  color: Color(0xFF6C7469),
                                ),
                              ),
                            ],
                          ],
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
