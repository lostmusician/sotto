import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum EntryStatus { draft, closed }

enum SessionPhase { arrival, writing, reflection, archive }

enum ArchiveZoom { entries, weeks, months }

class DailyCheckIn {
  const DailyCheckIn({
    required this.dateKey,
    required this.moodAngle,
    required this.moodIntensity,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DailyCheckIn.today({
    required double moodAngle,
    required double moodIntensity,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    return DailyCheckIn(
      dateKey: localDateKey(timestamp),
      moodAngle: moodAngle.clamp(0, 1),
      moodIntensity: moodIntensity.clamp(0, 1),
      createdAt: timestamp.toUtc(),
      updatedAt: timestamp.toUtc(),
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

class AiAnnotation {
  const AiAnnotation({
    required this.id,
    required this.entryId,
    required this.question,
    required this.anchorOffset,
    required this.createdAt,
  });

  factory AiAnnotation.create({
    required String entryId,
    required String question,
    required int anchorOffset,
  }) => AiAnnotation(
    id: _uuid.v4(),
    entryId: entryId,
    question: question,
    anchorOffset: anchorOffset,
    createdAt: DateTime.now().toUtc(),
  );

  factory AiAnnotation.fromMap(Map<String, Object?> map) => AiAnnotation(
    id: map['id']! as String,
    entryId: map['entry_id']! as String,
    question: map['question']! as String,
    anchorOffset: map['anchor_offset']! as int,
    createdAt: DateTime.parse(map['created_at']! as String),
  );

  final String id;
  final String entryId;
  final String question;
  final int anchorOffset;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'entry_id': entryId,
    'question': question,
    'anchor_offset': anchorOffset,
    'created_at': createdAt.toIso8601String(),
  };
}

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.targetWordCount,
    this.status = EntryStatus.draft,
    this.closedAt,
    this.reflectionQuestion,
    this.reflectionReply = '',
    this.annotations = const [],
  });

  factory JournalEntry.empty({DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return JournalEntry(
      id: _uuid.v4(),
      title: 'Untitled entry',
      content: '',
      createdAt: timestamp,
      updatedAt: timestamp,
      targetWordCount: 500,
    );
  }

  factory JournalEntry.fromMap(
    Map<String, Object?> map, {
    List<AiAnnotation> annotations = const [],
  }) => JournalEntry(
    id: map['id']! as String,
    title: map['title']! as String,
    content: map['content']! as String,
    createdAt: DateTime.parse(map['created_at']! as String),
    updatedAt: DateTime.parse(map['updated_at']! as String),
    targetWordCount: map['target_word_count']! as int,
    status: EntryStatus.values.byName(
      (map['status'] as String?) ?? EntryStatus.draft.name,
    ),
    closedAt: map['closed_at'] == null
        ? null
        : DateTime.parse(map['closed_at']! as String),
    reflectionQuestion: map['reflection_question'] as String?,
    reflectionReply: (map['reflection_reply'] as String?) ?? '',
    annotations: annotations,
  );

  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int targetWordCount;
  final EntryStatus status;
  final DateTime? closedAt;
  final String? reflectionQuestion;
  final String reflectionReply;
  final List<AiAnnotation> annotations;

  int get wordCount {
    final trimmed = content.trim();
    return trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length;
  }

  double get progress =>
      targetWordCount <= 0 ? 0 : (wordCount / targetWordCount).clamp(0, 1);

  JournalEntry copyWith({
    String? title,
    String? content,
    DateTime? updatedAt,
    int? targetWordCount,
    EntryStatus? status,
    DateTime? closedAt,
    bool clearClosedAt = false,
    String? reflectionQuestion,
    bool clearReflectionQuestion = false,
    String? reflectionReply,
    List<AiAnnotation>? annotations,
  }) => JournalEntry(
    id: id,
    title: title ?? this.title,
    content: content ?? this.content,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    targetWordCount: targetWordCount ?? this.targetWordCount,
    status: status ?? this.status,
    closedAt: clearClosedAt ? null : closedAt ?? this.closedAt,
    reflectionQuestion: clearReflectionQuestion
        ? null
        : reflectionQuestion ?? this.reflectionQuestion,
    reflectionReply: reflectionReply ?? this.reflectionReply,
    annotations: annotations ?? this.annotations,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'target_word_count': targetWordCount,
    'status': status.name,
    'closed_at': closedAt?.toIso8601String(),
    'reflection_question': reflectionQuestion,
    'reflection_reply': reflectionReply,
  };
}

class ArchiveCursor {
  const ArchiveCursor({required this.closedAt, required this.entryId});

  final DateTime closedAt;
  final String entryId;
}

String localDateKey(DateTime date) {
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
