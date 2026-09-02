import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum AppPhase { loading, mood, journal, binder }

enum BinderZoom { days, weeks, months }

enum DayEntryType { daily, additional }

class EveningPreference {
  const EveningPreference({this.minutesAfterMidnight = 18 * 60});

  final int minutesAfterMidnight;
  int get hour => minutesAfterMidnight ~/ 60;
  int get minute => minutesAfterMidnight % 60;

  bool isEvening(DateTime localTime) =>
      localTime.hour * 60 + localTime.minute >= minutesAfterMidnight;
}

class DailyCheckIn {
  const DailyCheckIn({
    required this.dateKey,
    required this.moodAngle,
    required this.moodIntensity,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DailyCheckIn.forDate({
    required String dateKey,
    required double moodAngle,
    required double moodIntensity,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return DailyCheckIn(
      dateKey: dateKey,
      moodAngle: moodAngle.clamp(0, 1),
      moodIntensity: moodIntensity.clamp(0, 1),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  factory DailyCheckIn.fromMap(Map<String, Object?> map) => DailyCheckIn(
    dateKey: map['date_key']! as String,
    moodAngle: (map['mood_angle']! as num).toDouble(),
    moodIntensity: (map['mood_intensity']! as num).toDouble(),
    createdAt: DateTime.parse(map['created_at']! as String),
    updatedAt: DateTime.parse(map['updated_at']! as String),
  );

  final String dateKey;
  final double moodAngle;
  final double moodIntensity;
  final DateTime createdAt;
  final DateTime updatedAt;

  DailyCheckIn copyWith({
    double? moodAngle,
    double? moodIntensity,
    DateTime? updatedAt,
  }) => DailyCheckIn(
    dateKey: dateKey,
    moodAngle: (moodAngle ?? this.moodAngle).clamp(0, 1),
    moodIntensity: (moodIntensity ?? this.moodIntensity).clamp(0, 1),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'date_key': dateKey,
    'mood_angle': moodAngle,
    'mood_intensity': moodIntensity,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

class JournalDay {
  const JournalDay({
    required this.dateKey,
    required this.gratitude,
    required this.createdAt,
    required this.updatedAt,
  });

  factory JournalDay.empty(String dateKey, {DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return JournalDay(
      dateKey: dateKey,
      gratitude: '',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  factory JournalDay.fromMap(Map<String, Object?> map) => JournalDay(
    dateKey: map['date_key']! as String,
    gratitude: (map['gratitude'] as String?) ?? '',
    createdAt: DateTime.parse(map['created_at']! as String),
    updatedAt: DateTime.parse(map['updated_at']! as String),
  );

  final String dateKey;
  final String gratitude;
  final DateTime createdAt;
  final DateTime updatedAt;

  JournalDay copyWith({String? gratitude, DateTime? updatedAt}) => JournalDay(
    dateKey: dateKey,
    gratitude: gratitude ?? this.gratitude,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'date_key': dateKey,
    'gratitude': gratitude,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

class DayEntry {
  const DayEntry({
    required this.id,
    required this.dateKey,
    required this.type,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DayEntry.empty({
    required String dateKey,
    required DayEntryType type,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return DayEntry(
      id: _uuid.v4(),
      dateKey: dateKey,
      type: type,
      title: '',
      content: '',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  factory DayEntry.fromMap(Map<String, Object?> map) => DayEntry(
    id: map['id']! as String,
    dateKey: map['date_key']! as String,
    type: DayEntryType.values.byName(map['entry_type']! as String),
    title: (map['title'] as String?) ?? '',
    content: (map['content'] as String?) ?? '',
    createdAt: DateTime.parse(map['created_at']! as String),
    updatedAt: DateTime.parse(map['updated_at']! as String),
  );

  final String id;
  final String dateKey;
  final DayEntryType type;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isEmpty => title.trim().isEmpty && content.trim().isEmpty;
  int get wordCount {
    final value = content.trim();
    return value.isEmpty ? 0 : value.split(RegExp(r'\s+')).length;
  }

  DayEntry copyWith({String? title, String? content, DateTime? updatedAt}) =>
      DayEntry(
        id: id,
        dateKey: dateKey,
        type: type,
        title: title ?? this.title,
        content: content ?? this.content,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'date_key': dateKey,
    'entry_type': type.name,
    'title': title,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

class BinderDay {
  const BinderDay({
    required this.day,
    required this.entries,
    required this.checkIn,
  });

  final JournalDay day;
  final List<DayEntry> entries;
  final DailyCheckIn? checkIn;

  DayEntry? get dailyEntry =>
      entries.where((entry) => entry.type == DayEntryType.daily).firstOrNull;
  List<DayEntry> get additionalEntries =>
      entries.where((entry) => entry.type == DayEntryType.additional).toList();
  bool get journalComplete => dailyEntry?.content.trim().isNotEmpty ?? false;
  bool get isComplete => journalComplete && checkIn != null;
}

class BinderCursor {
  const BinderCursor(this.dateKey);
  final String dateKey;
}

String localDateKey(DateTime date) {
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

DateTime localDateFromKey(String dateKey) {
  final parts = dateKey.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}
