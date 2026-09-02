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
  final _search = TextEditingController();
  List<BibleVersion> _versions = const [BundledBibleProvider.version];
  List<BibleBook> _books = const [];
  List<int> _chapters = const [1];
  List<BiblePassage> _results = const [];
  BibleVersion _version = BundledBibleProvider.version;
  BibleBook? _book;
  int _chapter = 1;
  BiblePassage? _selected;
  bool _loading = true;
  Object? _error;

  BibleProvider get _provider => _version.isOffline
      ? ref.read(bundledBibleProvider)
      : ref.read(youVersionBibleProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(_initialize);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final offline = ref.read(bundledBibleProvider);
      var versions = const [BundledBibleProvider.version];
      final remote = ref.read(youVersionBibleProvider);
      if (remote.isConfigured) {
        try {
          final online = await remote.versions();
          versions = [
            BundledBibleProvider.version,
            ...online.where((item) => item.id != '3034'),
          ];
        } catch (_) {
          // Offline Scripture remains fully functional without an app key.
        }
      }
      final preferredId = ref.read(journalControllerProvider).preferredBibleId;
      final selected = versions.firstWhere(
        (version) => version.id == preferredId,
        orElse: () => BundledBibleProvider.version,
      );
      final selectedProvider = selected.isOffline
          ? offline
          : ref.read(youVersionBibleProvider);
      final books = await selectedProvider.books(selected);
      final chapters = books.isEmpty
          ? const [1]
          : await selectedProvider.chapters(selected, books.first);
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
      if (mounted) setState(() => _error = error);
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
          .setPreferredBibleId(version.id);
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

  Future<void> _runSearch() async {
    final query = _search.text.trim();
    if (query.isEmpty) return _loadChapter();
    setState(() => _loading = true);
    try {
      final results = await _provider.search(_version, query);
      if (mounted) setState(() => _results = results);
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(
              children: [
                DropdownButtonFormField<BibleVersion>(
                  initialValue: _version,
                  decoration: const InputDecoration(labelText: 'Translation'),
                  items: [
                    for (final version in _versions)
                      DropdownMenuItem(
                        value: version,
                        child: Text(
                          '${version.abbreviation} · ${version.title}',
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
                        decoration: const InputDecoration(labelText: 'Book'),
                        items: [
                          for (final book in _books)
                            DropdownMenuItem(
                              value: book,
                              child: Text(book.name),
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
                        decoration: const InputDecoration(labelText: 'Chapter'),
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
                SearchBar(
                  controller: _search,
                  hintText: _version.isOffline
                      ? 'Search the BSB offline'
                      : 'Online versions support reference browsing',
                  leading: const Icon(Icons.search),
                  onSubmitted: (_) => _runSearch(),
                  trailing: [
                    IconButton(
                      onPressed: _runSearch,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Scripture could not be loaded: $_error'),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final passage = _results[index];
                final selected = _selected?.id == passage.id;
                return Card(
                  color: selected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  child: ListTile(
                    selected: selected,
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
                );
              },
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
  );
}
