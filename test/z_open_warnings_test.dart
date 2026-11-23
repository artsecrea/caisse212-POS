import 'package:flutter_test/flutter_test.dart';
import 'package:caisse212/services/z_rules.dart';

void main() {
  Set<ZOpenWarning> at(
    DateTime now, {
    DateTime? startedAt,
    String zDay = '2026-10-20',
    int startHour = 5,
    int? maxOpenHours,
    String? cutoff,
  }) => zOpenWarnings(
    now: now,
    startedAt: startedAt ?? DateTime(2026, 10, 20, 9),
    zDay: zDay,
    startHour: startHour,
    maxOpenHours: maxOpenHours,
    cutoff: cutoff,
  );

  group('open too long', () {
    test('warns at the limit, not before', () {
      expect(at(DateTime(2026, 10, 21, 0, 59), maxOpenHours: 16), isEmpty);
      expect(at(DateTime(2026, 10, 21, 1), maxOpenHours: 16), {
        ZOpenWarning.openTooLong,
      });
    });

    test('null or zero hours is off', () {
      expect(at(DateTime(2026, 10, 25)), isEmpty);
      expect(at(DateTime(2026, 10, 25), maxOpenHours: 0), isEmpty);
    });
  });

  group('past cutoff', () {
    test('04:00 is the morning after the business day', () {
      expect(at(DateTime(2026, 10, 20, 23), cutoff: '04:00'), isEmpty);
      expect(at(DateTime(2026, 10, 21, 3, 59), cutoff: '04:00'), isEmpty);
      expect(at(DateTime(2026, 10, 21, 4), cutoff: '04:00'), {
        ZOpenWarning.pastCutoff,
      });
    });

    test('a time after the day start is that same day', () {
      expect(at(DateTime(2026, 10, 20, 22, 59), cutoff: '23:00'), isEmpty);
      expect(at(DateTime(2026, 10, 20, 23), cutoff: '23:00'), {
        ZOpenWarning.pastCutoff,
      });
    });

    test('a Z opened after midnight belongs to the previous day', () {
      // Opened 02:00 on the 21st with the day starting at 05:00: still the
      // 20th's Z, so 04:00 that morning is its cutoff.
      expect(
        at(
          DateTime(2026, 10, 21, 4, 30),
          startedAt: DateTime(2026, 10, 21, 2),
          cutoff: '04:00',
        ),
        {ZOpenWarning.pastCutoff},
      );
    });

    test('a Z opened after the cutoff hour does not warn at once', () {
      // Opened 05:00 with a 04:00 cutoff and the day starting at 00:00 or
      // 05:00: the cutoff was already behind it — it is due tomorrow 04:00.
      for (final startHour in [0, 5]) {
        expect(
          at(
            DateTime(2026, 10, 20, 5, 1),
            startedAt: DateTime(2026, 10, 20, 5),
            startHour: startHour,
            cutoff: '04:00',
          ),
          isEmpty,
        );
        expect(
          at(
            DateTime(2026, 10, 21, 3, 59),
            startedAt: DateTime(2026, 10, 20, 5),
            startHour: startHour,
            cutoff: '04:00',
          ),
          isEmpty,
        );
        expect(
          at(
            DateTime(2026, 10, 21, 4),
            startedAt: DateTime(2026, 10, 20, 5),
            startHour: startHour,
            cutoff: '04:00',
          ),
          {ZOpenWarning.pastCutoff},
        );
      }
    });

    test('a 16:00 cutoff warns once the Z stays open past 16:00', () {
      final opened = DateTime(2026, 10, 20, 17);
      expect(
        at(DateTime(2026, 10, 20, 23), startedAt: opened, cutoff: '16:00'),
        isEmpty,
      );
      expect(
        at(DateTime(2026, 10, 21, 16), startedAt: opened, cutoff: '16:00'),
        {ZOpenWarning.pastCutoff},
      );
    });

    test('null or malformed cutoff is off', () {
      expect(at(DateTime(2026, 10, 22)), isEmpty);
      expect(at(DateTime(2026, 10, 22), cutoff: '4h'), isEmpty);
    });
  });

  test('both warnings together', () {
    expect(at(DateTime(2026, 10, 21, 6), maxOpenHours: 16, cutoff: '04:00'), {
      ZOpenWarning.openTooLong,
      ZOpenWarning.pastCutoff,
    });
  });
}
