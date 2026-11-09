/// SCN-01: complete-shift presence across midnight, late shifts and rest days.
///
/// Presence follows the *whole* shift (docs/09 §7.1); wage math keeps using
/// the natural-day timeline, so these tests only assert phase and sessions.
import 'package:finance_core/finance_core.dart';
import 'package:test/test.dart';

void main() {
  final calendar = BusinessCalendar.shanghai;
  final expander = ScheduleExpander((_) => calendar);

  ScheduleVersion officeSchedule() => ScheduleVersion(
        id: 'office',
        timezone: 'Asia/Shanghai',
        week: WeekTemplate.standardOffice(),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );

  // 22:00 → 06:00 next day, every day.
  ScheduleVersion nightSchedule({required String id}) => ScheduleVersion(
        id: id,
        timezone: 'Asia/Shanghai',
        week: WeekTemplate(<List<ShiftTemplate>>[
          for (var index = 0; index < 7; index++)
            const <ShiftTemplate>[
              ShiftTemplate(startMinute: 22 * 60, endMinute: 30 * 60),
            ],
        ]),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );

  // 22:00 → 02:00 next day, every day.
  ScheduleVersion shortNightSchedule() => ScheduleVersion(
        id: 'short-night',
        timezone: 'Asia/Shanghai',
        week: WeekTemplate(<List<ShiftTemplate>>[
          for (var index = 0; index < 7; index++)
            const <ShiftTemplate>[
              ShiftTemplate(startMinute: 22 * 60, endMinute: 26 * 60),
            ],
        ]),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );

  WorkSessionContext contextAt({
    required ScheduleVersion version,
    required DateTime utc,
    List<ScheduleOverride> overrides = const [],
  }) {
    return expander.workSessionContext(
      version: version,
      overrides: overrides,
      nowUtc: utc,
    );
  }

  group('standard office shift (09:00–18:00 with lunch)', () {
    final version = officeSchedule();

    test('working inside paid time, breakTime inside lunch', () {
      expect(
        contextAt(version: version, utc: DateTime.utc(2026, 11, 4, 2, 0)).phase,
        DayPhase.working,
      );
      expect(
        contextAt(version: version, utc: DateTime.utc(2026, 11, 4, 4, 30)).phase,
        DayPhase.breakTime,
      );
    });

    test('beforeShift before the shift, afterShift after it', () {
      expect(
        contextAt(version: version, utc: DateTime.utc(2026, 11, 4, 0, 30)).phase,
        DayPhase.beforeShift,
      );
      expect(
        contextAt(version: version, utc: DateTime.utc(2026, 11, 4, 11, 0)).phase,
        DayPhase.afterShift,
      );
    });

    test('lunch is a break inside one session, not two shifts', () {
      final context = contextAt(
        version: version,
        utc: DateTime.utc(2026, 11, 4, 4, 30),
      );
      expect(context.activeSession, isNotNull);
      expect(context.activeSession!.unpaidWindows, hasLength(1));
      expect(context.activeSession!.paidSegments, hasLength(2));
      expect(
        context.activeSession!.key,
        contains('office|2026-11-04'),
      );
    });

    test('a weekend is restDay even though Friday ended yesterday', () {
      // Saturday 2026-11-07 noon.
      final context = contextAt(
        version: version,
        utc: DateTime.utc(2026, 11, 7, 4, 0),
      );
      expect(context.phase, DayPhase.restDay);
      expect(context.lastEndedSession, isNotNull);
      expect(context.nextSession, isNotNull);
    });

    test('late evening after the shift stays afterShift, not restDay', () {
      expect(
        contextAt(version: version, utc: DateTime.utc(2026, 11, 4, 15, 0)).phase,
        DayPhase.afterShift,
      );
    });

    test('exact boundaries are closed-open: 09:00 starts, 18:00 ends', () {
      final start = contextAt(
        version: version,
        utc: DateTime.utc(2026, 11, 4, 1), // 09:00 CST
      );
      expect(start.phase, DayPhase.working);
      expect(start.activeSession, isNotNull);

      final lastSecond = contextAt(
        version: version,
        utc: DateTime.utc(2026, 11, 4, 9, 59, 59, 999), // 17:59:59.999 CST
      );
      expect(lastSecond.phase, DayPhase.working);
      expect(lastSecond.activeSession, isNotNull);

      final end = contextAt(
        version: version,
        utc: DateTime.utc(2026, 11, 4, 10), // 18:00:00 CST exactly
      );
      expect(end.phase, DayPhase.afterShift);
      expect(end.activeSession, isNull);
      expect(end.lastEndedSession, isNotNull);
      expect(
        end.lastEndedSession!.endUtc,
        DateTime.utc(2026, 11, 4, 10),
      );
      expect(end.nextSession, isNotNull);
      expect(
        end.nextSession!.startUtc,
        DateTime.utc(2026, 11, 5, 1), // 11-05 09:00 CST
      );
    });

    test('a rest override removes presence for that day', () {
      final context = contextAt(
        version: version,
        utc: DateTime.utc(2026, 11, 5, 2, 0),
        overrides: const [
          ScheduleOverride(
            localDate: LocalDate(2026, 11, 5),
            paidIntervals: <LocalInterval>[],
            reason: 'leave',
          ),
        ],
      );
      expect(context.phase, DayPhase.restDay);
    });
  });

  group('cross-midnight shifts', () {
    test('22:00–02:00 stays working after midnight', () {
      final version = shortNightSchedule();
      expect(
        contextAt(version: version, utc: DateTime.utc(2026, 11, 4, 17, 0)).phase,
        DayPhase.working,
      );
      // 00:30 next day is still the same shift, now on statistics date 11-05.
      final afterMidnight = contextAt(
        version: version,
        utc: DateTime.utc(2026, 11, 4, 16, 30),
      );
      expect(afterMidnight.phase, DayPhase.working);
      expect(
        calendar.dateOf(DateTime.utc(2026, 11, 4, 16, 30)),
        LocalDate(2026, 11, 5),
      );
    });

    test('02:00 end leaves an empty desk until the next evening shift', () {
      final version = shortNightSchedule();
      // 03:00: shift ended an hour ago; next shift starts 22:00 today.
      final context = contextAt(
        version: version,
        utc: DateTime.utc(2026, 11, 4, 19, 0),
      );
      expect(context.phase, DayPhase.afterShift);
      expect(context.lastEndedSession!.shiftDate, LocalDate(2026, 11, 4));
      expect(context.nextSession!.shiftDate, LocalDate(2026, 11, 5));
      expect(context.activeSession, isNull);
    });

    test('22:00–06:00 counts the full session across months', () {
      final version = nightSchedule(id: 'night');
      // 2026-11-30 23:30 → shift [22:00 11-30, 06:00 12-01].
      final context = contextAt(
        version: version,
        utc: DateTime.utc(2026, 11, 30, 15, 30),
      );
      expect(context.phase, DayPhase.working);
      expect(context.activeSession!.shiftDate, LocalDate(2026, 11, 30));
      expect(
        context.activeSession!.endUtc,
        calendar.instantAt(const LocalDate(2026, 12, 1), 6 * 60),
      );

      // 07:00 on 12-01: afterShift; the shift truly ended today.
      final morning = contextAt(
        version: version,
        utc: DateTime.utc(2026, 12, 1, 0 /* 08:00 CST */, 0),
      );
      expect(morning.phase, DayPhase.afterShift);
      expect(morning.lastEndedSession!.shiftDate, LocalDate(2026, 11, 30));
    });

    test('a night shift ends exactly at 06:00, not a tick later', () {
      final version = nightSchedule(id: 'night');
      final lastSecond = contextAt(
        version: version,
        utc: DateTime.utc(2026, 11, 30, 21, 59, 59, 999), // 05:59:59.999 CST
      );
      expect(lastSecond.phase, DayPhase.working);
      expect(
        lastSecond.activeSession!.endUtc,
        DateTime.utc(2026, 11, 30, 22), // 12-01 06:00 CST
      );

      final end = contextAt(
        version: version,
        utc: DateTime.utc(2026, 11, 30, 22), // 12-01 06:00 CST exactly
      );
      expect(end.phase, DayPhase.afterShift);
      expect(end.activeSession, isNull);
      expect(end.lastEndedSession!.shiftDate, LocalDate(2026, 11, 30));
      expect(end.nextSession!.shiftDate, LocalDate(2026, 12, 1));
    });

    test('wage timeline stays clipped to the natural day (untouched)', () {
      final version = nightSchedule(id: 'night');
      // The presence window must not change paid-second accounting.
      final timeline = expander.dayTimeline(
        version: version,
        overrides: const [],
        date: const LocalDate(2026, 11, 30),
      );
      // 11-30 sees the tail of the 11-29 shift (6h) plus its own 22:00 start
      // (2h) — 8 paid hours on the natural day, exactly as before.
      expect(timeline.paidSecondsTotal, 8 * 3600);
      final month = expander.monthlyPaidSeconds(
        version: version,
        overrides: const [],
        anchor: const LocalDate(2026, 11, 1),
      );
      // 30 days × 8h: the 22:00–06:00 shift splits evenly around midnight.
      expect(month, 30 * 8 * 3600);
    });
  });

  group('session identity', () {
    test('key stays stable across the midnight the shift crosses', () {
      final version = nightSchedule(id: 'night');
      final before = contextAt(
        version: version,
        utc: DateTime.utc(2026, 11, 30, 15, 59),
      );
      final after = contextAt(
        version: version,
        utc: DateTime.utc(2026, 11, 30, 16, 1),
      );
      expect(before.activeSession!.key, after.activeSession!.key);
    });
  });

  group('大小周 alternation', () {
    test('big week Saturday is working, small week Saturday is restDay', () {
      final small = WeekTemplate.standardOffice();
      final big = WeekTemplate(<List<ShiftTemplate>>[
        for (var index = 0; index < 7; index++)
          index < 6
              ? <ShiftTemplate>[
                  const ShiftTemplate(
                    startMinute: 9 * 60,
                    endMinute: 18 * 60,
                    breaks: <BreakTemplate>[
                      BreakTemplate(startMinute: 12 * 60, endMinute: 13 * 60),
                    ],
                  ),
                ]
              : const <ShiftTemplate>[],
      ]);
      final version = ScheduleVersion(
        id: 'alternating',
        timezone: 'Asia/Shanghai',
        week: small,
        alternation: WeekAlternation(
          smallWeek: small,
          bigWeek: big,
          anchorMonday: const LocalDate(2026, 11, 2),
        ),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );

      // 2026-11-07 is the Saturday of the anchor (big) week.
      expect(
        contextAt(version: version, utc: DateTime.utc(2026, 11, 7, 2, 0)).phase,
        DayPhase.working,
      );
      // 2026-11-14 is the Saturday of the small week.
      expect(
        contextAt(version: version, utc: DateTime.utc(2026, 11, 14, 2, 0)).phase,
        DayPhase.restDay,
      );
    });
  });
}
