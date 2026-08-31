import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../providers/journal_providers.dart';
import 'mood_dial.dart';

class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({
    required this.onBack,
    required this.onNewSession,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onNewSession;

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  final _scrollController = ScrollController();
  bool _scaleHandled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    Future.microtask(() {
      if (ref.read(archiveControllerProvider).entries.isEmpty) {
        ref.read(archiveControllerProvider.notifier).refresh();
      }
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 480) {
      ref.read(archiveControllerProvider.notifier).loadMore();
    }
  }

  void _changeZoom(ArchiveZoom zoom) {
    final progress =
        _scrollController.hasClients &&
            _scrollController.position.maxScrollExtent > 0
        ? (_scrollController.offset /
                  _scrollController.position.maxScrollExtent)
              .clamp(0.0, 1.0)
        : 0.0;
    ref.read(archiveControllerProvider.notifier).setZoom(zoom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(
        math.min(
          progress * _scrollController.position.maxScrollExtent,
          _scrollController.position.maxScrollExtent,
        ),
      );
    });
  }

  void _onScaleUpdate(ScaleUpdateDetails details, ArchiveZoom current) {
    if (_scaleHandled) return;
    final index = ArchiveZoom.values.indexOf(current);
    if (details.scale > 1.12 && index > 0) {
      _scaleHandled = true;
      _changeZoom(ArchiveZoom.values[index - 1]);
    } else if (details.scale < .88 && index < ArchiveZoom.values.length - 1) {
      _scaleHandled = true;
      _changeZoom(ArchiveZoom.values[index + 1]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final archive = ref.watch(archiveControllerProvider);
    final groups = _groupsFor(archive);
    return ColoredBox(
      color: const Color(0xFFF2EFE7),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('archive-back'),
                    tooltip: 'Back to session',
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Your days',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('archive-new-session'),
                    onPressed: widget.onNewSession,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New session'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SegmentedButton<ArchiveZoom>(
                key: const Key('archive-zoom'),
                segments: const [
                  ButtonSegment(
                    value: ArchiveZoom.entries,
                    label: Text('Entries'),
                  ),
                  ButtonSegment(value: ArchiveZoom.weeks, label: Text('Weeks')),
                  ButtonSegment(
                    value: ArchiveZoom.months,
                    label: Text('Months'),
                  ),
                ],
                selected: {archive.zoom},
                onSelectionChanged: (selection) => _changeZoom(selection.first),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GestureDetector(
                onScaleStart: (_) => _scaleHandled = false,
                onScaleUpdate: (details) =>
                    _onScaleUpdate(details, archive.zoom),
                child: CustomScrollView(
                  key: PageStorageKey('archive-${archive.zoom.name}'),
                  controller: _scrollController,
                  slivers: [
                    if (groups.isEmpty && !archive.isLoading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            'Closed sessions will gather here.',
                            style: TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                        sliver: SliverList.builder(
                          itemCount: groups.length,
                          itemBuilder: (context, index) => _ArchiveGroupCard(
                            group: groups[index],
                            zoom: archive.zoom,
                            checkIns: archive.checkIns,
                          ),
                        ),
                      ),
                    if (archive.isLoading)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_ArchiveGroup> _groupsFor(ArchiveState state) {
    if (state.zoom == ArchiveZoom.entries) {
      return [
        for (final entry in state.entries)
          _ArchiveGroup(label: _entryDate(entry), entries: [entry]),
      ];
    }
    final groups = <String, List<JournalEntry>>{};
    for (final entry in state.entries) {
      final date = (entry.closedAt ?? entry.updatedAt).toLocal();
      final key = state.zoom == ArchiveZoom.weeks
          ? _weekKey(date)
          : '${_monthName(date.month)} ${date.year}';
      groups.putIfAbsent(key, () => []).add(entry);
    }
    return [
      for (final item in groups.entries)
        _ArchiveGroup(label: item.key, entries: item.value),
    ];
  }
}

class _ArchiveGroupCard extends StatelessWidget {
  const _ArchiveGroupCard({
    required this.group,
    required this.zoom,
    required this.checkIns,
  });

  final _ArchiveGroup group;
  final ArchiveZoom zoom;
  final Map<String, DailyCheckIn> checkIns;

  @override
  Widget build(BuildContext context) {
    final mood = _averageMood(group.entries, checkIns);
    final color = mood == null
        ? const Color(0xFFC3C3BA)
        : MoodPalette.colorFor(mood.$1, mood.$2);
    if (zoom != ArchiveZoom.entries) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .24),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withValues(alpha: .44)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.label,
                    style: const TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${group.entries.length} ${group.entries.length == 1 ? 'session' : 'sessions'}',
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final entry = group.entries.single;
    final excerpt = entry.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFAF5),
        borderRadius: BorderRadius.circular(22),
        border: Border(left: BorderSide(color: color, width: 5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Text(group.label, style: const TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            excerpt.isEmpty ? 'A quiet session.' : excerpt,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Georgia',
              fontSize: 18,
              height: 1.45,
            ),
          ),
          if (entry.reflectionQuestion?.isNotEmpty ?? false) ...[
            const SizedBox(height: 14),
            Text(
              entry.reflectionQuestion!,
              style: TextStyle(
                color: color.computeLuminance() < .4
                    ? color
                    : const Color(0xFF596054),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  (double, double)? _averageMood(
    List<JournalEntry> entries,
    Map<String, DailyCheckIn> checkIns,
  ) {
    final moods = entries
        .map(
          (entry) => checkIns[localDateKey(entry.closedAt ?? entry.updatedAt)],
        )
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
    final averageAngle = ((math.atan2(y, x) / (math.pi * 2)) + 1) % 1;
    return (
      averageAngle,
      moods.fold<double>(0, (sum, mood) => sum + mood.moodIntensity) /
          moods.length,
    );
  }
}

class _ArchiveGroup {
  const _ArchiveGroup({required this.label, required this.entries});
  final String label;
  final List<JournalEntry> entries;
}

String _entryDate(JournalEntry entry) {
  final date = (entry.closedAt ?? entry.updatedAt).toLocal();
  return '${_monthName(date.month)} ${date.day}, ${date.year}';
}

String _weekKey(DateTime date) {
  final monday = date.subtract(Duration(days: date.weekday - DateTime.monday));
  return 'Week of ${_monthName(monday.month)} ${monday.day}';
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
