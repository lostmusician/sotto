import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../services/ai_service.dart';
import '../services/database_service.dart';

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final service = DatabaseService();
  ref.onDispose(service.close);
  return service;
});
final aiServiceProvider = Provider<AiService>((ref) => AiService());

class JournalSessionState {
  const JournalSessionState({
    required this.entry,
    this.isLoading = false,
    this.error,
    this.lastReflectionWasDemo = false,
  });
  final JournalEntry entry;
  final bool isLoading;
  final Object? error;
  final bool lastReflectionWasDemo;

  JournalSessionState copyWith({
    JournalEntry? entry,
    bool? isLoading,
    Object? error,
    bool clearError = false,
    bool? lastReflectionWasDemo,
  }) => JournalSessionState(
    entry: entry ?? this.entry,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : error ?? this.error,
    lastReflectionWasDemo: lastReflectionWasDemo ?? this.lastReflectionWasDemo,
  );
}

class JournalController extends StateNotifier<JournalSessionState> {
  JournalController(this._database)
    : super(JournalSessionState(entry: JournalEntry.empty()));
  final DatabaseService _database;

  Future<void> initialize() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final entry = await _database.latestEntry() ?? state.entry;
      state = state.copyWith(entry: entry, isLoading: false);
      if (entry.content.isEmpty) await _database.saveEntry(entry);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  void updateContent(String content) {
    state = state.copyWith(
      entry: state.entry.copyWith(
        content: content,
        updatedAt: DateTime.now().toUtc(),
      ),
      clearError: true,
    );
  }

  Future<void> save() async {
    try {
      await _database.saveEntry(state.entry);
    } catch (error) {
      state = state.copyWith(error: error);
    }
  }

  Future<void> addReflection(ReflectionResult result) async {
    final entry = state.entry;
    final annotation = AiAnnotation.create(
      entryId: entry.id,
      question: result.question,
      anchorOffset: entry.content.length,
    );
    state = state.copyWith(
      entry: entry.copyWith(
        annotations: [...entry.annotations, annotation],
        updatedAt: DateTime.now().toUtc(),
      ),
      lastReflectionWasDemo: result.isDemo,
      clearError: true,
    );
    await save();
  }
}

final journalControllerProvider =
    StateNotifierProvider<JournalController, JournalSessionState>(
      (ref) => JournalController(ref.watch(databaseServiceProvider)),
    );
final activeWordCountProvider = Provider<int>(
  (ref) => ref.watch(
    journalControllerProvider.select((state) => state.entry.wordCount),
  ),
);
final aiTypingProvider = StateProvider<bool>((ref) => false);
