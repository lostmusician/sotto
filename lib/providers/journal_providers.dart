import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../services/database_service.dart';
import '../services/bible_service.dart';
import '../services/embedding_service.dart';
import '../services/keyphrase_service.dart';
import '../services/organization_service.dart';

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final service = DatabaseService();
  ref.onDispose(service.close);
  return service;
});

final keyphraseExtractorProvider = Provider<KeyphraseExtractor>(
  (ref) => const RakeKeyphraseExtractor(),
);

final taggingServiceProvider = Provider<TaggingService>(
  (ref) => TaggingService(
    ref.watch(databaseServiceProvider),
    ref.watch(keyphraseExtractorProvider),
    ref.watch(embeddingServiceProvider),
  ),
);

final relationshipServiceProvider = Provider<RelationshipService>(
  (ref) => RelationshipService(
    ref.watch(databaseServiceProvider),
    ref.watch(embeddingServiceProvider),
  ),
);

final embeddingServiceProvider = Provider<EmbeddingService>((ref) {
  final service = ArcticEmbeddingService();
  ref.onDispose(service.close);
  return service;
});

final youVersionBibleProvider = Provider<YouVersionBibleProvider>((ref) {
  final provider = YouVersionBibleProvider();
  ref.onDispose(provider.close);
  return provider;
});

class JournalAppState {
  const JournalAppState({
    this.phase = AppPhase.loading,
    this.selectedDateKey,
    this.day,
    this.entries = const [],
    this.selectedEntryId,
    this.checkIn,
    this.eveningPreference = const EveningPreference(),
    this.showMoodReminder = false,
    this.smartOrganizationEnabled = false,
    this.christianModeEnabled = false,
    this.preferredBibleId = 'NIV',
    this.isLoading = false,
    this.error,
  });

  final AppPhase phase;
  final String? selectedDateKey;
  final JournalDay? day;
  final List<DayEntry> entries;
  final String? selectedEntryId;
  final DailyCheckIn? checkIn;
  final EveningPreference eveningPreference;
  final bool showMoodReminder;
  final bool smartOrganizationEnabled;
  final bool christianModeEnabled;
  final String preferredBibleId;
  final bool isLoading;
  final Object? error;

  DayEntry? get selectedEntry =>
      entries.where((entry) => entry.id == selectedEntryId).firstOrNull;
  DayEntry? get dailyEntry =>
      entries.where((entry) => entry.type == DayEntryType.daily).firstOrNull;
  bool get journalComplete => dailyEntry?.content.trim().isNotEmpty ?? false;
  bool get dayComplete => journalComplete && checkIn != null;

  JournalAppState copyWith({
    AppPhase? phase,
    String? selectedDateKey,
    JournalDay? day,
    List<DayEntry>? entries,
    String? selectedEntryId,
    bool clearSelectedEntry = false,
    DailyCheckIn? checkIn,
    bool clearCheckIn = false,
    EveningPreference? eveningPreference,
    bool? showMoodReminder,
    bool? smartOrganizationEnabled,
    bool? christianModeEnabled,
    String? preferredBibleId,
    bool? isLoading,
    Object? error,
    bool clearError = false,
  }) => JournalAppState(
    phase: phase ?? this.phase,
    selectedDateKey: selectedDateKey ?? this.selectedDateKey,
    day: day ?? this.day,
    entries: entries ?? this.entries,
    selectedEntryId: clearSelectedEntry
        ? null
        : selectedEntryId ?? this.selectedEntryId,
    checkIn: clearCheckIn ? null : checkIn ?? this.checkIn,
    eveningPreference: eveningPreference ?? this.eveningPreference,
    showMoodReminder: showMoodReminder ?? this.showMoodReminder,
    smartOrganizationEnabled:
        smartOrganizationEnabled ?? this.smartOrganizationEnabled,
    christianModeEnabled: christianModeEnabled ?? this.christianModeEnabled,
    preferredBibleId: preferredBibleId ?? this.preferredBibleId,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : error ?? this.error,
  );
}

class JournalController extends StateNotifier<JournalAppState> {
  JournalController(this._database) : super(const JournalAppState());

  final DatabaseService _database;
  bool _continueToJournalAfterMood = false;

  Future<void> initialize({DateTime? now}) async {
    final timestamp = now ?? DateTime.now();
    final dateKey = localDateKey(timestamp);
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final preferences = await Future.wait<Object>([
        _database.eveningPreference(),
        _database.smartOrganizationEnabled(),
        _database.christianModeEnabled(),
        _database.preferredBibleId(),
      ]);
      final preference = preferences[0] as EveningPreference;
      final binderDay = await _database.loadBinderDay(dateKey);
      state = state.copyWith(
        selectedDateKey: dateKey,
        day: binderDay.day,
        entries: binderDay.entries,
        checkIn: binderDay.checkIn,
        clearCheckIn: binderDay.checkIn == null,
        eveningPreference: preference,
        smartOrganizationEnabled: preferences[1] as bool,
        christianModeEnabled: preferences[2] as bool,
        preferredBibleId: preferences[3] as String,
        isLoading: false,
      );
      if (binderDay.isComplete) {
        state = state.copyWith(phase: AppPhase.binder, showMoodReminder: false);
      } else if (preference.isEvening(timestamp) && binderDay.checkIn == null) {
        await openMood(dateKey, continueToJournal: true);
      } else if (!binderDay.journalComplete) {
        await openDay(dateKey, now: timestamp);
      } else {
        state = state.copyWith(
          phase: AppPhase.binder,
          showMoodReminder: binderDay.checkIn == null,
        );
      }
    } catch (error) {
      state = state.copyWith(
        phase: AppPhase.binder,
        isLoading: false,
        error: error,
      );
    }
  }

  Future<void> openDay(
    String dateKey, {
    bool createAdditional = false,
    DateTime? now,
  }) async {
    if (!await saveCurrentEntry()) return;
    final binderDay = await _database.loadBinderDay(dateKey, create: true);
    var entries = binderDay.entries;
    var daily = entries
        .where((entry) => entry.type == DayEntryType.daily)
        .firstOrNull;
    if (daily == null) {
      daily = DayEntry.empty(
        dateKey: dateKey,
        type: DayEntryType.daily,
        now: now,
      );
      await _database.saveDayEntry(daily);
      entries = [daily, ...entries];
    }
    state = state.copyWith(
      phase: AppPhase.journal,
      selectedDateKey: dateKey,
      day: binderDay.day,
      entries: entries,
      selectedEntryId: daily.id,
      checkIn: binderDay.checkIn,
      clearCheckIn: binderDay.checkIn == null,
      showMoodReminder: false,
      clearError: true,
    );
    if (createAdditional) await addEntry(now: now);
  }

  Future<void> selectEntry(String entryId) async {
    if (state.phase != AppPhase.journal || entryId == state.selectedEntryId) {
      return;
    }
    if (!await saveCurrentEntry()) return;
    if (state.entries.any((entry) => entry.id == entryId)) {
      state = state.copyWith(selectedEntryId: entryId);
    }
  }

  Future<void> addEntry({DateTime? now}) async {
    final dateKey = state.selectedDateKey;
    if (state.phase != AppPhase.journal || dateKey == null) return;
    if (!await saveCurrentEntry()) return;
    final entry = DayEntry.empty(
      dateKey: dateKey,
      type: DayEntryType.additional,
      now: now,
    );
    state = state.copyWith(
      entries: [
        state.dailyEntry!,
        entry,
        ...state.entries.where((e) => e.type == DayEntryType.additional),
      ],
      selectedEntryId: entry.id,
      clearError: true,
    );
  }

  Future<void> addQuietTime({DateTime? now}) async {
    final dateKey = state.selectedDateKey;
    if (state.phase != AppPhase.journal || dateKey == null) return;
    if (!await saveCurrentEntry()) return;
    final entry = DayEntry.empty(
      dateKey: dateKey,
      type: DayEntryType.additional,
      purpose: EntryPurpose.quietTime,
      now: now,
    ).copyWith(title: 'Quiet Time');
    state = state.copyWith(
      entries: [
        state.dailyEntry!,
        entry,
        ...state.entries.where((e) => e.type == DayEntryType.additional),
      ],
      selectedEntryId: entry.id,
      clearError: true,
    );
  }

  void updateEntry({String? title, String? content, DateTime? now}) {
    final selected = state.selectedEntry;
    if (state.phase != AppPhase.journal || selected == null) return;
    final updated = selected.copyWith(
      title: title,
      content: content,
      updatedAt: (now ?? DateTime.now()).toUtc(),
    );
    state = state.copyWith(
      entries: [
        for (final entry in state.entries)
          if (entry.id == updated.id) updated else entry,
      ],
      clearError: true,
    );
  }

  void updateGratitude(String gratitude, {DateTime? now}) {
    if (state.phase != AppPhase.journal || state.day == null) return;
    state = state.copyWith(
      day: state.day!.copyWith(
        gratitude: gratitude,
        updatedAt: (now ?? DateTime.now()).toUtc(),
      ),
      clearError: true,
    );
  }

  Future<bool> saveCurrentEntry() async {
    final entry = state.selectedEntry;
    if (entry == null) return true;
    try {
      if (entry.type == DayEntryType.additional && entry.isEmpty) {
        await _database.deleteDayEntry(entry.id);
        state = state.copyWith(
          entries: state.entries.where((item) => item.id != entry.id).toList(),
          selectedEntryId: state.dailyEntry?.id,
        );
      } else {
        await _database.saveDayEntry(entry);
      }
      return true;
    } catch (error) {
      state = state.copyWith(error: error);
      return false;
    }
  }

  Future<bool> saveGratitude() async {
    final day = state.day;
    if (day == null) return true;
    try {
      await _database.saveDay(day);
      return true;
    } catch (error) {
      state = state.copyWith(error: error);
      return false;
    }
  }

  Future<void> finishEditing({DateTime? now}) async {
    if (!await saveCurrentEntry()) return;
    if (!await saveGratitude()) return;
    final timestamp = now ?? DateTime.now();
    final todayKey = localDateKey(timestamp);
    if (state.selectedDateKey == todayKey &&
        state.eveningPreference.isEvening(timestamp) &&
        state.checkIn == null) {
      await openMood(todayKey);
    } else {
      state = state.copyWith(
        phase: AppPhase.binder,
        showMoodReminder:
            state.selectedDateKey == todayKey && state.checkIn == null,
      );
    }
  }

  Future<void> openMood(
    String dateKey, {
    DateTime? now,
    bool continueToJournal = false,
  }) async {
    if (!await saveCurrentEntry()) return;
    if (!await saveGratitude()) return;
    _continueToJournalAfterMood = continueToJournal;
    final binderDay = await _database.loadBinderDay(dateKey, create: true);
    state = state.copyWith(
      phase: AppPhase.mood,
      selectedDateKey: dateKey,
      day: binderDay.day,
      entries: binderDay.entries,
      checkIn: binderDay.checkIn,
      clearCheckIn: binderDay.checkIn == null,
      showMoodReminder: false,
      clearError: true,
    );
  }

  void updateMood(double angle, double intensity, {DateTime? now}) {
    final dateKey = state.selectedDateKey;
    if (state.phase != AppPhase.mood || dateKey == null) return;
    final timestamp = now ?? DateTime.now();
    final checkIn = state.checkIn == null
        ? DailyCheckIn.forDate(
            dateKey: dateKey,
            moodAngle: angle,
            moodIntensity: intensity,
            now: timestamp,
          )
        : state.checkIn!.copyWith(
            moodAngle: angle,
            moodIntensity: intensity,
            updatedAt: timestamp.toUtc(),
          );
    state = state.copyWith(checkIn: checkIn, clearError: true);
  }

  Future<bool> saveMood() async {
    final checkIn = state.checkIn;
    if (checkIn == null) return true;
    try {
      await _database.saveCheckIn(checkIn);
      return true;
    } catch (error) {
      state = state.copyWith(error: error);
      return false;
    }
  }

  Future<void> finishMood({DateTime? now}) async {
    if (!await saveMood()) return;
    final timestamp = now ?? DateTime.now();
    final dateKey = state.selectedDateKey ?? localDateKey(timestamp);
    final day = await _database.loadBinderDay(dateKey);
    if (_continueToJournalAfterMood && !day.journalComplete) {
      _continueToJournalAfterMood = false;
      await openDay(dateKey, now: timestamp);
    } else {
      _continueToJournalAfterMood = false;
      state = state.copyWith(phase: AppPhase.binder, showMoodReminder: false);
    }
  }

  Future<void> openBinder() async {
    if (!await saveCurrentEntry()) return;
    if (!await saveGratitude()) return;
    if (!await saveMood()) return;
    state = state.copyWith(phase: AppPhase.binder);
  }

  Future<void> updateEveningPreference(int minutes) async {
    final preference = EveningPreference(
      minutesAfterMidnight: minutes.clamp(0, 1439),
    );
    state = state.copyWith(eveningPreference: preference);
    await _database.saveEveningPreference(preference);
  }

  Future<void> setSmartOrganizationEnabled(bool enabled) async {
    await _database.saveSetting(
      DatabaseService.smartOrganizationSettingKey,
      '$enabled',
    );
    state = state.copyWith(smartOrganizationEnabled: enabled);
  }

  Future<void> setChristianModeEnabled(bool enabled) async {
    await _database.saveSetting(
      DatabaseService.christianModeSettingKey,
      '$enabled',
    );
    state = state.copyWith(christianModeEnabled: enabled);
  }

  Future<void> setPreferredBibleId(String bibleId) async {
    await _database.saveSetting(
      DatabaseService.preferredBibleSettingKey,
      bibleId,
    );
    state = state.copyWith(preferredBibleId: bibleId);
  }
}

final journalControllerProvider =
    StateNotifierProvider<JournalController, JournalAppState>(
      (ref) => JournalController(ref.watch(databaseServiceProvider)),
    );

class BinderState {
  const BinderState({
    this.zoom = BinderZoom.days,
    this.days = const [],
    this.selectedDateKey,
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  final BinderZoom zoom;
  final List<BinderDay> days;
  final String? selectedDateKey;
  final bool isLoading;
  final bool hasMore;
  final Object? error;

  BinderState copyWith({
    BinderZoom? zoom,
    List<BinderDay>? days,
    String? selectedDateKey,
    bool? isLoading,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) => BinderState(
    zoom: zoom ?? this.zoom,
    days: days ?? this.days,
    selectedDateKey: selectedDateKey ?? this.selectedDateKey,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : error ?? this.error,
  );
}

class BinderController extends StateNotifier<BinderState> {
  BinderController(this._database) : super(const BinderState());

  static const pageSize = 20;
  final DatabaseService _database;

  Future<void> refresh({String? anchorDateKey}) async {
    state = state.copyWith(
      days: const [],
      selectedDateKey: anchorDateKey ?? state.selectedDateKey,
      hasMore: true,
      clearError: true,
    );
    await loadMore();
    if (state.selectedDateKey == null && state.days.isNotEmpty) {
      state = state.copyWith(selectedDateKey: state.days.first.day.dateKey);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final page = await _database.binderPage(
        cursor: state.days.lastOrNull == null
            ? null
            : BinderCursor(state.days.last.day.dateKey),
        limit: pageSize,
      );
      state = state.copyWith(
        days: [...state.days, ...page],
        isLoading: false,
        hasMore: page.length == pageSize,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  void selectDate(String dateKey) {
    state = state.copyWith(selectedDateKey: dateKey);
  }

  void setZoom(BinderZoom zoom) {
    state = state.copyWith(zoom: zoom);
  }
}

final binderControllerProvider =
    StateNotifierProvider<BinderController, BinderState>(
      (ref) => BinderController(ref.watch(databaseServiceProvider)),
    );

class DiscoveryState {
  const DiscoveryState({
    this.tags = const [],
    this.results = const [],
    this.entryTags = const {},
    this.relationships = const {},
    this.isLoading = false,
    this.indexedEntries = 0,
    this.totalEntries = 0,
    this.error,
  });

  final List<JournalTag> tags;
  final List<JournalSearchResult> results;
  final Map<String, List<EntryTag>> entryTags;
  final Map<String, List<EntryRelationship>> relationships;
  final bool isLoading;
  final int indexedEntries;
  final int totalEntries;
  final Object? error;

  DiscoveryState copyWith({
    List<JournalTag>? tags,
    List<JournalSearchResult>? results,
    Map<String, List<EntryTag>>? entryTags,
    Map<String, List<EntryRelationship>>? relationships,
    bool? isLoading,
    int? indexedEntries,
    int? totalEntries,
    Object? error,
    bool clearError = false,
  }) => DiscoveryState(
    tags: tags ?? this.tags,
    results: results ?? this.results,
    entryTags: entryTags ?? this.entryTags,
    relationships: relationships ?? this.relationships,
    isLoading: isLoading ?? this.isLoading,
    indexedEntries: indexedEntries ?? this.indexedEntries,
    totalEntries: totalEntries ?? this.totalEntries,
    error: clearError ? null : error ?? this.error,
  );
}

class DiscoveryController extends StateNotifier<DiscoveryState> {
  DiscoveryController(this._database, this._tagging, this._relationships)
    : super(const DiscoveryState());

  final DatabaseService _database;
  final TaggingService _tagging;
  final RelationshipService _relationships;
  bool _cancelled = false;

  Future<void> loadForDays(List<BinderDay> days) async {
    try {
      final tags = await _database.allTags();
      final entryTags = Map<String, List<EntryTag>>.from(state.entryTags);
      final relationships = Map<String, List<EntryRelationship>>.from(
        state.relationships,
      );
      for (final day in days) {
        for (final entry in day.entries) {
          entryTags[entry.id] = await _database.tagsForEntry(entry.id);
          relationships[entry.id] = await _database.relationshipsForEntry(
            entry.id,
          );
        }
      }
      state = state.copyWith(
        tags: tags,
        entryTags: entryTags,
        relationships: relationships,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(error: error);
    }
  }

  Future<void> search(JournalSearchQuery query) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await _database.searchEntries(query);
      state = state.copyWith(results: results, isLoading: false);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> addManualTag(String entryId, String name) async {
    final tag = await _database.ensureTag(name);
    await _database.attachTag(
      entryId: entryId,
      tag: tag,
      source: EntryTagSource.manual,
    );
    await _reloadEntry(entryId);
  }

  Future<void> removeTag(String entryId, String tagId) async {
    await _database.detachTag(entryId, tagId);
    await _reloadEntry(entryId);
  }

  Future<void> renameTag(String tagId, String name) async {
    await _tagging.renameTag(tagId, name);
    await _reloadKnownTags();
  }

  Future<void> mergeTags(String sourceTagId, String targetTagId) async {
    await _tagging.mergeTags(sourceTagId, targetTagId);
    await _reloadKnownTags();
  }

  Future<void> _reloadKnownTags() async {
    final entryTags = <String, List<EntryTag>>{};
    for (final entryId in state.entryTags.keys) {
      entryTags[entryId] = await _database.tagsForEntry(entryId);
    }
    state = state.copyWith(
      tags: await _database.allTags(),
      entryTags: entryTags,
    );
  }

  Future<void> organizeEntry(DayEntry entry) async {
    await _tagging.organizeEntry(entry);
    await _relationships.rebuildForEntry(entry.id);
    await _reloadEntry(entry.id);
  }

  Future<void> organizeBackCatalog() async {
    _cancelled = false;
    state = state.copyWith(
      isLoading: true,
      indexedEntries: 0,
      clearError: true,
    );
    try {
      await _tagging.organizeBackCatalog(
        isCancelled: () => _cancelled,
        onProgress: (completed, total) {
          state = state.copyWith(
            indexedEntries: completed,
            totalEntries: total,
          );
        },
      );
      if (!_cancelled) {
        await _relationships.rebuildAll(isCancelled: () => _cancelled);
      }
      state = state.copyWith(tags: await _database.allTags(), isLoading: false);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  void cancelIndexing() => _cancelled = true;

  Future<void> _reloadEntry(String entryId) async {
    state = state.copyWith(
      tags: await _database.allTags(),
      entryTags: {
        ...state.entryTags,
        entryId: await _database.tagsForEntry(entryId),
      },
      relationships: {
        ...state.relationships,
        entryId: await _database.relationshipsForEntry(entryId),
      },
    );
  }
}

final discoveryControllerProvider =
    StateNotifierProvider<DiscoveryController, DiscoveryState>(
      (ref) => DiscoveryController(
        ref.watch(databaseServiceProvider),
        ref.watch(taggingServiceProvider),
        ref.watch(relationshipServiceProvider),
      ),
    );
