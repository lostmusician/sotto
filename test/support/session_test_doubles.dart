import 'package:sotto/models/journal_entry.dart';
import 'package:sotto/services/database_service.dart';

class FakeDatabaseService extends DatabaseService {
  final Map<String, JournalDay> days = {};
  final Map<String, DayEntry> entries = {};
  final Map<String, DailyCheckIn> checkIns = {};
  EveningPreference preference = const EveningPreference();
  bool failEntrySaves = false;
  int saveDayEntryCallCount = 0;

  @override
  Future<JournalDay> ensureDay(String dateKey, {DateTime? now}) async =>
      days.putIfAbsent(dateKey, () => JournalDay.empty(dateKey, now: now));

  @override
  Future<JournalDay?> journalDay(String dateKey) async => days[dateKey];

  @override
  Future<void> saveDay(JournalDay day) async {
    days[day.dateKey] = day;
  }

  @override
  Future<List<DayEntry>> entriesForDay(String dateKey) async {
    final values =
        entries.values.where((entry) => entry.dateKey == dateKey).toList()
          ..sort((a, b) {
            if (a.type != b.type) return a.type == DayEntryType.daily ? -1 : 1;
            return b.createdAt.compareTo(a.createdAt);
          });
    return values;
  }

  @override
  Future<void> saveDayEntry(DayEntry entry) async {
    saveDayEntryCallCount += 1;
    if (failEntrySaves) throw StateError('entry save failed');
    await ensureDay(entry.dateKey, now: entry.createdAt);
    if (entry.type == DayEntryType.daily &&
        entries.values.any(
          (existing) =>
              existing.id != entry.id &&
              existing.dateKey == entry.dateKey &&
              existing.type == DayEntryType.daily,
        )) {
      throw StateError('daily entry already exists');
    }
    entries[entry.id] = entry;
  }

  @override
  Future<void> deleteDayEntry(String id) async {
    entries.remove(id);
  }

  @override
  Future<DailyCheckIn?> checkInForDate(String dateKey) async =>
      checkIns[dateKey];

  @override
  Future<void> saveCheckIn(DailyCheckIn checkIn) async {
    await ensureDay(checkIn.dateKey, now: checkIn.createdAt);
    checkIns[checkIn.dateKey] = checkIn;
  }

  @override
  Future<BinderDay> loadBinderDay(String dateKey, {bool create = false}) async {
    final day = create
        ? await ensureDay(dateKey)
        : days[dateKey] ?? JournalDay.empty(dateKey);
    return BinderDay(
      day: day,
      entries: await entriesForDay(dateKey),
      checkIn: checkIns[dateKey],
    );
  }

  @override
  Future<List<BinderDay>> binderPage({
    BinderCursor? cursor,
    int limit = 20,
  }) async {
    final keys = days.keys.where((key) {
      if (cursor != null && key.compareTo(cursor.dateKey) >= 0) return false;
      final day = days[key]!;
      final hasEntry = entries.values.any(
        (entry) => entry.dateKey == key && !entry.isEmpty,
      );
      return day.gratitude.trim().isNotEmpty ||
          hasEntry ||
          checkIns.containsKey(key);
    }).toList()..sort((a, b) => b.compareTo(a));
    return Future.wait(keys.take(limit).map(loadBinderDay));
  }

  @override
  Future<EveningPreference> eveningPreference() async => preference;

  @override
  Future<void> saveEveningPreference(EveningPreference value) async {
    preference = value;
  }

  @override
  Future<void> close() async {}
}
