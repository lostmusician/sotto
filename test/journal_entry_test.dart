import 'package:flutter_test/flutter_test.dart';
import 'package:meno/models/journal_entry.dart';

void main() {
  test('day entry counts words and identifies empty content', () {
    final entry = DayEntry.empty(
      dateKey: '2026-09-01',
      type: DayEntryType.additional,
    ).copyWith(content: '  one   two\nthree  ');

    expect(entry.wordCount, 3);
    expect(entry.isEmpty, isFalse);
  });

  test('evening preference switches at the configured local minute', () {
    const preference = EveningPreference(minutesAfterMidnight: 18 * 60);

    expect(preference.isEvening(DateTime(2026, 9, 1, 17, 59)), isFalse);
    expect(preference.isEvening(DateTime(2026, 9, 1, 18)), isTrue);
  });
}
