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

  test('formatSize', () {
    expect(formatSize(0), '0 o');
    expect(formatSize(999), '999 o');
    expect(formatSize(1500), '1,5 Ko');
    expect(formatSize(350000000), '350 Mo');
    expect(formatSize(1400000000), '1,4 Go');
    expect(formatSize(12000000000), '12 Go');
    expect(formatSize(2000000000), '2 Go');
  });
}
