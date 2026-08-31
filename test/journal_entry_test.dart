import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/models/journal_entry.dart';

void main() {
  test('word count ignores surrounding and repeated whitespace', () {
    final entry = JournalEntry.empty().copyWith(
      content: '  The quiet   room\nheld five words. ',
    );
    expect(entry.wordCount, 6);
  });

  test('progress is capped at one', () {
    final entry = JournalEntry.empty().copyWith(
      content: List.filled(600, 'word').join(' '),
    );
    expect(entry.progress, 1);
  });
}
