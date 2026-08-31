import 'package:sotto/models/journal_entry.dart';
import 'package:sotto/services/ai_service.dart';
import 'package:sotto/services/database_service.dart';

class FakeDatabaseService extends DatabaseService {
  final Map<String, JournalEntry> entries = {};
  final Map<String, DailyCheckIn> checkIns = {};

  @override
  Future<JournalEntry?> latestDraft() async {
    final drafts =
        entries.values
            .where((entry) => entry.status == EntryStatus.draft)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return drafts.firstOrNull;
  }

  @override
  Future<DailyCheckIn?> checkInForDate(String dateKey) async =>
      checkIns[dateKey];

  @override
  Future<void> saveEntry(JournalEntry entry) async {
    entries[entry.id] = entry;
  }

  @override
  Future<void> saveCheckIn(DailyCheckIn checkIn) async {
    checkIns[checkIn.dateKey] = checkIn;
  }

  @override
  Future<List<JournalEntry>> archivePage({
    ArchiveCursor? cursor,
    int limit = 30,
  }) async {
    final closedEntries =
        entries.values
            .where(
              (entry) =>
                  entry.status == EntryStatus.closed && entry.closedAt != null,
            )
            .toList()
          ..sort((a, b) {
            final timeOrder = b.closedAt!.compareTo(a.closedAt!);
            return timeOrder != 0 ? timeOrder : b.id.compareTo(a.id);
          });
    final filtered = cursor == null
        ? closedEntries
        : closedEntries.where((entry) {
            final timeOrder = entry.closedAt!.compareTo(cursor.closedAt);
            return timeOrder < 0 ||
                (timeOrder == 0 && entry.id.compareTo(cursor.entryId) < 0);
          }).toList();
    return filtered.take(limit).toList();
  }

  @override
  Future<List<DailyCheckIn>> checkInsBetween(
    String startDateKey,
    String endDateKey,
  ) async => checkIns.values
      .where(
        (checkIn) =>
            checkIn.dateKey.compareTo(startDateKey) >= 0 &&
            checkIn.dateKey.compareTo(endDateKey) <= 0,
      )
      .toList();

  @override
  Future<void> close() async {}
}

class FixedReflectionService implements ReflectionService {
  const FixedReflectionService({
    this.question = 'What deserves more of your attention?',
  });

  final String question;

  @override
  Future<ReflectionResult> reflectOn(String text) async =>
      ReflectionResult(question: question, isDemo: false);
}
