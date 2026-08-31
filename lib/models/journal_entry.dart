import 'package:uuid/uuid.dart';

const _uuid = Uuid();

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
  }) {
    return AiAnnotation(
      id: _uuid.v4(),
      entryId: entryId,
      question: question,
      anchorOffset: anchorOffset,
      createdAt: DateTime.now().toUtc(),
    );
  }

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
    this.annotations = const [],
  });

  factory JournalEntry.empty() {
    final now = DateTime.now().toUtc();
    return JournalEntry(
      id: _uuid.v4(),
      title: 'Untitled entry',
      content: '',
      createdAt: now,
      updatedAt: now,
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
    annotations: annotations,
  );

  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int targetWordCount;
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
    List<AiAnnotation>? annotations,
  }) => JournalEntry(
    id: id,
    title: title ?? this.title,
    content: content ?? this.content,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    targetWordCount: targetWordCount ?? this.targetWordCount,
    annotations: annotations ?? this.annotations,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'target_word_count': targetWordCount,
  };
}
