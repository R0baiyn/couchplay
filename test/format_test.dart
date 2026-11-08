import 'package:couchplay/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatTime', () {
    expect(formatTime(const Duration(seconds: 9)), '0:09');
    expect(formatTime(const Duration(minutes: 5, seconds: 9)), '5:09');
    expect(
      formatTime(const Duration(hours: 1, minutes: 50, seconds: 30)),
      '1:50:30',
    );
  });

  test('formatRuntime', () {
    expect(formatRuntime(const Duration(minutes: 45)), '45 min');
    expect(formatRuntime(const Duration(minutes: 60)), '1 h 00');
    expect(formatRuntime(const Duration(hours: 2, minutes: 5)), '2 h 05');
  });

  test('formatDate, en heure locale', () {
    expect(formatDate(DateTime(2026, 3, 7, 12)), '07/03/2026');
  });
}
