import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../providers/journal_providers.dart';
import '../services/embedding_service.dart';

class MenoSettingsSheet extends ConsumerWidget {
  const MenoSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(journalControllerProvider);
    final embedding = ref.watch(embeddingServiceProvider);
    final discovery = ref.watch(discoveryControllerProvider);
    return SafeArea(
      child: SizedBox(
        height: math.min(MediaQuery.sizeOf(context).height * .82, 680),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            const Text(
              'Meno settings',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Evening begins'),
              subtitle: Text(
                TimeOfDay(
                  hour: app.eveningPreference.hour,
                  minute: app.eveningPreference.minute,
                ).format(context),
              ),
              onTap: () async {
                final selected = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(
                    hour: app.eveningPreference.hour,
                    minute: app.eveningPreference.minute,
                  ),
                );
                if (selected != null) {
                  await ref
                      .read(journalControllerProvider.notifier)
                      .updateEveningPreference(
                        selected.hour * 60 + selected.minute,
                      );
                }
              },
            ),
            const Divider(),
            SwitchListTile.adaptive(
              key: const Key('smart-organization-setting'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Smart Organization'),
              subtitle: const Text(
                'Suggest editable tags and connect related entries on this device.',
              ),
              value: app.smartOrganizationEnabled,
              onChanged: (enabled) async {
                await ref
                    .read(journalControllerProvider.notifier)
                    .setSmartOrganizationEnabled(enabled);
                if (!enabled) {
                  ref
                      .read(discoveryControllerProvider.notifier)
                      .cancelIndexing();
                  return;
                }
                try {
                  await embedding.downloadModel();
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Semantic model unavailable. Local keyphrase tags still work.',
                        ),
                      ),
                    );
                  }
                }
                unawaited(
                  ref
                      .read(discoveryControllerProvider.notifier)
                      .organizeBackCatalog(),
                );
              },
            ),
            StreamBuilder<EmbeddingStatus>(
              stream: embedding.status,
              builder: (context, snapshot) {
                final status = snapshot.data;
                if (status?.availability != EmbeddingAvailability.downloading) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(value: status?.progress),
                );
              },
            ),
            FutureBuilder<bool>(
              future: embedding.isAvailable(),
              builder: (context, snapshot) {
                if (snapshot.data != true || app.smartOrganizationEnabled) {
                  return const SizedBox.shrink();
                }
                return Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: embedding.deleteModel,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Remove semantic model'),
                  ),
                );
              },
            ),
            if (discovery.isLoading) ...[
              LinearProgressIndicator(
                value: discovery.totalEntries == 0
                    ? null
                    : discovery.indexedEntries / discovery.totalEntries,
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      discovery.totalEntries == 0
                          ? 'Organizing your journal…'
                          : '${discovery.indexedEntries} of ${discovery.totalEntries} entries organized',
                    ),
                  ),
                  TextButton(
                    onPressed: ref
                        .read(discoveryControllerProvider.notifier)
                        .cancelIndexing,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
            const Divider(),
            SwitchListTile.adaptive(
              key: const Key('christian-mode-setting'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Christian Mode'),
              subtitle: const Text(
                'Add licensed Scripture, verse attachments, and Quiet Time entries.',
              ),
              value: app.christianModeEnabled,
              onChanged: (enabled) => ref
                  .read(journalControllerProvider.notifier)
                  .setChristianModeEnabled(enabled),
            ),
            if (app.christianModeEnabled)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Preferred Bible'),
                subtitle: const Text(
                  'Choose ESV, NIV, ERV, or NKJV in the Scripture workspace',
                ),
                trailing: Text(app.preferredBibleId),
              ),
            const SizedBox(height: 12),
            Text(
              'Journal analysis stays on this device. Online Bible requests never include journal text.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class DiscoverySheet extends ConsumerStatefulWidget {
  const DiscoverySheet({this.initialEntryId, super.key});
  final String? initialEntryId;

  @override
  ConsumerState<DiscoverySheet> createState() => _DiscoverySheetState();
}

class _DiscoverySheetState extends ConsumerState<DiscoverySheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _query = TextEditingController();
  final _selectedTags = <String>{};
  EntryPurpose? _purpose;
  String? _scriptureBook;
  String? _fromDateKey;
  String? _toDateKey;
  int? _graphWindowDays = 90;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    Future.microtask(_search);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() => ref
      .read(discoveryControllerProvider.notifier)
      .search(
        JournalSearchQuery(
          text: _query.text,
          tagIds: _selectedTags.toList(),
          purpose: _purpose,
          scriptureBook: _scriptureBook,
          fromDateKey: _fromDateKey,
          toDateKey: _toDateKey,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final discovery = ref.watch(discoveryControllerProvider);
    final binder = ref.watch(binderControllerProvider);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Find a thread',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 27,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Search & related'),
                Tab(text: 'Connections'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _SearchPane(
                    query: _query,
                    discovery: discovery,
                    initialEntryId: widget.initialEntryId,
                    selectedTags: _selectedTags,
                    purpose: _purpose,
                    onPurposeChanged: (value) {
                      setState(() => _purpose = value);
                      _search();
                    },
                    onTagChanged: (id, selected) {
                      setState(() {
                        if (selected) {
                          _selectedTags.add(id);
                        } else {
                          _selectedTags.remove(id);
                        }
                      });
                      _search();
                    },
                    onSearch: _search,
                    onAdvancedFilters: _showAdvancedFilters,
                    advancedFilterCount: [
                      _scriptureBook,
                      _fromDateKey,
                      _toDateKey,
                    ].whereType<String>().length,
                    onOpen: _openEntry,
                    onAddTag: _addTag,
                    onRenameTag: _renameTag,
                    onRemoveTag: (entryId, tagId) => ref
                        .read(discoveryControllerProvider.notifier)
                        .removeTag(entryId, tagId),
                  ),
                  _ConnectionsPane(
                    days: binder.days,
                    relationships: discovery.relationships,
                    entryTags: discovery.entryTags,
                    tags: discovery.tags,
                    selectedTags: _selectedTags,
                    windowDays: _graphWindowDays,
                    onWindowChanged: (value) =>
                        setState(() => _graphWindowDays = value),
                    onTagChanged: (id, selected) {
                      setState(() {
                        if (selected) {
                          _selectedTags.add(id);
                        } else {
                          _selectedTags.remove(id);
                        }
                      });
                    },
                    onOpen: _openEntry,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEntry(DayEntry entry) async {
    Navigator.pop(context);
    final controller = ref.read(journalControllerProvider.notifier);
    await controller.openDay(entry.dateKey);
    await controller.selectEntry(entry.id);
  }

  Future<void> _addTag(DayEntry entry) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Family, prayer, work…'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await ref
          .read(discoveryControllerProvider.notifier)
          .addManualTag(entry.id, name);
    }
  }

  Future<void> _showAdvancedFilters() async {
    final scripture = TextEditingController(text: _scriptureBook ?? '');
    final from = TextEditingController(text: _fromDateKey ?? '');
    final to = TextEditingController(text: _toDateKey ?? '');
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Date & Scripture filters'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: scripture,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Scripture book code',
                hintText: 'JHN, PSA, ROM…',
              ),
            ),
            TextField(
              controller: from,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'From date',
                hintText: 'YYYY-MM-DD',
              ),
            ),
            TextField(
              controller: to,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'To date',
                hintText: 'YYYY-MM-DD',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    final scriptureValue = scripture.text.trim();
    final fromValue = from.text.trim();
    final toValue = to.text.trim();
    scripture.dispose();
    from.dispose();
    to.dispose();
    if (!mounted || apply == null) return;
    setState(() {
      _scriptureBook = apply && scriptureValue.isNotEmpty
          ? scriptureValue.toUpperCase()
          : null;
      _fromDateKey = apply && fromValue.isNotEmpty ? fromValue : null;
      _toDateKey = apply && toValue.isNotEmpty ? toValue : null;
    });
    await _search();
  }

  Future<void> _renameTag(JournalTag tag) async {
    final controller = TextEditingController(text: tag.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty && name.trim() != tag.name) {
      await ref
          .read(discoveryControllerProvider.notifier)
          .renameTag(tag.id, name);
      await _search();
    }
  }
}

class _SearchPane extends StatelessWidget {
  const _SearchPane({
    required this.query,
    required this.discovery,
    required this.initialEntryId,
    required this.selectedTags,
    required this.purpose,
    required this.onPurposeChanged,
    required this.onTagChanged,
    required this.onSearch,
    required this.onAdvancedFilters,
    required this.advancedFilterCount,
    required this.onOpen,
    required this.onAddTag,
    required this.onRenameTag,
    required this.onRemoveTag,
  });

  final TextEditingController query;
  final DiscoveryState discovery;
  final String? initialEntryId;
  final Set<String> selectedTags;
  final EntryPurpose? purpose;
  final ValueChanged<EntryPurpose?> onPurposeChanged;
  final void Function(String, bool) onTagChanged;
  final VoidCallback onSearch;
  final VoidCallback onAdvancedFilters;
  final int advancedFilterCount;
  final ValueChanged<DayEntry> onOpen;
  final ValueChanged<DayEntry> onAddTag;
  final ValueChanged<JournalTag> onRenameTag;
  final void Function(String, String) onRemoveTag;

  @override
  Widget build(BuildContext context) {
    final relatedIds = {
      for (final relationship
          in discovery.relationships[initialEntryId] ?? const [])
        relationship.targetEntryId,
    };
    final results = initialEntryId == null
        ? discovery.results
        : [
            ...discovery.results.where(
              (result) => relatedIds.contains(result.entry.id),
            ),
            ...discovery.results.where(
              (result) => !relatedIds.contains(result.entry.id),
            ),
          ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        SearchBar(
          key: const Key('journal-search'),
          controller: query,
          hintText: 'Search your writing',
          leading: const Icon(Icons.search),
          trailing: [
            IconButton(
              onPressed: onSearch,
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
          onSubmitted: (_) => onSearch(),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onAdvancedFilters,
            icon: const Icon(Icons.tune_rounded),
            label: Text(
              advancedFilterCount == 0
                  ? 'Date & Scripture'
                  : 'Date & Scripture ($advancedFilterCount)',
            ),
          ),
        ),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            FilterChip(
              label: const Text('Quiet Time'),
              selected: purpose == EntryPurpose.quietTime,
              onSelected: (selected) =>
                  onPurposeChanged(selected ? EntryPurpose.quietTime : null),
            ),
            for (final tag in discovery.tags)
              FilterChip(
                label: Text(tag.name),
                selected: selectedTags.contains(tag.id),
                onSelected: (selected) => onTagChanged(tag.id, selected),
              ),
          ],
        ),
        if (discovery.isLoading) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (initialEntryId != null && relatedIds.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(
            'Related entries',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
        const SizedBox(height: 10),
        for (final result in results)
          Card(
            child: ListTile(
              onTap: () => onOpen(result.entry),
              title: Text(
                result.entry.title.trim().isEmpty
                    ? result.entry.dateKey
                    : result.entry.title,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.entry.content.trim().isEmpty
                        ? 'A quiet page.'
                        : result.entry.content.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (result.tags.isNotEmpty)
                    Wrap(
                      spacing: 5,
                      children: [
                        for (final entryTag in result.tags.take(5))
                          InputChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(entryTag.tag.name),
                            tooltip: 'Edit ${entryTag.tag.name}',
                            onPressed: () => onRenameTag(entryTag.tag),
                            onDeleted: () =>
                                onRemoveTag(result.entry.id, entryTag.tag.id),
                          ),
                      ],
                    ),
                ],
              ),
              trailing: IconButton(
                tooltip: 'Add tag',
                onPressed: () => onAddTag(result.entry),
                icon: const Icon(Icons.new_label_outlined),
              ),
            ),
          ),
        if (!discovery.isLoading && results.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: Text('No matching entries yet.')),
          ),
      ],
    );
  }
}

class _ConnectionsPane extends StatelessWidget {
  const _ConnectionsPane({
    required this.days,
    required this.relationships,
    required this.entryTags,
    required this.tags,
    required this.selectedTags,
    required this.windowDays,
    required this.onWindowChanged,
    required this.onTagChanged,
    required this.onOpen,
  });

  final List<BinderDay> days;
  final Map<String, List<EntryRelationship>> relationships;
  final Map<String, List<EntryTag>> entryTags;
  final List<JournalTag> tags;
  final Set<String> selectedTags;
  final int? windowDays;
  final ValueChanged<int?> onWindowChanged;
  final void Function(String, bool) onTagChanged;
  final ValueChanged<DayEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final newestDate = days.firstOrNull == null
        ? null
        : localDateFromKey(days.first.day.dateKey);
    final cutoff = newestDate == null || windowDays == null
        ? null
        : newestDate.subtract(Duration(days: windowDays!));
    final entries = days
        .expand((day) => day.entries)
        .where((entry) => !entry.isEmpty)
        .where(
          (entry) =>
              cutoff == null ||
              !localDateFromKey(entry.dateKey).isBefore(cutoff),
        )
        .where((entry) {
          final ids = (entryTags[entry.id] ?? const [])
              .map((entryTag) => entryTag.tag.id)
              .toSet();
          return selectedTags.every(ids.contains);
        })
        .take(40)
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Wrap(
            spacing: 7,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<int?>(
                value: windowDays,
                items: const [
                  DropdownMenuItem(value: 30, child: Text('Last 30 days')),
                  DropdownMenuItem(value: 90, child: Text('Last 90 days')),
                  DropdownMenuItem(value: null, child: Text('All dates')),
                ],
                onChanged: onWindowChanged,
              ),
              for (final tag in tags)
                FilterChip(
                  label: Text(tag.name),
                  selected: selectedTags.contains(tag.id),
                  onSelected: (selected) => onTagChanged(tag.id, selected),
                ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('No connections match these filters.'))
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: CustomPaint(
                    key: const Key('connections-graph'),
                    painter: _ConnectionsPainter(
                      entries,
                      relationships,
                      Theme.of(context).colorScheme,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
        ),
        if (entries.isNotEmpty)
          SizedBox(
            height: 150,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              scrollDirection: Axis.horizontal,
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => ActionChip(
                label: Text(
                  entries[index].title.trim().isEmpty
                      ? entries[index].dateKey
                      : entries[index].title,
                ),
                onPressed: () => onOpen(entries[index]),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConnectionsPainter extends CustomPainter {
  _ConnectionsPainter(this.entries, this.relationships, this.colors);
  final List<DayEntry> entries;
  final Map<String, List<EntryRelationship>> relationships;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * .38;
    final points = <String, Offset>{};
    for (var index = 0; index < entries.length; index++) {
      final angle = -math.pi / 2 + index / entries.length * math.pi * 2;
      points[entries[index].id] =
          center + Offset(math.cos(angle), math.sin(angle)) * radius;
    }
    final edgePaint = Paint()
      ..color = colors.primary.withValues(alpha: .22)
      ..strokeWidth = 1.3;
    for (final entry in entries) {
      for (final relationship in (relationships[entry.id] ?? const []).take(
        3,
      )) {
        final from = points[entry.id];
        final to = points[relationship.targetEntryId];
        if (from != null && to != null) canvas.drawLine(from, to, edgePaint);
      }
    }
    final nodePaint = Paint()..color = colors.primaryContainer;
    for (final point in points.values) {
      canvas.drawCircle(point, 6, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionsPainter oldDelegate) =>
      oldDelegate.entries != entries ||
      oldDelegate.relationships != relationships;
}
