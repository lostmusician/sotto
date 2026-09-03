import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../providers/journal_providers.dart';
import '../services/bible_service.dart';

class ScriptureSelection {
  const ScriptureSelection(this.passage, {required this.insertText});
  final BiblePassage passage;
  final bool insertText;
}

class ScriptureWorkspace extends ConsumerStatefulWidget {
  const ScriptureWorkspace({super.key});

  @override
  ConsumerState<ScriptureWorkspace> createState() => _ScriptureWorkspaceState();
}

class _ScriptureWorkspaceState extends ConsumerState<ScriptureWorkspace> {
  static const _initialVersion = BibleVersion(
    id: 'NIV',
    abbreviation: 'NIV',
    title: 'New International Version',
    languageTag: 'en',
    copyright: '',
  );

  List<BibleVersion> _versions = const [];
  List<BibleBook> _books = const [];
  List<int> _chapters = const [1];
  List<BiblePassage> _results = const [];
  BibleVersion _version = _initialVersion;
  BibleBook? _book;
  int _chapter = 1;
  BiblePassage? _selected;
  bool _loading = true;
  Object? _error;

  BibleProvider get _provider => ref.read(youVersionBibleProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(_initialize);
  }

  Future<void> _initialize() async {
    try {
      final remote = ref.read(youVersionBibleProvider);
      if (!remote.isConfigured) {
        throw StateError(
          'Add a YouVersion app key to browse ESV, NIV, ERV, and NKJV.',
        );
      }
      final versions = await remote.versions();
      if (versions.isEmpty) {
        throw StateError(
          'None of ESV, NIV, ERV, or NKJV is licensed to this app key.',
        );
      }
      final preferredId = ref.read(journalControllerProvider).preferredBibleId;
      final selected = versions.firstWhere(
        (version) =>
            version.id == preferredId ||
            version.abbreviation.toUpperCase() == preferredId.toUpperCase(),
        orElse: () => versions.firstWhere(
          (version) => version.abbreviation.toUpperCase() == 'NIV',
          orElse: () => versions.first,
        ),
      );
      final books = await remote.books(selected);
      final chapters = books.isEmpty
          ? const [1]
          : await remote.chapters(selected, books.first);
      if (!mounted) return;
      setState(() {
        _versions = versions;
        _version = selected;
        _books = books;
        _chapters = chapters;
        _book = books.firstOrNull;
        _loading = false;
      });
      await _loadChapter();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  Future<void> _changeVersion(BibleVersion version) async {
    setState(() {
      _version = version;
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(journalControllerProvider.notifier)
          .setPreferredBibleId(version.abbreviation.toUpperCase());
      final books = await _provider.books(version);
      final chapters = books.isEmpty
          ? const [1]
          : await _provider.chapters(version, books.first);
      if (!mounted) return;
      setState(() {
        _books = books;
        _chapters = chapters;
        _book = books.firstOrNull;
        _chapter = 1;
      });
      await _loadChapter();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeBook(BibleBook book) async {
    setState(() {
      _book = book;
      _chapter = 1;
      _loading = true;
      _error = null;
    });
    try {
      final chapters = await _provider.chapters(_version, book);
      if (!mounted) return;
      setState(() => _chapters = chapters.isEmpty ? const [1] : chapters);
      await _loadChapter();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadChapter() async {
    final book = _book;
    if (book == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final passages = await _provider.chapterVerses(_version, book, _chapter);
      if (passages.isEmpty) {
        throw StateError('No verse text was returned for this chapter.');
      }
      if (!mounted) return;
      setState(() {
        _results = passages;
        _selected = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Scaffold(
      backgroundColor: const Color(0xFFFFFCF5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Scripture',
          style: TextStyle(fontFamily: 'Georgia', fontWeight: FontWeight.w600),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          _PassagePicker(
            versions: _versions,
            version: _version,
            books: _books,
            book: _book,
            chapters: _chapters,
            chapter: _chapter,
            onVersionChanged: _changeVersion,
            onBookChanged: _changeBook,
            onChapterChanged: (value) {
              setState(() => _chapter = value);
              _loadChapter();
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: _error != null
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: SelectableText(
                      'Scripture could not be loaded: $_error',
                    ),
                  )
                : ListView.separated(
                    key: const Key('scripture-verse-list'),
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final passage = _results[index];
                      final selected = _selected?.id == passage.id;
                      return Semantics(
                        selected: selected,
                        button: true,
                        label: passage.reference,
                        child: InkWell(
                          key: ValueKey('scripture-verse-${passage.id}'),
                          onTap: () => setState(() => _selected = passage),
                          borderRadius: BorderRadius.circular(8),
                          child: AnimatedContainer(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 140),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: .52)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 34,
                                  child: Text(
                                    passage.id.split('.').last,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    passage.content,
                                    style: const TextStyle(
                                      fontFamily: 'Georgia',
                                      fontSize: 17,
                                      height: 1.48,
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
          ),
          _ScriptureActionBar(
            version: _version,
            selected: _selected,
            onAttach: _selected == null
                ? null
                : () => Navigator.pop(
                    context,
                    ScriptureSelection(_selected!, insertText: false),
                  ),
            onInsert: _selected == null
                ? null
                : () => Navigator.pop(
                    context,
                    ScriptureSelection(_selected!, insertText: true),
                  ),
          ),
        ],
      ),
    ),
  );
}

class _PassagePicker extends StatelessWidget {
  const _PassagePicker({
    required this.versions,
    required this.version,
    required this.books,
    required this.book,
    required this.chapters,
    required this.chapter,
    required this.onVersionChanged,
    required this.onBookChanged,
    required this.onChapterChanged,
  });

  final List<BibleVersion> versions;
  final BibleVersion version;
  final List<BibleBook> books;
  final BibleBook? book;
  final List<int> chapters;
  final int chapter;
  final ValueChanged<BibleVersion> onVersionChanged;
  final ValueChanged<BibleBook> onBookChanged;
  final ValueChanged<int> onChapterChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
    child: Column(
      children: [
        DropdownButtonFormField<BibleVersion>(
          initialValue: version,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Translation'),
          items: [
            for (final item in versions)
              DropdownMenuItem(
                value: item,
                child: Text(
                  '${item.abbreviation} · ${item.title}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) onVersionChanged(value);
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<BibleBook>(
                initialValue: book,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Book'),
                items: [
                  for (final item in books)
                    DropdownMenuItem(
                      value: item,
                      child: Text(item.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onBookChanged(value);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: chapter,
                decoration: const InputDecoration(labelText: 'Chapter'),
                items: [
                  for (final item in chapters)
                    DropdownMenuItem(value: item, child: Text('$item')),
                ],
                onChanged: (value) {
                  if (value != null) onChapterChanged(value);
                },
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ScriptureActionBar extends StatelessWidget {
  const _ScriptureActionBar({
    required this.version,
    required this.selected,
    required this.onAttach,
    required this.onInsert,
  });

  final BibleVersion version;
  final BiblePassage? selected;
  final VoidCallback? onAttach;
  final VoidCallback? onInsert;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFFCF5),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            selected == null
                ? 'Select a verse to attach it to this entry.'
                : selected!.reference,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (version.copyright.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              version.copyright,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
          if (selected != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  key: const Key('attach-scripture-reference'),
                  onPressed: onAttach,
                  child: const Text('Attach reference'),
                ),
                FilledButton(
                  key: const Key('insert-scripture-verse'),
                  onPressed: onInsert,
                  child: const Text('Insert into note'),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}
