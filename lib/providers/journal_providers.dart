import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../services/ai_service.dart';
import '../services/database_service.dart';

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final service = DatabaseService();
  ref.onDispose(service.close);
  return service;
});

final reflectionServiceProvider = Provider<ReflectionService>(
  (ref) => AiService(),
);

class JournalSessionState {
  const JournalSessionState({
    this.phase = SessionPhase.arrival,
    this.phaseBeforeArchive = SessionPhase.arrival,
    this.entry,
    this.todayCheckIn,
    this.isLoading = false,
    this.isReflecting = false,
    this.lastReflectionWasDemo = false,
    this.error,
  });

  final SessionPhase phase;
  final SessionPhase phaseBeforeArchive;
  final JournalEntry? entry;
  final DailyCheckIn? todayCheckIn;
  final bool isLoading;
  final bool isReflecting;
  final bool lastReflectionWasDemo;
  final Object? error;

  bool get hasUnfinishedDraft =>
      entry != null && entry!.status == EntryStatus.draft;

  JournalSessionState copyWith({
    SessionPhase? phase,
    SessionPhase? phaseBeforeArchive,
    JournalEntry? entry,
    bool clearEntry = false,
    DailyCheckIn? todayCheckIn,
    bool? isLoading,
    bool? isReflecting,
    bool? lastReflectionWasDemo,
    Object? error,
    bool clearError = false,
  }) => JournalSessionState(
    phase: phase ?? this.phase,
    phaseBeforeArchive: phaseBeforeArchive ?? this.phaseBeforeArchive,
    entry: clearEntry ? null : entry ?? this.entry,
    todayCheckIn: todayCheckIn ?? this.todayCheckIn,
    isLoading: isLoading ?? this.isLoading,
    isReflecting: isReflecting ?? this.isReflecting,
    lastReflectionWasDemo: lastReflectionWasDemo ?? this.lastReflectionWasDemo,
    error: clearError ? null : error ?? this.error,
  );
}

class JournalController extends StateNotifier<JournalSessionState> {
  JournalController(this._database, this._reflectionService)
    : super(const JournalSessionState());

  final DatabaseService _database;
  final ReflectionService _reflectionService;

  Future<void> initialize({DateTime? now}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final timestamp = now ?? DateTime.now();
      final results = await Future.wait<Object?>([
        _database.latestDraft(),
        _database.checkInForDate(localDateKey(timestamp)),
      ]);
      state = state.copyWith(
        entry: results[0] as JournalEntry?,
        clearEntry: results[0] == null,
        todayCheckIn: results[1] as DailyCheckIn?,
        phase: SessionPhase.arrival,
        isLoading: false,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  void updateMood(double angle, double intensity, {DateTime? now}) {
    final existing = state.todayCheckIn;
    final timestamp = now ?? DateTime.now();
    final checkIn = existing == null
        ? DailyCheckIn.today(
            moodAngle: angle,
            moodIntensity: intensity,
            now: timestamp,
          )
        : existing.copyWith(
            moodAngle: angle,
            moodIntensity: intensity,
            updatedAt: timestamp.toUtc(),
          );
    state = state.copyWith(todayCheckIn: checkIn, clearError: true);
  }

  Future<void> saveMood() async {
    final checkIn = state.todayCheckIn;
    if (checkIn == null) return;
    try {
      await _database.saveCheckIn(checkIn);
    } catch (error) {
      state = state.copyWith(error: error);
    }
  }

  Future<void> beginSession({DateTime? now}) async {
    if (state.phase != SessionPhase.arrival) return;
    final timestamp = now ?? DateTime.now();
    final checkIn =
        state.todayCheckIn ??
        DailyCheckIn.today(moodAngle: .12, moodIntensity: .55, now: timestamp);
    final entry = state.hasUnfinishedDraft
        ? state.entry!
        : JournalEntry.empty(now: timestamp);
    state = state.copyWith(
      phase: SessionPhase.writing,
      entry: entry,
      todayCheckIn: checkIn,
      clearError: true,
    );
    try {
      await Future.wait([
        _database.saveCheckIn(checkIn),
        _database.saveEntry(entry),
      ]);
    } catch (error) {
      state = state.copyWith(error: error);
    }
  }

  void updateContent(String content) {
    if (state.phase != SessionPhase.writing || state.entry == null) return;
    state = state.copyWith(
      entry: state.entry!.copyWith(
        content: content,
        updatedAt: DateTime.now().toUtc(),
      ),
      clearError: true,
    );
  }

  Future<void> saveDraft() async {
    final entry = state.entry;
    if (entry == null || entry.status != EntryStatus.draft) return;
    try {
      await _database.saveEntry(entry);
    } catch (error) {
      state = state.copyWith(error: error);
    }
  }

  Future<void> requestClose() async {
    final entry = state.entry;
    if (state.phase != SessionPhase.writing ||
        entry == null ||
        state.isReflecting) {
      return;
    }
    await saveDraft();
    if (state.phase != SessionPhase.writing || state.entry?.id != entry.id) {
      return;
    }
    state = state.copyWith(
      phase: SessionPhase.reflection,
      isReflecting: true,
      clearError: true,
    );
    final entryId = entry.id;
    late final ReflectionResult result;
    try {
      result = await _reflectionService.reflectOn(entry.content);
    } catch (error) {
      result = ReflectionResult(
        question: 'What feels most true here?',
        isDemo: true,
        failure: error,
      );
    }
    if (state.phase != SessionPhase.reflection || state.entry?.id != entryId) {
      return;
    }
    final updated = state.entry!.copyWith(
      reflectionQuestion: result.question,
      updatedAt: DateTime.now().toUtc(),
    );
    state = state.copyWith(
      entry: updated,
      isReflecting: false,
      lastReflectionWasDemo: result.isDemo,
      error: result.failure,
    );
    try {
      await _database.saveEntry(updated);
    } catch (error) {
      state = state.copyWith(error: error);
    }
  }

  Future<void> saveReflectionReply(String reply) async {
    if (state.phase != SessionPhase.reflection || state.entry == null) return;
    updateReflectionReply(reply);
    try {
      await _database.saveEntry(state.entry!);
    } catch (error) {
      state = state.copyWith(error: error);
    }
  }

  void updateReflectionReply(String reply) {
    if (state.phase != SessionPhase.reflection || state.entry == null) return;
    state = state.copyWith(
      entry: state.entry!.copyWith(
        reflectionReply: reply,
        updatedAt: DateTime.now().toUtc(),
      ),
      clearError: true,
    );
  }

  Future<void> reopenWriting() async {
    if (state.phase != SessionPhase.reflection || state.entry == null) return;
    final entry = state.entry!.copyWith(
      clearReflectionQuestion: true,
      reflectionReply: '',
      updatedAt: DateTime.now().toUtc(),
    );
    state = state.copyWith(
      phase: SessionPhase.writing,
      entry: entry,
      isReflecting: false,
      lastReflectionWasDemo: false,
      clearError: true,
    );
    try {
      await _database.saveEntry(entry);
    } catch (error) {
      state = state.copyWith(error: error);
    }
  }

  Future<void> finishSession({DateTime? now}) async {
    if (state.phase != SessionPhase.reflection || state.entry == null) return;
    final timestamp = (now ?? DateTime.now()).toUtc();
    final closed = state.entry!.copyWith(
      status: EntryStatus.closed,
      closedAt: timestamp,
      updatedAt: timestamp,
    );
    state = state.copyWith(
      phase: SessionPhase.archive,
      phaseBeforeArchive: SessionPhase.arrival,
      entry: closed,
      isReflecting: false,
      clearError: true,
    );
    try {
      await _database.saveEntry(closed);
    } catch (error) {
      state = state.copyWith(error: error);
    }
  }

  Future<void> openArchive() async {
    if (state.phase == SessionPhase.archive) return;
    if (state.phase == SessionPhase.arrival) await saveMood();
    if (state.phase == SessionPhase.writing) await saveDraft();
    state = state.copyWith(
      phaseBeforeArchive: state.phase,
      phase: SessionPhase.archive,
    );
  }

  void leaveArchive() {
    if (state.phase != SessionPhase.archive) return;
    state = state.copyWith(phase: state.phaseBeforeArchive);
  }

  void startNewSession() {
    state = state.copyWith(
      phase: SessionPhase.arrival,
      phaseBeforeArchive: SessionPhase.arrival,
      clearEntry: true,
      isReflecting: false,
      lastReflectionWasDemo: false,
      clearError: true,
    );
  }
}

final journalControllerProvider =
    StateNotifierProvider<JournalController, JournalSessionState>(
      (ref) => JournalController(
        ref.watch(databaseServiceProvider),
        ref.watch(reflectionServiceProvider),
      ),
    );

class ArchiveState {
  const ArchiveState({
    this.zoom = ArchiveZoom.entries,
    this.entries = const [],
    this.checkIns = const {},
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  final ArchiveZoom zoom;
  final List<JournalEntry> entries;
  final Map<String, DailyCheckIn> checkIns;
  final bool isLoading;
  final bool hasMore;
  final Object? error;

  ArchiveState copyWith({
    ArchiveZoom? zoom,
    List<JournalEntry>? entries,
    Map<String, DailyCheckIn>? checkIns,
    bool? isLoading,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) => ArchiveState(
    zoom: zoom ?? this.zoom,
    entries: entries ?? this.entries,
    checkIns: checkIns ?? this.checkIns,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : error ?? this.error,
  );
}

class ArchiveController extends StateNotifier<ArchiveState> {
  ArchiveController(this._database) : super(const ArchiveState());

  static const pageSize = 30;
  final DatabaseService _database;

  Future<void> refresh() async {
    state = state.copyWith(
      entries: const [],
      checkIns: const {},
      hasMore: true,
      clearError: true,
    );
    await loadMore();
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final last = state.entries.lastOrNull;
      final page = await _database.archivePage(
        cursor: last?.closedAt == null
            ? null
            : ArchiveCursor(closedAt: last!.closedAt!, entryId: last.id),
        limit: pageSize,
      );
      final pageCheckIns = <String, DailyCheckIn>{};
      if (page.isNotEmpty) {
        final dates =
            page
                .map((entry) => localDateKey(entry.closedAt ?? entry.updatedAt))
                .toList()
              ..sort();
        final checkIns = await _database.checkInsBetween(
          dates.first,
          dates.last,
        );
        for (final checkIn in checkIns) {
          pageCheckIns[checkIn.dateKey] = checkIn;
        }
      }
      state = state.copyWith(
        entries: [...state.entries, ...page],
        checkIns: {...state.checkIns, ...pageCheckIns},
        isLoading: false,
        hasMore: page.length == pageSize,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  void setZoom(ArchiveZoom zoom) {
    state = state.copyWith(zoom: zoom);
  }
}

final archiveControllerProvider =
    StateNotifierProvider<ArchiveController, ArchiveState>(
      (ref) => ArchiveController(ref.watch(databaseServiceProvider)),
    );

final activeWordCountProvider = Provider<int>(
  (ref) => ref.watch(
    journalControllerProvider.select((state) => state.entry?.wordCount ?? 0),
  ),
);
