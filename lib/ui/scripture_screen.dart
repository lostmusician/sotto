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
      final chapter = await _provider.passage(_version, '${book.id}.$_chapter');
      final passages = <BiblePassage>[];
      for (final line in chapter.content.split('\n')) {
        final match = RegExp(
          r'^(\d+)\s+(.*)$',
          dotAll: true,
        ).firstMatch(line.trim());
        if (match == null) continue;
        final verse = int.parse(match.group(1)!);
        passages.add(
          BiblePassage(
            id: '${book.id}.$_chapter.$verse',
            reference: '${book.name} $_chapter:$verse',
            content: match.group(2)!,
            version: _version,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _results = passages.isEmpty ? [chapter] : passages;
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
      appBar: AppBar(
        title: const Text('Scripture'),
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
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 20),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Column(
                    children: [
                      DropdownButtonFormField<BibleVersion>(
                        initialValue: _version,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Translation',
                        ),
                        items: [
                          for (final version in _versions)
                            DropdownMenuItem(
                              value: version,
                              child: Text(
                                '${version.abbreviation} · ${version.title}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) _changeVersion(value);
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<BibleBook>(
                              initialValue: _book,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Book',
                              ),
                              items: [
                                for (final book in _books)
                                  DropdownMenuItem(
                                    value: book,
                                    child: Text(
                                      book.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) _changeBook(value);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _chapter,
                              decoration: const InputDecoration(
                                labelText: 'Chapter',
                              ),
                              items: [
                                for (final chapter in _chapters)
                                  DropdownMenuItem(
                                    value: chapter,
                                    child: Text('$chapter'),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _chapter = value);
                                _loadChapter();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Available translations depend on the licenses approved for this app.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      'Scripture could not be loaded: $_error',
                    ),
                  ),
                for (final passage in _results)
                  Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    color: _selected?.id == passage.id
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    child: ListTile(
                      selected: _selected?.id == passage.id,
                      title: Text(passage.reference),
                      subtitle: Text(
                        passage.content,
                        style: const TextStyle(
                          fontFamily: 'Georgia',
                          height: 1.4,
                        ),
                      ),
                      onTap: () => setState(() => _selected = passage),
                    ),
                  ),
                if (_selected != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(
                              context,
                              ScriptureSelection(_selected!, insertText: false),
                            ),
                            child: const Text('Attach verse'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(
                              context,
                              ScriptureSelection(_selected!, insertText: true),
                            ),
                            child: const Text('Attach & insert'),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text(
                    _version.copyright,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
