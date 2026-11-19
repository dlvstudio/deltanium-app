import 'package:deltanium_app/utils/server_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zoneless server time is read as UTC', () {
    final dt = ServerTime.parse('2026-11-18T09:25:24.383916');
    expect(dt.isUtc, isFalse); // returned in local time
    expect(dt.toUtc(), DateTime.utc(2026, 11, 18, 9, 25, 24, 383, 916));
  });

  test('times with a zone are kept', () {
    expect(ServerTime.parse('2026-11-18T09:25:24Z').toUtc(), DateTime.utc(2026, 11, 18, 9, 25, 24));
    expect(ServerTime.parse('2026-11-18T16:25:24+07:00').toUtc(), DateTime.utc(2026, 11, 18, 9, 25, 24));
  });

  test('date-only values are not shifted', () {
    final d = ServerTime.parse('2008-11-22');
    expect([d.year, d.month, d.day], [2008, 11, 22]);
  });

  test('UTC serialization round-trips', () {
    final dt = ServerTime.parse('2026-11-18T09:25:24');
    expect(ServerTime.parse(dt.toUtc().toIso8601String()), dt);
  });

  test('bad input', () {
    expect(ServerTime.tryParse(null), isNull);
    expect(ServerTime.tryParse(''), isNull);
    expect(ServerTime.tryParse('nope'), isNull);
  });
}
