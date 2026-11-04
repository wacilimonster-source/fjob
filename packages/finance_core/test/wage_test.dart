import 'package:finance_core/finance_core.dart';
import 'package:test/test.dart';

void main() {
  final calendar = BusinessCalendar.shanghai;
  final calculator = WageCalculator(calendar);

  final schedule = ScheduleVersion(
    id: 'schedule-1',
    timezone: 'Asia/Shanghai',
    week: WeekTemplate.standardOffice(),
    effectiveFromUtc: DateTime.utc(2026, 1, 1),
  );
  final schedules = <String, ScheduleVersion>{'schedule-1': schedule};

  SalaryVersion salary(String monthly, {String id = 'salary-1', DateTime? from}) =>
      SalaryVersion(
        id: id,
        monthlyNetCny: Rational.parse(monthly),
        effectiveFromUtc: from ?? DateTime.utc(2026, 1, 1),
        scheduleVersionId: 'schedule-1',
      );

  WageResult accrualForDay({
    required DateTime atUtc,
    List<SalaryVersion>? versions,
    List<ScheduleOverride> overrides = const [],
  }) {
    final date = calendar.dateOf(atUtc);
    return calculator.accrual(
      fromUtc: calendar.startOfDayUtc(date),
      toUtc: atUtc,
      salaryVersions: versions ?? [salary('12000')],
      schedules: schedules,
      overrides: overrides,
      nowUtc: atUtc,
    );
  }

  group('CALC-WAGE', () {
    test('AC-CALC-01 full month conserves the configured salary', () {
      final date = LocalDate(2026, 11, 1);
      final result = calculator.accrual(
        fromUtc: calendar.startOfMonthUtc(LocalDate(2026, 11, 1)),
        toUtc: calendar.endOfMonthUtc(LocalDate(2026, 11, 1)),
        salaryVersions: [salary('12000')],
        schedules: schedules,
        overrides: const [],
        nowUtc: DateTime.utc(2026, 11, 30, 15, 59),
      );
      expect(result.amount, Rational.parse('12000'));
      expect(result.paidSecondsInWindow, 604800);
      expect(result.status, WageStatus.computed);
    });

    test('AC-CALC-02 14:36 Shanghai equals the reference case', () {
      final result = accrualForDay(atUtc: DateTime.utc(2026, 11, 4, 6, 36));
      expect(result.amount!.toDisplayString(), '328.57');
      expect(result.paidSecondsInWindow, 16560);
      expect(result.monthStats!.paidSeconds, 604800);
      expect(result.monthStats!.paidDays, 21);
    });

    test('AC-CALC-02 lunch holds the wage constant', () {
      final before = accrualForDay(atUtc: DateTime.utc(2026, 11, 4, 4)); // 12:00
      final during = accrualForDay(atUtc: DateTime.utc(2026, 11, 4, 4, 59));
      expect(before.amount, during.amount);
      expect(during.paidSecondsInWindow, 10800);
    });

    test('AC-CALC-02 wage does not grow outside the shift', () {
      final end = accrualForDay(atUtc: DateTime.utc(2026, 11, 4, 10)); // 18:00
      final late = accrualForDay(atUtc: DateTime.utc(2026, 11, 4, 14));
      expect(end.amount, late.amount);
      expect(late.amount!.toDisplayString(), '571.43');
    });

    test('zero salary with an empty schedule is allowed', () {
      final emptySchedule = ScheduleVersion(
        id: 'empty',
        timezone: 'Asia/Shanghai',
        week: WeekTemplate(List<List<ShiftTemplate>>.filled(7, const [])),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );
      final result = calculator.accrual(
        fromUtc: DateTime.utc(2026, 11, 4),
        toUtc: DateTime.utc(2026, 11, 4, 8),
        salaryVersions: [
          SalaryVersion(
            id: 'zero',
            monthlyNetCny: Rational.zero,
            effectiveFromUtc: DateTime.utc(2026, 1, 1),
            scheduleVersionId: 'empty',
          ),
        ],
        schedules: {'empty': emptySchedule},
        overrides: const [],
      );
      expect(result.status, WageStatus.computed);
      expect(result.amount, Rational.zero);
      expect(result.paidSecondsInWindow, 0);
    });

    test('positive salary without paid seconds reports invalidSchedule', () {
      final emptySchedule = ScheduleVersion(
        id: 'empty',
        timezone: 'Asia/Shanghai',
        week: WeekTemplate(List<List<ShiftTemplate>>.filled(7, const [])),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );
      final result = calculator.accrual(
        fromUtc: calendar.startOfDayUtc(LocalDate(2026, 11, 4)),
        toUtc: DateTime.utc(2026, 11, 4, 8),
        salaryVersions: [
          SalaryVersion(
            id: 'salary',
            monthlyNetCny: Rational.parse('12000'),
            effectiveFromUtc: DateTime.utc(2026, 1, 1),
            scheduleVersionId: 'empty',
          ),
        ],
        schedules: {'empty': emptySchedule},
        overrides: const [],
      );
      expect(result.status, WageStatus.invalidSchedule);
      expect(result.amount, isNull);
    });

    test('a mid-month salary change is segmented per version', () {
      final result = calculator.accrual(
        fromUtc: calendar.startOfMonthUtc(LocalDate(2026, 11, 1)),
        toUtc: calendar.endOfMonthUtc(LocalDate(2026, 11, 1)),
        salaryVersions: [
          SalaryVersion(
            id: 'salary-a',
            monthlyNetCny: Rational.parse('12000'),
            effectiveFromUtc: DateTime.utc(2026, 1, 1),
            effectiveToUtc: DateTime.utc(2026, 11, 16, 16), // Nov 17 00:00
            scheduleVersionId: 'schedule-1',
          ),
          SalaryVersion(
            id: 'salary-b',
            monthlyNetCny: Rational.parse('24000'),
            effectiveFromUtc: DateTime.utc(2026, 11, 16, 16),
            scheduleVersionId: 'schedule-1',
          ),
        ],
        schedules: schedules,
        overrides: const [],
      );
      expect(result.isSegmented, isTrue);
      expect(result.slices, hasLength(2));
      expect(result.slices.first.month, LocalDate(2026, 11, 1));
      expect(result.paidSecondsInWindow, 604800);
      // Each segment keeps its own full-month denominator, so the month total
      // is no longer the configured salary; the UI labels it an estimate.
      expect(result.amount, isNot(Rational.parse('18000')));
      final expected = Rational.parse('12000') *
              Rational.fromInt(result.slices.first.paidSeconds) /
              Rational.fromInt(604800) +
          Rational.parse('24000') *
              Rational.fromInt(result.slices.last.paidSeconds) /
              Rational.fromInt(604800);
      expect(result.amount, expected);
    });

    test('AC-CALC-03 a cross-month night shift uses both month rates', () {
      final nightSchedule = ScheduleVersion(
        id: 'night',
        timezone: 'Asia/Shanghai',
        week: WeekTemplate(<List<ShiftTemplate>>[
          for (var index = 0; index < 7; index++)
            const <ShiftTemplate>[
              ShiftTemplate(startMinute: 22 * 60, endMinute: 30 * 60),
            ],
        ]),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );
      final result = calculator.accrual(
        fromUtc: DateTime.utc(2027, 1, 31, 14), // 22:00 Shanghai
        toUtc: DateTime.utc(2027, 1, 31, 22), // Feb 1 06:00 Shanghai
        salaryVersions: [
          SalaryVersion(
            id: 'night-salary',
            monthlyNetCny: Rational.parse('12000'),
            effectiveFromUtc: DateTime.utc(2026, 1, 1),
            scheduleVersionId: 'night',
          ),
        ],
        schedules: {'night': nightSchedule},
        overrides: const [],
      );
      expect(result.slices, hasLength(2));
      final january = result.slices.firstWhere(
        (slice) => slice.month == LocalDate(2027, 1, 1),
      );
      final february = result.slices.firstWhere(
        (slice) => slice.month == LocalDate(2027, 2, 1),
      );
      expect(january.paidSeconds, 7200);
      expect(february.paidSeconds, 21600);
      expect(january.monthlyPaidSeconds, 31 * 8 * 3600);
      expect(february.monthlyPaidSeconds, 28 * 8 * 3600);
    });

    test('a rest-day override lowers the denominator immediately', () {
      final result = calculator.accrual(
        fromUtc: calendar.startOfMonthUtc(LocalDate(2026, 11, 1)),
        toUtc: calendar.endOfMonthUtc(LocalDate(2026, 11, 1)),
        salaryVersions: [salary('12000')],
        schedules: schedules,
        overrides: [
          const ScheduleOverride(
            localDate: LocalDate(2026, 11, 5),
            paidIntervals: <LocalInterval>[],
            reason: 'leave',
          ),
        ],
        nowUtc: DateTime.utc(2026, 11, 30, 15, 59),
      );
      expect(result.paidSecondsInWindow, 604800 - 28800);
      expect(result.monthStats!.paidSeconds, 604800 - 28800);
      expect(result.monthStats!.paidDays, 20);
    });
  });
}
