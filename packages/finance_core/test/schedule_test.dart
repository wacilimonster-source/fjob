import 'package:finance_core/finance_core.dart';
import 'package:test/test.dart';

void main() {
  final calendar = BusinessCalendar.shanghai;
  final expander = ScheduleExpander((_) => calendar);

  ScheduleVersion officeSchedule({String id = 'schedule-1'}) => ScheduleVersion(
        id: id,
        timezone: 'Asia/Shanghai',
        week: WeekTemplate.standardOffice(),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );

  ScheduleVersion nightSchedule({String id = 'night'}) => ScheduleVersion(
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

  group('week template', () {
    test('standard office has 21 paid days in 2026-11', () {
      final schedule = officeSchedule();
      final paid = expander.monthlyPaidSeconds(
        version: schedule,
        overrides: const [],
        anchor: LocalDate(2026, 11, 1),
      );
      expect(paid, 604800);
      expect(
        expander.monthlyPaidDays(
          version: schedule,
          overrides: const [],
          anchor: LocalDate(2026, 11, 1),
        ),
        21,
      );
    });

    test('cross-midnight shift is split by local month', () {
      final schedule = nightSchedule();
      final january = expander.monthlyPaidSeconds(
        version: schedule,
        overrides: const [],
        anchor: LocalDate(2027, 1, 1),
      );
      final february = expander.monthlyPaidSeconds(
        version: schedule,
        overrides: const [],
        anchor: LocalDate(2027, 2, 1),
      );
      // 31 days x 8h, with the previous month's spill balancing the next.
      expect(january, 31 * 8 * 3600);
      expect(february, 28 * 8 * 3600);

      final segments = expander.expand(
        version: schedule,
        overrides: const [],
        fromUtc: DateTime.utc(2027, 1, 31, 14), // 22:00 Shanghai
        toUtc: DateTime.utc(2027, 1, 31, 22), // 06:00 next day
      );
      expect(segments, hasLength(1));
      expect(segments.single.seconds, 8 * 3600);
      expect(segments.single.shiftDate, LocalDate(2027, 1, 31));
    });

    test('a rest-day override removes that day from the denominator', () {
      final schedule = officeSchedule();
      final paid = expander.monthlyPaidSeconds(
        version: schedule,
        overrides: [
          const ScheduleOverride(
            localDate: LocalDate(2026, 11, 5),
            paidIntervals: <LocalInterval>[],
            reason: 'leave',
          ),
        ],
        anchor: LocalDate(2026, 11, 1),
      );
      expect(paid, 604800 - 8 * 3600);
    });

    test('a half-day override replaces the template for that date', () {
      final schedule = officeSchedule();
      final timeline = expander.dayTimeline(
        version: schedule,
        overrides: [
          const ScheduleOverride(
            localDate: LocalDate(2026, 11, 4),
            paidIntervals: <LocalInterval>[
              LocalInterval(startMinute: 540, endMinute: 720),
            ],
            reason: 'halfDay',
          ),
        ],
        date: LocalDate(2026, 11, 4),
      );
      expect(timeline.paidSecondsTotal, 3 * 3600);
      expect(timeline.unpaidWindows, isEmpty);
    });
  });

  group('validation', () {
    test('overlapping shifts are rejected', () {
      expect(
        () => WeekTemplate(<List<ShiftTemplate>>[
          const <ShiftTemplate>[
            ShiftTemplate(startMinute: 540, endMinute: 720),
            ShiftTemplate(startMinute: 660, endMinute: 840),
          ],
          ...List<List<ShiftTemplate>>.filled(6, const []),
        ]),
        throwsA(isA<ScheduleValidationError>()),
      );
    });

    test('a break outside the shift is rejected', () {
      expect(
        () => const ShiftTemplate(
          startMinute: 540,
          endMinute: 1080,
          breaks: <BreakTemplate>[
            BreakTemplate(startMinute: 480, endMinute: 540),
          ],
        ).validate(),
        throwsA(isA<ScheduleValidationError>()),
      );
    });

    test('a shift fully consumed by breaks is rejected', () {
      expect(
        () => const ShiftTemplate(
          startMinute: 540,
          endMinute: 600,
          breaks: <BreakTemplate>[
            BreakTemplate(startMinute: 540, endMinute: 600),
          ],
        ).validate(),
        throwsA(isA<ScheduleValidationError>()),
      );
    });
  });

  group('day timeline', () {
    test('break windows and elapsed pay follow the template', () {
      final schedule = officeSchedule();
      final timeline = expander.dayTimeline(
        version: schedule,
        overrides: const [],
        date: LocalDate(2026, 11, 4),
      );
      expect(timeline.paidSegments, hasLength(2));
      expect(timeline.unpaidWindows, hasLength(1));
      expect(
        timeline.unpaidWindows.single.startUtc,
        DateTime.utc(2026, 11, 4, 4), // 12:00 Shanghai
      );
      expect(
        timeline.paidSecondsElapsed(DateTime.utc(2026, 11, 4, 6, 36)),
        16560,
      );
      expect(
        timeline.paidSecondsElapsed(DateTime.utc(2026, 11, 4, 5)), // 13:00
        10800,
      );
      expect(
        timeline.paidSecondsElapsed(DateTime.utc(2026, 11, 4, 4, 59)),
        10800,
      );
    });

    test('version validity clips the timeline', () {
      final schedule = ScheduleVersion(
        id: 'later',
        timezone: 'Asia/Shanghai',
        week: WeekTemplate.standardOffice(),
        effectiveFromUtc: DateTime.utc(2026, 11, 4, 5), // 13:00 Shanghai
      );
      final timeline = expander.dayTimeline(
        version: schedule,
        overrides: const [],
        date: LocalDate(2026, 11, 4),
      );
      expect(timeline.paidSegments, hasLength(1));
      expect(timeline.shiftStartUtc, DateTime.utc(2026, 11, 4, 5));
    });
  });

  group('大小周', () {
    WeekTemplate bigWeek() {
      final base = WeekTemplate.standardOffice().byWeekday;
      return WeekTemplate([
        for (var index = 0; index < 7; index++)
          if (index == 5)
            <ShiftTemplate>[
              const ShiftTemplate(
                startMinute: 9 * 60,
                endMinute: 18 * 60,
                breaks: [BreakTemplate(startMinute: 12 * 60, endMinute: 13 * 60)],
              ),
            ]
          else
            List<ShiftTemplate>.from(base[index]),
      ]);
    }

    test('alternates big and small weeks and counts a month correctly', () {
      final pattern = WeekAlternation(
        smallWeek: WeekTemplate.standardOffice(),
        bigWeek: bigWeek(),
        anchorMonday: LocalDate(2026, 11, 2),
      );
      expect(pattern.isBigWeek(LocalDate(2026, 11, 2)), isTrue);
      expect(pattern.isBigWeek(LocalDate(2026, 11, 9)), isFalse);
      expect(pattern.isBigWeek(LocalDate(2026, 11, 16)), isTrue);
      expect(pattern.isBigWeek(LocalDate(2026, 11, 7)), isTrue);

      final schedule = ScheduleVersion(
        id: 'bs',
        timezone: 'Asia/Shanghai',
        week: pattern.smallWeek,
        alternation: pattern,
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );
      expect(
        expander.monthlyPaidDays(
          version: schedule,
          overrides: const [],
          anchor: LocalDate(2026, 11, 1),
        ),
        23,
      );
      expect(
        expander.monthlyPaidSeconds(
          version: schedule,
          overrides: const [],
          anchor: LocalDate(2026, 11, 1),
        ),
        23 * 8 * 3600,
      );
    });

    test('a month can contain three extra Saturdays', () {
      final pattern = WeekAlternation(
        smallWeek: WeekTemplate.standardOffice(),
        bigWeek: bigWeek(),
        anchorMonday: LocalDate(2026, 4, 27),
      );
      final schedule = ScheduleVersion(
        id: 'bs-may',
        timezone: 'Asia/Shanghai',
        week: pattern.smallWeek,
        alternation: pattern,
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );
      expect(
        expander.monthlyPaidDays(
          version: schedule,
          overrides: const [],
          anchor: LocalDate(2026, 5, 1),
        ),
        24,
      );
    });
  });
}
