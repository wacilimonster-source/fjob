/// HOME-DUAL-04..07: the pure time/balance display model.
///
/// All snapshots come from the real `DashboardCalculator`; only presentation
/// fields are overridden where a scenario is hard to produce through inputs
/// (a true zero total, stale quality). No widget is involved.
library;

import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/domain/ledger.dart';
import 'package:todayagain/features/dashboard/home_metrics_model.dart';

void main() {
  final calendar = BusinessCalendar.shanghai;
  final calculator = DashboardCalculator(calendar);

  final officeSchedule = ScheduleVersion(
    id: 'office',
    timezone: 'Asia/Shanghai',
    week: WeekTemplate.standardOffice(),
    effectiveFromUtc: DateTime.utc(2026, 1, 1),
  );

  SalaryVersion salary({String monthly = '12000'}) => SalaryVersion(
        id: 'salary-1',
        monthlyNetCny: Rational.parse(monthly),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
        scheduleVersionId: 'office',
      );

  Holding stock() => Holding(
        id: 'stock',
        instrumentId: 'CN.SZ.000001',
        quantity: Rational.parse('1000'),
        costPerUnit: Rational.parse('13'),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );

  Holding gold() => Holding(
        id: 'gold',
        instrumentId: 'GOLD.CNY_GRAM.AU9999',
        quantity: Rational.parse('20'),
        costPerUnit: Rational.parse('850'),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );

  HousingVersion housing() => HousingVersion(
        id: 'housing-1',
        mode: HousingMode.mortgage,
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );

  CarVersion car() => CarVersion(
        id: 'car-1',
        enabled: true,
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );

  MonthlyBill housingBill() => MonthlyBill(
        expenseId: 'housing-1',
        kind: ExpenseKind.housing,
        month: const LocalDate(2026, 11, 1),
        monthlyAmountCny: Rational.parse('4800'),
        principalCny: Rational.parse('2800'),
        status: BillStatus.confirmed,
      );

  MonthlyBill carBill() => MonthlyBill(
        expenseId: 'car-1',
        kind: ExpenseKind.car,
        month: const LocalDate(2026, 11, 1),
        monthlyAmountCny: Rational.parse('1800'),
        principalCny: Rational.parse('1500'),
        status: BillStatus.confirmed,
      );

  Map<String, Quote> quotesAt(DateTime at, {QuoteQuality quality = QuoteQuality.fixture}) => {
        'CN.SZ.000001': Quote(
          instrumentId: 'CN.SZ.000001',
          priceCny: Rational.parse('12.05'),
          baselineCny: Rational.parse('12.4'),
          quoteAtUtc: at,
          fetchedAtUtc: at,
          tradingDate: const LocalDate(2026, 11, 4),
          dayBasis: QuoteDayBasis.exchangeTradingDay,
          marketState: MarketState.open,
          quality: quality,
          source: 'fixture',
          sourceRevision: 1,
        ),
        'GOLD.CNY_GRAM.AU9999': Quote(
          instrumentId: 'GOLD.CNY_GRAM.AU9999',
          priceCny: Rational.parse('905'),
          baselineCny: Rational.parse('900'),
          quoteAtUtc: at,
          fetchedAtUtc: at,
          tradingDate: const LocalDate(2026, 11, 4),
          dayBasis: QuoteDayBasis.referenceTradingDay,
          marketState: MarketState.open,
          quality: quality,
          source: 'fixture',
          sourceRevision: 1,
        ),
      };

  MarketCalendar marketCalendarFor(LocalDate date) => MarketCalendar(
        {
          for (var day = 1; day <= date.daysInMonth; day++)
            LocalDate(date.year, date.month, day):
                LocalDate(date.year, date.month, day).weekday <= 5
                    ? MarketDayStatus.open
                    : MarketDayStatus.closed,
        },
        version: 'SSE@test',
      );

  CalculationInput input({
    DateTime? now,
    List<Holding> holdings = const [],
    Map<String, Quote>? quotes,
    List<HousingVersion> housingVersions = const [],
    List<CarVersion> carVersions = const [],
    List<MonthlyBill> bills = const [],
    List<SalaryVersion>? salaries,
    Map<String, ScheduleVersion>? schedules,
    ScheduleVersion? scheduleVersion,
  }) {
    final instant = now ?? DateTime.utc(2026, 11, 4, 6, 36);
    return CalculationInput(
      nowUtc: instant,
      ledgerRevision: 3,
      calendar: calendar,
      salaryVersions: salaries ?? [salary()],
      schedules: schedules ??
          {'office': scheduleVersion ?? officeSchedule},
      overrides: const [],
      holdings: holdings,
      quotes: quotes ?? quotesAt(instant),
      marketCalendar: marketCalendarFor(calendar.dateOf(instant)),
      housingVersions: housingVersions,
      carVersions: carVersions,
      bills: bills,
    );
  }

  DashboardSnapshot snapshot({
    DateTime? now,
    List<Holding> holdings = const [],
    Map<String, Quote>? quotes,
    List<HousingVersion> housingVersions = const [],
    List<CarVersion> carVersions = const [],
    List<MonthlyBill> bills = const [],
    List<SalaryVersion>? salaries,
    Map<String, ScheduleVersion>? schedules,
    ScheduleVersion? scheduleVersion,
  }) =>
      calculator.calculate(
        input(
          now: now,
          holdings: holdings,
          quotes: quotes,
          housingVersions: housingVersions,
          carVersions: carVersions,
          bills: bills,
          salaries: salaries,
          schedules: schedules,
          scheduleVersion: scheduleVersion,
        ),
      );

  DashboardSnapshot referenceNegative() => snapshot(
        holdings: [stock(), gold()],
        housingVersions: [housing()],
        carVersions: [car()],
        bills: [housingBill(), carBill()],
      );

  DashboardSnapshot withTotal(
    DashboardSnapshot base,
    Rational? total, {
    Completeness? completeness,
    QuoteQuality? quoteQuality,
    DateTime? quotesAsOf,
    List<DashboardNote>? notes,
    WorkSessionContext? workSession,
  }) =>
      DashboardSnapshot(
        computedAtUtc: base.computedAtUtc,
        ledgerRevision: base.ledgerRevision,
        statisticsDate: base.statisticsDate,
        timezone: base.timezone,
        wage: base.wage,
        stockDaily: base.stockDaily,
        goldDaily: base.goldDaily,
        fundDaily: base.fundDaily,
        housing: base.housing,
        car: base.car,
        principal: base.principal,
        interest: base.interest,
        rent: base.rent,
        total: total,
        completeness: completeness ?? base.completeness,
        wageSegmented: base.wageSegmented,
        breakdownComplete: base.breakdownComplete,
        estimate: base.estimate,
        phase: base.phase,
        timeline: base.timeline,
        monthStats: base.monthStats,
        wageDetail: base.wageDetail,
        assets: base.assets,
        housingDetail: base.housingDetail,
        carDetail: base.carDetail,
        quotesAsOf: quotesAsOf ?? base.quotesAsOf,
        quoteQuality: quoteQuality ?? base.quoteQuality,
        notes: notes ?? base.notes,
        dayLengthSeconds: base.dayLengthSeconds,
        monthDays: base.monthDays,
        workSession: workSession ?? base.workSession,
      );

  group('countdown formatting (HOME-DUAL-05)', () {
    test('ceil to whole seconds so the last second never reads 00:00:00', () {
      final target = DateTime.utc(2026, 11, 4, 10);
      expect(
        remainingCeilSeconds(
          target,
          DateTime.utc(2026, 11, 4, 9, 59, 59, 900),
        ),
        1,
      );
      expect(remainingCeilSeconds(target, target), 0);
      expect(
        remainingCeilSeconds(
          target,
          target.subtract(const Duration(microseconds: 1)),
        ),
        1,
      );
    });

    test('hours are not modulo 24 and are never truncated', () {
      expect(formatCountdown(3 * 3600 + 24 * 60), '03:24:00');
      expect(formatCountdown(1), '00:00:01');
      expect(formatCountdown(100 * 3600), '100:00:00');
      expect(formatCountdown(0), '00:00:00');
    });

    test('spoken countdown rounds up to whole minutes', () {
      expect(spokenCountdown(3 * 3600 + 24 * 60), '3 小时 24 分钟');
      expect(spokenCountdown(1), '1 分钟');
      expect(spokenCountdown(5 * 3600 + 30 * 60), '5 小时 30 分钟');
      expect(spokenCountdown(2 * 3600), '2 小时');
    });

    test('shift moments say today, 次日 or an explicit date', () {
      const date = LocalDate(2026, 11, 30);
      expect(
        formatShiftMoment(DateTime.utc(2026, 11, 30, 10), calendar, date),
        '18:00',
      );
      expect(
        formatShiftMoment(DateTime.utc(2026, 11, 30, 22), calendar, date),
        '次日 06:00',
      );
      expect(
        formatShiftMoment(DateTime.utc(2026, 12, 2, 1), calendar, date),
        '12月02日 09:00',
      );
    });
  });

  group('time card state matrix (HOME-DUAL-04)', () {
    test('working at 14:36 shows 03:24:00 and today\'s pay progress', () {
      final display = buildHomeTimeDisplay(
        snapshot: snapshot(),
        calendar: calendar,
      );
      expect(display.state, HomeTimeState.working);
      expect(display.label, '距离下班还有');
      expect(display.tag, '在岗中');
      expect(display.mainValue, '03:24:00');
      expect(display.detail, '预计 18:00 下班 · 按排班计薪');
      expect(display.showProgress, isTrue);
      expect(display.progressLabel, '今日计薪 4.6 / 8.0 小时');
      expect(display.progressSemantics, contains('完成 58%'));
      expect(display.semanticsLabel, '距离下班还有 3 小时 24 分钟，预计 18:00 下班');
    });

    test('lunch at 12:30 keeps counting down while pay is paused', () {
      final display = buildHomeTimeDisplay(
        snapshot: snapshot(now: DateTime.utc(2026, 11, 4, 4, 30)),
        calendar: calendar,
      );
      expect(display.state, HomeTimeState.breakTime);
      expect(display.tag, '休息中');
      expect(display.mainValue, '05:30:00');
      expect(display.detail, '预计 18:00 下班 · 休息中，工资暂停');
      expect(display.progressLabel, '今日计薪 3.0 / 8.0 小时');
    });

    test('before shift counts to the start and still shows the expected end', () {
      final display = buildHomeTimeDisplay(
        snapshot: snapshot(now: DateTime.utc(2026, 11, 4, 0, 45)),
        calendar: calendar,
      );
      expect(display.state, HomeTimeState.beforeShift);
      expect(display.tag, '未开始');
      expect(display.mainValue, '00:15:00');
      expect(display.detail, '09:00 上班 · 预计 18:00 下班');
      expect(display.progressLabel, '今日计薪 0.0 / 8.0 小时');
    });

    test('17:59:59.900 still shows 00:00:01; 18:00:00 is 已下班', () {
      final lastTick = buildHomeTimeDisplay(
        snapshot: snapshot(now: DateTime.utc(2026, 11, 4, 9, 59, 59, 900)),
        calendar: calendar,
      );
      expect(lastTick.state, HomeTimeState.working);
      expect(lastTick.mainValue, '00:00:01');

      final ended = buildHomeTimeDisplay(
        snapshot: snapshot(now: DateTime.utc(2026, 11, 4, 10)),
        calendar: calendar,
      );
      expect(ended.state, HomeTimeState.afterShift);
      expect(ended.label, '本班状态');
      expect(ended.mainValue, '已下班');
      expect(ended.detail, '18:00 已下班 · 固定支出继续分摊 · 下一班 次日 09:00');
      expect(ended.semanticsLabel, isNot(contains('00:00:00')));
    });

    test('a rest day is 今日休息 and hides progress', () {
      final display = buildHomeTimeDisplay(
        // Saturday 2026-11-07 12:00 CST.
        snapshot: snapshot(now: DateTime.utc(2026, 11, 7, 4)),
        calendar: calendar,
      );
      expect(display.state, HomeTimeState.restDay);
      expect(display.tag, '休息日');
      expect(display.mainValue, '今日休息');
      expect(display.showProgress, isFalse);
      expect(display.progress, isNull);
      expect(display.detail, startsWith('今天没有排班，好好休息'));
      expect(display.detail, contains('下一班 11月09日 09:00'));
    });

    test('missing schedule is 排班待确认, never a guessed rest day', () {
      final display = buildHomeTimeDisplay(
        snapshot: snapshot(schedules: const {}),
        calendar: calendar,
      );
      expect(display.state, HomeTimeState.unknown);
      expect(display.label, '排班状态');
      expect(display.mainValue, '排班待确认');
      expect(display.showProgress, isFalse);
      expect(display.detail, contains('还没有排班'));
    });

    test('invalid schedule points at the wage/schedule settings', () {
      final base = snapshot();
      final display = buildHomeTimeDisplay(
        snapshot: withTotal(
          base,
          base.total,
          notes: const [DashboardNote.invalidSchedule],
          workSession: WorkSessionContext.empty,
        ),
        calendar: calendar,
      );
      expect(display.state, HomeTimeState.unknown);
      expect(display.detail, contains('排班配置有误'));
    });

    test('22:00–06:00 crosses midnight without ending early', () {
      final night = ScheduleVersion(
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
      final beforeMidnight = buildHomeTimeDisplay(
        snapshot: snapshot(
          now: DateTime.utc(2026, 11, 30, 15, 59, 59),
          scheduleVersion: night,
        ),
        calendar: calendar,
      );
      expect(beforeMidnight.state, HomeTimeState.working);
      expect(beforeMidnight.mainValue, '06:00:01');
      expect(beforeMidnight.detail, '预计 次日 06:00 下班 · 按排班计薪');

      final afterMidnight = buildHomeTimeDisplay(
        snapshot: snapshot(
          now: DateTime.utc(2026, 11, 30, 16),
          scheduleVersion: night,
        ),
        calendar: calendar,
      );
      expect(afterMidnight.state, HomeTimeState.working);
      expect(afterMidnight.mainValue, '06:00:00');
      expect(afterMidnight.detail, '预计 06:00 下班 · 按排班计薪');

      final ended = buildHomeTimeDisplay(
        snapshot: snapshot(
          now: DateTime.utc(2026, 11, 30, 22),
          scheduleVersion: night,
        ),
        calendar: calendar,
      );
      expect(ended.state, HomeTimeState.afterShift);
      expect(ended.mainValue, '已下班');
      expect(ended.detail, startsWith('06:00 已下班'));
    });
  });

  group('balance card (HOME-DUAL-06/07)', () {
    test('complete negative uses the exact subtotal and 努力回本', () {
      final display = buildHomeBalanceDisplay(
        snapshot: referenceNegative(),
        calendar: calendar,
        tone: AppTone.gentle,
      );
      expect(display.tag, '努力回本');
      expect(display.amountText, '−¥55.26');
      expect(display.negative, isTrue);
      expect(display.neutral, isFalse);
      expect(display.completenessNote, isNull);
      expect(display.formula, '工资估算 + 投资今日浮动 − 固定支出已分摊');
      expect(display.semanticsLabel, contains('−¥55.26'));
    });

    test('complete positive and a true zero are both 暂时领先', () {
      final positive = buildHomeBalanceDisplay(
        snapshot: snapshot(),
        calendar: calendar,
        tone: AppTone.gentle,
      );
      expect(positive.tag, '暂时领先');
      expect(positive.negative, isFalse);
      expect(positive.amountText, startsWith('¥'));

      final base = snapshot();
      final zero = buildHomeBalanceDisplay(
        snapshot: withTotal(base, Rational.zero),
        calendar: calendar,
        tone: AppTone.gentle,
      );
      expect(zero.amountText, '¥0.00');
      expect(zero.tag, '暂时领先');
      expect(zero.negative, isFalse);
    });

    test('partial shows the known subtotal and names the missing class', () {
      final partial = snapshot(holdings: [stock()], quotes: const {});
      expect(partial.completeness, Completeness.partial);
      final display = buildHomeBalanceDisplay(
        snapshot: partial,
        calendar: calendar,
        tone: AppTone.gentle,
      );
      expect(display.tag, '部分小计');
      expect(display.neutral, isTrue);
      expect(display.completenessNote, contains('A股今日浮动'));
      expect(display.completenessNote, contains('不代表最终盈亏'));
      expect(display.semanticsLabel, contains('部分小计'));
    });

    test('unavailable never shows a fake zero or an old total', () {
      final base = snapshot();
      final display = buildHomeBalanceDisplay(
        snapshot: withTotal(
          base,
          null,
          completeness: Completeness.unavailable,
        ),
        calendar: calendar,
        tone: AppTone.gentle,
      );
      expect(display.tag, '不可计算');
      expect(display.amountText, '待配置');
      expect(display.known, isFalse);
      expect(display.neutral, isTrue);
      expect(display.completenessNote, contains('设置'));
      expect(display.semanticsLabel, contains('不可计算'));
      expect(display.semanticsLabel, isNot(contains('¥0.00')));
    });

    test('stale quotes are marked with the quote time, not computedAt', () {
      final base = snapshot();
      final display = buildHomeBalanceDisplay(
        snapshot: withTotal(
          base,
          base.total,
          quoteQuality: QuoteQuality.stale,
          // 13:00 CST, while the snapshot was computed at 14:36 CST.
          quotesAsOf: DateTime.utc(2026, 11, 4, 5),
        ),
        calendar: calendar,
        tone: AppTone.gentle,
      );
      expect(display.sourceNote, contains('缓存/陈旧'));
      expect(display.sourceNote, contains('13:00'));
      expect(display.sourceNote, isNot(contains('14:36')));
    });

    test('partial and stale are both visible at once', () {
      final partial = snapshot(holdings: [stock()], quotes: const {});
      final display = buildHomeBalanceDisplay(
        snapshot: withTotal(
          partial,
          partial.total,
          quoteQuality: QuoteQuality.stale,
          quotesAsOf: DateTime.utc(2026, 11, 4, 5),
        ),
        calendar: calendar,
        tone: AppTone.gentle,
      );
      expect(display.completenessNote, isNotNull);
      expect(display.sourceNote, contains('缓存/陈旧'));
    });

    test('large negative amounts keep every digit and the sign', () {
      final base = snapshot();
      final display = buildHomeBalanceDisplay(
        snapshot: withTotal(base, Rational.parse('-1234567.89')),
        calendar: calendar,
        tone: AppTone.gentle,
      );
      expect(display.amountText, '−¥1,234,567.89');
      expect(display.negative, isTrue);
    });

    test('harsh tone only changes the complete flavor line', () {
      final gentle = buildHomeBalanceDisplay(
        snapshot: referenceNegative(),
        calendar: calendar,
        tone: AppTone.gentle,
      );
      final harsh = buildHomeBalanceDisplay(
        snapshot: referenceNegative(),
        calendar: calendar,
        tone: AppTone.harsh,
      );
      expect(gentle.flavorLine, isNot(harsh.flavorLine));
      expect(gentle.tag, harsh.tag);
      expect(gentle.amountText, harsh.amountText);
    });
  });
}
